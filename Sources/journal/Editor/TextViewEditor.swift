import SwiftUI

/// Geometry shared by both platform backends: the text sits in a centered
/// column at most `maxTextWidth` wide, with `minInset` of breathing room on
/// narrow views, while the scroll view itself spans the whole window.
enum JournalLayout {
  static let maxTextWidth: CGFloat = 720
  static let minInset: CGFloat = 16
  static let verticalInset: CGFloat = 24
}

struct TextViewEditor: PlatformViewRepresentable, JournalEditor {
  @Binding var text: AttributedString
  let commands: EditorCommands

  func makeCoordinator() -> Coordinator { Coordinator(text: $text, commands: commands) }

  @MainActor
  final class Coordinator: NSObject {
    @Binding var text: AttributedString
    weak var textView: PlatformTextView?
    // Set when we push a change up through the binding so updateXxxView
    // can skip the redundant round-trip back into the text storage.
    var textViewDidChange = false
    // Block-based NotificationCenter tokens (iOS keyboard observers) to
    // unregister when the coordinator goes away. Empty on macOS. Mutated
    // only on the main actor; read once from the nonisolated deinit.
    nonisolated(unsafe) var observerTokens: [NSObjectProtocol] = []

    init(text: Binding<AttributedString>, commands: EditorCommands) {
      self._text = text
      super.init()
      commands.handler = { [weak self] in self?.handle($0) }
    }

    deinit {
      observerTokens.forEach(NotificationCenter.default.removeObserver)
    }

    private func handle(_ command: EditorCommand) {
      switch command {
      case .toggleBold: toggleTrait(.boldTrait)
      case .toggleItalic: toggleTrait(.italicTrait)
      case .toggleUnderline: toggleUnderline()
      case .setBlockStyle(let style): apply(style)
      }
    }

    // MARK: Inline traits

    private func toggleTrait(_ trait: FontTraits) {
      mutateSelection { tv in
        // Caret only: flip the trait for whatever gets typed next.
        tv.typingAttributes[.font] = font(tv.typingAttributes[.font]).toggling(trait)
      } selection: { storage, selection in
        // Match the platforms' convention for mixed runs: if anything
        // in the selection lacks the trait, add it everywhere; only a
        // uniformly-styled selection toggles off.
        var allHaveTrait = true
        storage.enumerateAttribute(.font, in: selection) { value, _, stop in
          if !font(value).traits.contains(trait) {
            allHaveTrait = false
            stop.pointee = true
          }
        }
        storage.enumerateAttribute(.font, in: selection) { value, range, _ in
          let f = font(value)
          let traits =
            allHaveTrait
            ? f.traits.subtracting(trait) : f.traits.union(trait)
          storage.addAttribute(.font, value: f.with(traits: traits), range: range)
        }
      }
    }

    private func toggleUnderline() {
      mutateSelection { tv in
        if (tv.typingAttributes[.underlineStyle] as? Int ?? 0) == 0 {
          tv.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        } else {
          tv.typingAttributes.removeValue(forKey: .underlineStyle)
        }
      } selection: { storage, selection in
        var allUnderlined = true
        storage.enumerateAttribute(.underlineStyle, in: selection) { value, _, stop in
          if (value as? Int ?? 0) == 0 {
            allUnderlined = false
            stop.pointee = true
          }
        }
        if allUnderlined {
          storage.removeAttribute(.underlineStyle, range: selection)
        } else {
          storage.addAttribute(
            .underlineStyle, value: NSUnderlineStyle.single.rawValue,
            range: selection)
        }
      }
    }

    // MARK: Block styles

    /// Restyles every paragraph touched by the selection, keeping any
    /// bold/italic the writer applied within it.
    private func apply(_ style: TextStyle) {
      guard let tv = textView, let storage = tv.optionalTextStorage else { return }

      // apply to the typing attributes so new text gets the new style
      tv.typingAttributes = style.attributes

      // get selected paragraphs and apply the new paragraph style to all
      // also preserve any bold/italic traits within the paragraphs
      let paragraphs = (storage.string as NSString)
        .paragraphRange(for: tv.selectedRange)
      if paragraphs.length > 0 {
        performEdit(in: paragraphs) { storage in
          storage.addAttribute(
            .paragraphStyle, value: style.paragraphStyle, range: paragraphs)
          storage.enumerateAttribute(.font, in: paragraphs) { value, range, _ in
            let old = font(value)
            // keep existing bold/italic traits
            let kept = old.traits.intersection([.boldTrait, .italicTrait])
            // apply the new style's font traits (e.g. weight, size)
            let font = style.font.with(traits: style.font.traits.union(kept))
            storage.addAttribute(.font, value: font, range: range)
          }
        }
      }
    }

    // MARK: Plumbing

    /// A font attribute value, or the body font when a run is missing one.
    private func font(_ value: Any?) -> PlatformFont {
      value as? PlatformFont ?? TextStyle.body.font
    }

    /// Shared scaffold for the inline toggles: routes a caret-only edit to
    /// the typing attributes, and a ranged selection through `performEdit`.
    private func mutateSelection(
      caret: (PlatformTextView) -> Void,
      selection: (NSTextStorage, NSRange) -> Void
    ) {
      guard let tv = textView, let storage = tv.optionalTextStorage else { return }
      let range = tv.selectedRange
      guard range.length > 0 else {
        caret(tv)
        return
      }
      performEdit(in: range) { selection($0, range) }
    }

    /// Runs a programmatic attribute edit with undo support (macOS) and
    /// pushes the result back through the binding.
    private func performEdit(in range: NSRange, _ edit: (NSTextStorage) -> Void) {
      guard let tv = textView, let storage = tv.optionalTextStorage else { return }
      #if canImport(AppKit)
        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
      #endif
      storage.beginEditing()
      edit(storage)
      storage.endEditing()
      #if canImport(AppKit)
        // Registers undo and fires textDidChange, which syncs the binding.
        tv.didChangeText()
      #else
        text = AttributedString(storage)
      #endif
    }
  }
}
