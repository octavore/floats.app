import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// The journal's type scale: every block of text is one of these styles.
/// A style owns both the font and the paragraph treatment (line height,
/// spacing), so changing the scale here restyles the whole app.
enum TextStyle: String, CaseIterable, Identifiable {
    case title
    case heading
    case body

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .title: "Title"
        case .heading: "Heading"
        case .body: "Body"
        }
    }

    var font: PlatformFont {
        switch self {
        case .title: .systemFont(ofSize: 28, weight: .bold)
        case .heading: .systemFont(ofSize: 22, weight: .semibold)
        case .body: .systemFont(ofSize: 17)
        }
    }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch self {
        case .title:
            style.paragraphSpacing = 12
        case .heading:
            style.paragraphSpacingBefore = 12
            style.paragraphSpacing = 6
        case .body:
            style.lineHeightMultiple = 1.25
            style.paragraphSpacing = 8
        }
        return style
    }

    var attributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: PlatformColor.editorText,
        ]
    }

    /// Menu shortcut: ⌥⌘1 title, ⌥⌘2 heading, ⌥⌘0 body.
    var shortcutKey: KeyEquivalent {
        switch self {
        case .title: "1"
        case .heading: "2"
        case .body: "0"
        }
    }

    /// Normalizes externally-pasted rich text into the journal's type system.
    ///
    /// Foreign rich text arrives carrying `NSTextAttachment`s (inline images,
    /// list markers, …) and fonts the editor can't round-trip. The attachments
    /// don't survive `NSAttributedString` ↔ `AttributedString`, but the U+FFFC
    /// object-replacement characters they sit on do — which is what renders as
    /// "boxes with question marks." This re-bases every run onto the body font,
    /// preserves only bold/italic/underline, and drops attachments and any
    /// other styling so pasted text matches the surrounding journal.
    static func sanitize(pasted input: NSAttributedString) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let full = NSRange(location: 0, length: input.length)
        input.enumerateAttributes(in: full) { attrs, range, _ in
            // Skip attachment runs outright; strip any stray U+FFFC elsewhere.
            if attrs[.attachment] != nil { return }
            let text = (input.string as NSString)
                .substring(with: range)
                .replacingOccurrences(of: "\u{FFFC}", with: "")
            guard !text.isEmpty else { return }

            var clean = body.attributes
            let traits = (attrs[.font] as? PlatformFont)?
                .traits.intersection([.boldTrait, .italicTrait]) ?? []
            if !traits.isEmpty {
                clean[.font] = body.font.with(traits: traits)
            }
            if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
                clean[.underlineStyle] = underline
            }
            output.append(NSAttributedString(string: text, attributes: clean))
        }
        return output
    }
}
