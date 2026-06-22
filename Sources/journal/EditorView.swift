import SwiftUI

/// Top-level editing surface. Owns the document text and hands it to whichever
/// backend `ActiveEditor` resolves to. A centered, max-width column keeps long
/// lines readable on a wide macOS window.
struct EditorView: View {
  @State private var text = AttributedString()
  @State private var commands = EditorCommands()

  // The selected typeface, shared with SettingsView through the same defaults
  // key; changing it there re-renders this view and restyles the editor.
  @AppStorage(JournalFont.defaultsKey) private var fontFamily: JournalFont = .system

  #if os(iOS)
    @State private var showingSettings = false
  #endif

  /// The editor backend configured with the current typeface. Built here rather
  /// than inline so `fontFamily` can be set after the `JournalEditor` init.
  private var editor: ActiveEditor {
    var editor = ActiveEditor(text: $text, commands: commands)
    editor.fontFamily = fontFamily
    return editor
  }

  var body: some View {
    editor
      // Fills the window so the scrollbar sits at the window's edge; the
      // text itself is kept to a readable column inside the text view.
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(PlatformColor.editorBackground))
      // Opt out of SwiftUI's automatic keyboard avoidance; the UITextView
      // adjusts its own contentInset to keep content visible above the keyboard.
      #if os(iOS)
        .ignoresSafeArea(.keyboard)
      #endif
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
              showingSettings = true
            } label: {
              Label("Settings", systemImage: "gearshape")
            }
          }
        }
        .sheet(isPresented: $showingSettings) {
          SettingsView()
        }
      #endif
  }
}
