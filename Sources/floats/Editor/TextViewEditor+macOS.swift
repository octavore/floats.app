#if canImport(AppKit)
  import SwiftUI
  import AppKit

  extension TextViewEditor {
    func makeNSView(context: Context) -> NSScrollView {
      let scroll = NSScrollView()
      scroll.hasVerticalScroller = true
      scroll.drawsBackground = false
      scroll.borderType = .noBorder

      let tv = FloatsTextView(frame: .zero)
      tv.delegate = context.coordinator
      tv.isRichText = true
      tv.allowsUndo = true
      tv.drawsBackground = false
      tv.textContainerInset = NSSize(
        width: FloatsLayout.minInset, height: FloatsLayout.verticalInset)
      tv.typingAttributes = TextStyle.body.attributes
      tv.isVerticallyResizable = true
      tv.isHorizontallyResizable = false
      tv.autoresizingMask = [.width]
      tv.minSize = NSSize(width: 0, height: 0)
      tv.maxSize = NSSize(
        width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
      tv.textContainer?.widthTracksTextView = true

      // The highlighter is the storage's delegate: every character edit (typing,
      // paste, programmatic replacement) routes through its didProcessEditing,
      // which is the single trigger for incremental restyling.
      tv.textStorage?.delegate = context.coordinator.highlighter

      scroll.documentView = tv
      context.coordinator.textView = tv
      // Seed the applied face and spacing so the first updateNSView only
      // restyles if the saved values differ from the typing attributes set above.
      Typography.current = fontFamily
      context.coordinator.appliedFont = fontFamily
      Typography.lineSpacing = lineSpacingSetting
      context.coordinator.appliedLineSpacing = lineSpacingSetting
      return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
      // Switch typeface and line spacing first; if either changed, the document
      // was just restyled and the binding resynced, so skip the storage rebuild
      // below. Don't short-circuit with `||` — both need to run.
      let didApplyFont = context.coordinator.applyFont(fontFamily)
      let didApplyLineSpacing = context.coordinator.applyLineSpacing(lineSpacingSetting)
      if didApplyFont || didApplyLineSpacing { return }
      // While the text view is the live source of truth (typing in flight, its
      // binding sync still pending), don't rebuild the storage from the binding.
      if context.coordinator.isSyncingFromTextView { return }
      guard let tv = scroll.documentView as? NSTextView,
        let storage = tv.textStorage
      else { return }
      let desired = NSAttributedString(text)
      guard storage != desired else { return }
      let selected = tv.selectedRanges
      // Replacing the storage fires the highlighter's didProcessEditing, which
      // restyles the whole document; no explicit highlight call needed.
      storage.setAttributedString(desired)
      tv.selectedRanges = selected
    }
  }

  extension TextViewEditor.Coordinator: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
      // The storage delegate has already restyled the text; coalesce the costly
      // binding conversion so it runs once typing settles, not per keystroke.
      scheduleBindingSync()
    }
  }

  /// An `NSTextView` that normalizes pasted rich text into the app's type
  /// system instead of dumping in foreign fonts and attachments, and keeps the
  /// text in a centered, readable column while filling the scroll view.
  final class FloatsTextView: NSTextView {
    // Above the column width only the centering inset changes, not the text
    // layout. Without this, the view blits its cached bitmap during a live
    // resize and only re-centers once resizing stops; opting out forces a
    // continuous redraw so the column tracks the window smoothly.
    override var preservesContentDuringLiveResize: Bool { false }

    // The superview drives this on every live-resize step, whereas
    // `setFrameSize` gets coalesced and only lands once resizing stops —
    // which left the centered column lagging behind the window edge.
    override func resize(withOldSuperviewSize oldSize: NSSize) {
      super.resize(withOldSuperviewSize: oldSize)
      let inset = max(FloatsLayout.minInset, (bounds.width - FloatsLayout.maxTextWidth) / 2)
      if abs(textContainerInset.width - inset) > 0.5 {
        textContainerInset = NSSize(width: inset, height: FloatsLayout.verticalInset)
      }
    }

    override func paste(_ sender: Any?) {
      guard
        let pasted = NSPasteboard.general.readObjects(
          forClasses: [NSAttributedString.self], options: nil)?.first
          as? NSAttributedString
      else {
        super.paste(sender)
        return
      }
      let clean = TextStyle.sanitize(pasted: pasted)
      // insertText routes through undo and fires textDidChange, syncing
      // the binding, just like the user typing the text.
      insertText(clean, replacementRange: selectedRange())
    }
  }
#endif
