import SwiftUI

/// Top-level editing surface. Owns the document text and hands it to whichever
/// backend `ActiveEditor` resolves to. A centered, max-width column keeps long
/// lines readable on a wide macOS window.
struct EditorView: View {
  // Seeded from disk so the first render already shows the saved document;
  // see `DocumentStore`. The source of truth is the plain Markdown text —
  // formatting is re-derived by the highlighter, same as on every edit.
  @State private var text = AttributedString(DocumentStore.load())
  @State private var commands = EditorCommands()
  @State private var saveTask: Task<Void, Never>?
  @Environment(\.scenePhase) private var scenePhase

  // The selected typeface and line spacing, shared with SettingsView through
  // the same defaults keys; changing them there re-renders this view and
  // restyles the editor.
  @AppStorage(FloatsFont.defaultsKey) private var fontFamily: FloatsFont = .system
  @AppStorage(LineSpacing.defaultsKey) private var lineSpacing: LineSpacing = .normal

  // Whether the window floats above all other windows/spaces, persisted so
  // it's restored on relaunch. `windowBox` is how we reach the NSWindow a
  // pure SwiftUI scene never hands us directly.
  @AppStorage("isFloating") private var isFloating = false
  @State private var windowBox = WindowBox()

  /// The editor backend configured with the current typeface. Built here rather
  /// than inline so `fontFamily` can be set after the `FloatsEditor` init.
  private var editor: ActiveEditor {
    var editor = ActiveEditor(text: $text, commands: commands)
    editor.fontFamily = fontFamily
    editor.lineSpacingSetting = lineSpacing
    return editor
  }

  var body: some View {
    editor
      // Fills the window so the scrollbar sits at the window's edge; the
      // text itself is kept to a readable column inside the text view.
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(PlatformColor.editorBackground))
      // Exposes this window's editor to the app-level Format menu.
      .focusedSceneValue(\.editorCommands, commands)
      // Resolves this window once SwiftUI creates it, then applies whatever
      // floating level was restored from disk.
      .background(
        WindowAccessor { window in
          windowBox.window = window
          applyFloating()
          windowBox.configureTrafficLightFading()
          // The pin lives in the title bar (see `installPinAccessory`), not
          // in the content, so it aligns with the traffic lights top-right.
          windowBox.installPinAccessory()
        }
      )
      .onChange(of: isFloating) { _, _ in applyFloating() }
      // Debounced so a typing burst writes to disk once it settles rather
      // than on every keystroke, matching the binding-sync debounce upstream.
      .onChange(of: text) { _, newValue in
        saveTask?.cancel()
        saveTask = Task {
          try? await Task.sleep(for: .milliseconds(500))
          guard !Task.isCancelled else { return }
          DocumentStore.save(String(newValue.characters))
        }
      }
      // Belt-and-suspenders: flush immediately when the window loses focus,
      // backgrounds, or the app quits, so a debounce in flight isn't lost.
      .onChange(of: scenePhase) { _, phase in
        guard phase != .active else { return }
        saveTask?.cancel()
        DocumentStore.save(String(text.characters))
      }
  }

  /// Applies `isFloating` to the resolved window's level and space behavior.
  /// A no-op until `WindowAccessor` has resolved the window.
  private func applyFloating() {
    guard let window = windowBox.window else { return }
    window.level = isFloating ? .floating : .normal
    window.collectionBehavior = isFloating ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
  }
}
