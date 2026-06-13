import SwiftUI

/// Top-level editing surface. Owns the document text and hands it to whichever
/// backend `ActiveEditor` resolves to. A centered, max-width column keeps long
/// lines readable on a wide macOS window.
struct EditorView: View {
    @State private var text = AttributedString()
    @State private var commands = EditorCommands()

    var body: some View {
        ActiveEditor(text: $text, commands: commands)
            // Fills the window so the scrollbar sits at the window's edge; the
            // text itself is kept to a readable column inside the text view.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(PlatformColor.editorBackground))
            // Exposes this window's editor to the app-level Format menu.
            .focusedSceneValue(\.editorCommands, commands)
            #if os(iOS)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Menu {
                            ForEach(TextStyle.allCases) { style in
                                Button(style.displayName) {
                                    commands.send(.setBlockStyle(style))
                                }
                            }
                        } label: {
                            Label("Style", systemImage: "textformat.size")
                        }
                        Spacer()
                        Button {
                            commands.send(.toggleBold)
                        } label: {
                            Label("Bold", systemImage: "bold")
                        }
                        Button {
                            commands.send(.toggleItalic)
                        } label: {
                            Label("Italic", systemImage: "italic")
                        }
                        Button {
                            commands.send(.toggleUnderline)
                        } label: {
                            Label("Underline", systemImage: "underline")
                        }
                    }
                }
            #endif
    }
}
