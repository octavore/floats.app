#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers

    extension TextViewEditor {
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
    }

    extension TextViewEditor.Coordinator: UITextViewDelegate {
        func textViewDidChange(_ textView: UITextView) {
            textViewDidChange = true
            text = AttributedString(textView.attributedText)
        }
    }

    /// A `UITextView` that normalizes pasted rich text into the journal's type
    /// system instead of dumping in foreign fonts and attachments, keeps the
    /// text in a centered, readable column on wide (iPad) layouts, and opts out
    /// of intrinsic content sizing so SwiftUI lets it scroll.
    final class JournalTextView: UITextView {
        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }

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
#endif
