import SwiftUI

/// Protocol describing editor backend. Aliased to `ActiveEditor`. Backends are
/// initialized with a `Binding<AttributedString>`.
protocol FloatsEditor: View {
  init(text: Binding<AttributedString>, commands: EditorCommands)
}

/// The editor the app actually uses today. Swap this line — not the call
/// sites — when migrating off the AppKit text view.
typealias ActiveEditor = TextViewEditor
