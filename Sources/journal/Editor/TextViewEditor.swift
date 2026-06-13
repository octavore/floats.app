import SwiftUI

#if canImport(UIKit)
    import UIKit
    import UniformTypeIdentifiers
#elseif canImport(AppKit)
    import AppKit
#endif

/// iOS-18 / macOS-14 editor backend: wraps `UITextView` / `NSTextView` behind
/// the `JournalEditor` seam. It reads and writes only `AttributedString`,
/// converting to `NSAttributedString` at the platform boundary.
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

    init(text: Binding<AttributedString>, commands: EditorCommands) {
        self._text = text
        self.commands = commands
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, commands: commands) }

    #if canImport(UIKit)
        func makeUIView(context: Context) -> UITextView {
            let tv = JournalTextView()
            tv.delegate = context.coordinator
            tv.backgroundColor = .clear
            tv.alwaysBounceVertical = true
            tv.textContainerInset = UIEdgeInsets(
                top: JournalLayout.verticalInset, left: JournalLayout.minInset,
                bottom: JournalLayout.verticalInset, right: JournalLayout.minInset)
            // Native bold/italic/underline in the selection edit menu. Note:
            // attribute-only edits made there bypass textViewDidChange, so the
            // binding catches up on the next text change.
            tv.allowsEditingTextAttributes = true
            tv.typingAttributes = TextStyle.body.attributes
            context.coordinator.textView = tv
            return tv
        }

        func updateUIView(_ tv: UITextView, context: Context) {
            if context.coordinator.textViewDidChange {
                context.coordinator.textViewDidChange = false
                return
            }
            let desired = NSAttributedString(text)
            guard tv.attributedText != desired else { return }
            let selected = tv.selectedRange
            tv.attributedText = desired
            tv.selectedRange = selected
        }

    #elseif canImport(AppKit)
        func makeNSView(context: Context) -> NSScrollView {
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            scroll.borderType = .noBorder

            let tv = JournalTextView(frame: .zero)
            tv.delegate = context.coordinator
            tv.isRichText = true
            tv.allowsUndo = true
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(
                width: JournalLayout.minInset, height: JournalLayout.verticalInset)
            tv.typingAttributes = TextStyle.body.attributes
            tv.isVerticallyResizable = true
            tv.isHorizontallyResizable = false
            tv.autoresizingMask = [.width]
            tv.minSize = NSSize(width: 0, height: 0)
            tv.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            tv.textContainer?.widthTracksTextView = true

            scroll.documentView = tv
            context.coordinator.textView = tv
            return scroll
        }

        func updateNSView(_ scroll: NSScrollView, context: Context) {
            if context.coordinator.textViewDidChange {
                context.coordinator.textViewDidChange = false
                return
            }
            guard let tv = scroll.documentView as? NSTextView,
                let storage = tv.textStorage
            else { return }
            let desired = NSAttributedString(text)
            guard storage != desired else { return }
            let selected = tv.selectedRanges
            storage.setAttributedString(desired)
            tv.selectedRanges = selected
        }
    #endif

    @MainActor
    final class Coordinator: NSObject {
        @Binding var text: AttributedString
        weak var textView: PlatformTextView?
        // Set when we push a change up through the binding so updateXxxView
        // can skip the redundant round-trip back into the text storage.
        var textViewDidChange = false

        init(text: Binding<AttributedString>, commands: EditorCommands) {
            self._text = text
            super.init()
            commands.handler = { [weak self] in self?.handle($0) }
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
            guard let tv = textView, let storage = tv.textStorage else { return }
            let selection = tv.selectedRange
            guard selection.length > 0 else {
                // Caret only: flip the trait for whatever gets typed next.
                let font = tv.typingAttributes[.font] as? PlatformFont ?? TextStyle.body.font
                tv.typingAttributes[.font] = font.toggling(trait)
                return
            }
            // Match the platforms' convention for mixed runs: if anything in
            // the selection lacks the trait, add it everywhere; only a
            // uniformly-styled selection toggles off.
            var allHaveTrait = true
            storage.enumerateAttribute(.font, in: selection) { value, _, stop in
                let font = value as? PlatformFont ?? TextStyle.body.font
                if !font.traits.contains(trait) {
                    allHaveTrait = false
                    stop.pointee = true
                }
            }
            performEdit(in: selection) { storage in
                storage.enumerateAttribute(.font, in: selection) { value, range, _ in
                    let font = value as? PlatformFont ?? TextStyle.body.font
                    let traits =
                        allHaveTrait
                        ? font.traits.subtracting(trait) : font.traits.union(trait)
                    storage.addAttribute(.font, value: font.with(traits: traits), range: range)
                }
            }
        }

        private func toggleUnderline() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let selection = tv.selectedRange
            guard selection.length > 0 else {
                let current = tv.typingAttributes[.underlineStyle] as? Int ?? 0
                if current == 0 {
                    tv.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                } else {
                    tv.typingAttributes.removeValue(forKey: .underlineStyle)
                }
                return
            }
            var allUnderlined = true
            storage.enumerateAttribute(.underlineStyle, in: selection) { value, _, stop in
                if (value as? Int ?? 0) == 0 {
                    allUnderlined = false
                    stop.pointee = true
                }
            }
            performEdit(in: selection) { storage in
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
            guard let tv = textView, let storage = tv.textStorage else { return }
            let paragraphs = (storage.string as NSString)
                .paragraphRange(for: tv.selectedRange)
            if paragraphs.length > 0 {
                performEdit(in: paragraphs) { storage in
                    storage.addAttribute(
                        .paragraphStyle, value: style.paragraphStyle, range: paragraphs)
                    storage.enumerateAttribute(.font, in: paragraphs) { value, range, _ in
                        let old = value as? PlatformFont ?? TextStyle.body.font
                        let kept = old.traits.intersection([.boldTrait, .italicTrait])
                        let font = style.font.with(traits: style.font.traits.union(kept))
                        storage.addAttribute(.font, value: font, range: range)
                    }
                }
            }
            tv.typingAttributes = style.attributes
        }

        // MARK: Plumbing

        /// Runs a programmatic attribute edit with undo support (macOS) and
        /// pushes the result back through the binding.
        private func performEdit(in range: NSRange, _ edit: (NSTextStorage) -> Void) {
            guard let tv = textView, let storage = tv.textStorage else { return }
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

#if canImport(UIKit)
    extension TextViewEditor.Coordinator: UITextViewDelegate {
        func textViewDidChange(_ textView: UITextView) {
            textViewDidChange = true
            text = AttributedString(textView.attributedText)
        }
    }

    /// A `UITextView` that normalizes pasted rich text into the journal's type
    /// system instead of dumping in foreign fonts and attachments, and keeps the
    /// text in a centered, readable column on wide (iPad) layouts.
    final class JournalTextView: UITextView {
        override func layoutSubviews() {
            super.layoutSubviews()
            let inset = max(JournalLayout.minInset, (bounds.width - JournalLayout.maxTextWidth) / 2)
            if abs(textContainerInset.left - inset) > 0.5 {
                textContainerInset = UIEdgeInsets(
                    top: JournalLayout.verticalInset, left: inset,
                    bottom: JournalLayout.verticalInset, right: inset)
            }
        }

        override func paste(_ sender: Any?) {
            guard let pasted = UIPasteboard.general.journalAttributedString() else {
                super.paste(sender)
                return
            }
            let clean = TextStyle.sanitize(pasted: pasted)
            let range = selectedRange
            textStorage.replaceCharacters(in: range, with: clean)
            selectedRange = NSRange(location: range.location + clean.length, length: 0)
            delegate?.textViewDidChange?(self)
        }
    }

    extension UIPasteboard {
        /// Best available attributed representation of the pasteboard: RTF when
        /// present (attachments are stripped downstream), else plain text.
        fileprivate func journalAttributedString() -> NSAttributedString? {
            if let data = data(forPasteboardType: UTType.rtf.identifier),
                let attr = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil)
            {
                return attr
            }
            return string.map { NSAttributedString(string: $0) }
        }
    }
#elseif canImport(AppKit)
    extension TextViewEditor.Coordinator: NSTextViewDelegate {
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                let storage = tv.textStorage
            else { return }
            textViewDidChange = true
            text = AttributedString(storage)
        }
    }

    /// An `NSTextView` that normalizes pasted rich text into the journal's type
    /// system instead of dumping in foreign fonts and attachments, and keeps the
    /// text in a centered, readable column while filling the scroll view.
    final class JournalTextView: NSTextView {
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
            let inset = max(JournalLayout.minInset, (bounds.width - JournalLayout.maxTextWidth) / 2)
            if abs(textContainerInset.width - inset) > 0.5 {
                textContainerInset = NSSize(width: inset, height: JournalLayout.verticalInset)
            }
        }

        override func paste(_ sender: Any?) {
            let pasteboard = NSPasteboard.general
            guard
                let pasted = pasteboard.readObjects(
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
