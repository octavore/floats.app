import SwiftUI

@main
struct JournalApp: App {
  var body: some Scene {
    WindowGroup {
      EditorView()
    }
    #if os(macOS)
      .windowStyle(.hiddenTitleBar)
    #endif
    .commands {
      FormatCommands()
    }
  }
}

/// App-level Format menu (and hardware-keyboard shortcuts on iPad). Reaches
/// the focused window's editor through the focused-scene value, so the menu
/// stays decoupled from whichever backend is active.
struct FormatCommands: Commands {
  @FocusedValue(\.editorCommands) private var commands

  var body: some Commands {
    CommandMenu("Format") {
      Button("Bold") { commands?.send(.toggleBold) }
        .keyboardShortcut("b")
      Button("Italic") { commands?.send(.toggleItalic) }
        .keyboardShortcut("i")
      Button("Underline") { commands?.send(.toggleUnderline) }
        .keyboardShortcut("u")
      Divider()
      ForEach(TextStyle.allCases) { style in
        Button(style.displayName) { commands?.send(.setBlockStyle(style)) }
          .keyboardShortcut(style.shortcutKey, modifiers: [.command, .option])
      }
    }
  }
}
