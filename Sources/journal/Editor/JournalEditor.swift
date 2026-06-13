import SwiftUI

/// The seam.
///
/// Every editor backend conforms to this; the rest of the app only ever
/// constructs `ActiveEditor` and hands it a `Binding<AttributedString>`.
/// The model type (`AttributedString`) never changes — to adopt SwiftUI's
/// AttributedString-backed `TextEditor` (iOS 26 / macOS 26) later, write a
/// conforming view and point `ActiveEditor` at it. Nothing else moves.
protocol JournalEditor: View {
    init(text: Binding<AttributedString>, commands: EditorCommands)
}

/// The editor the app actually uses today. Swap this line — not the call
/// sites — when migrating off the UIKit/AppKit text view.
typealias ActiveEditor = TextViewEditor
