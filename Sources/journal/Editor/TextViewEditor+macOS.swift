#if canImport(AppKit)
    import SwiftUI
    import AppKit

    extension TextViewEditor {
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
    }

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
