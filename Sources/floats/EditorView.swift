import Crumpet
import SwiftUI

/// Top-level editing surface: the Crumpet library's `MarkdownEditor`
/// bound to the document text, wrapped in the floating-window plumbing this app
/// adds on top.
struct EditorView: View {
  // Seeded from disk so the first render already shows the saved document; see
  // `DocumentStore`. The Markdown source is the whole document state —
  // formatting is re-derived by the editor on every edit.
  @State private var text = DocumentStore.load()
  @State private var commands = EditorCommands()
  @State private var saveTask: Task<Void, Never>?
  @Environment(\.scenePhase) private var scenePhase

  // Editor typography and rendering options, shared with SettingsView through
  // the same defaults keys; changing them there re-renders this view and
  // restyles the editor live.
  @AppStorage(EditorSettings.defaultsKey) private var settings = EditorSettings()
  @AppStorage(EditorTheme.defaultsKey) private var theme = EditorTheme.system
  @AppStorage(EditorAppearance.defaultsKey) private var editorAppearance = EditorAppearance.system
  @AppStorage(EditorCustomColors.defaultsKey) private var customColors = EditorCustomColors()
  @Environment(\.colorScheme) private var systemAppearance

  // Whether the window floats above all other windows/spaces, persisted so it's
  // restored on relaunch. `windowBox` is how we reach the NSWindow a pure
  // SwiftUI scene never hands us directly.
  @AppStorage("isFloating") private var isFloating = false
  @State private var windowBox = WindowBox()

  /// The light or dark appearance the editor is using.
  private var appearance: ColorScheme { editorAppearance.resolved(systemAppearance) }

  /// The scheme in effect now, used to paint the surface around the editor.
  private var colorScheme: EditorColorScheme {
    theme.colorScheme(for: appearance, customColors: customColors)
  }

  var body: some View {
    MarkdownEditor(text: $text)
      .commands(commands)
      .editorSettings(settings)
      .editorSettingsChannel(AppSettings.editorChannel)
      .editorTheme(theme, customColors: customColors)
      .editorAppearance(editorAppearance)
      // Fills the window so the scrollbar sits at the window's edge; the text
      // itself is kept to a readable column inside the text view.
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // Resolves an adaptive background in the editor's appearance, which can
      // differ from the window's.
      .background { colorScheme.background.environment(\.colorScheme, appearance) }
      // Exposes this window's editor to the app-level Format menu.
      .focusedSceneValue(\.editorCommands, commands)
      // Resolves this window once SwiftUI creates it, then applies whatever
      // floating level was restored from disk.
      .background(
        WindowAccessor { window in
          windowBox.window = window
          applyFloating()
          windowBox.configureTrafficLightFading()
          // The pin lives in the title bar (see `installPinAccessory`), not in
          // the content, so it aligns with the traffic lights top-right.
          windowBox.installPinAccessory()
        }
      )
      .onChange(of: isFloating) { _, _ in applyFloating() }
      // Debounced so a typing burst writes to disk once it settles rather than
      // on every keystroke.
      .onChange(of: text) { _, newValue in
        saveTask?.cancel()
        saveTask = Task {
          try? await Task.sleep(for: .milliseconds(500))
          guard !Task.isCancelled else { return }
          DocumentStore.save(newValue)
        }
      }
      // Flush immediately when the window loses focus, backgrounds, or the app
      // quits, so a debounce in flight isn't lost.
      .onChange(of: scenePhase) { _, phase in
        guard phase != .active else { return }
        saveTask?.cancel()
        DocumentStore.save(text)
      }
  }

  /// Applies `isFloating` to the resolved window's level and space behavior. A
  /// no-op until `WindowAccessor` has resolved the window.
  private func applyFloating() {
    guard let window = windowBox.window else { return }
    window.level = isFloating ? .floating : .normal
    window.collectionBehavior = isFloating ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
  }
}

extension FocusedValues {
  /// Lets app-level menu commands reach the editor in the focused window.
  @Entry var editorCommands: EditorCommands?
}
