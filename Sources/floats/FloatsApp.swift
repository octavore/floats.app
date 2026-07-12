import SwiftUI

@main
struct FloatsApp: App {
  var body: some Scene {
    // A single, non-duplicable window — this app is one document, not a
    // multi-window editor, so there's no "New Window" command to remove.
    Window("floats", id: "main") {
      EditorView()
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 480, height: 360)
    .commands {
      AboutCommand()
      FormatCommands()
      FloatCommands()
    }

    Settings {
      SettingsView()
    }
  }
}

/// Replaces the standard About panel to link to the app's homepage and
/// drop the build number, which is meaningless to end users.
struct AboutCommand: Commands {
  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("about floats") {
        NSApp.orderFrontStandardAboutPanel(options: [
          .applicationVersion: Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
          .credits: NSAttributedString(
            string: "https://github.com/octavore/floats.app",
            attributes: [.link: URL(string: "https://github.com/octavore/floats.app")!]
          ),
        ])
      }
    }
  }
}

/// Keyboard entry point (⇧⌘F) for the float toggle, since the pin now lives
/// in the title bar as an accessory rather than a focusable SwiftUI button.
/// Drives the same `isFloating` default the title-bar pin and `EditorView`
/// observe, so all three stay in sync.
struct FloatCommands: Commands {
  @AppStorage("isFloating") private var isFloating = false

  var body: some Commands {
    CommandGroup(after: .toolbar) {
      Button(isFloating ? "Stop Floating on Top" : "Float on Top") {
        isFloating.toggle()
      }
      .keyboardShortcut("f", modifiers: [.command, .shift])
    }
  }
}

/// App-level Format menu. Reaches the focused window's editor through the
/// focused-scene value, so the menu stays decoupled from whichever backend
/// is active.
struct FormatCommands: Commands {
  @FocusedValue(\.editorCommands) private var commands

  var body: some Commands {
    CommandMenu("Format") {
      Button("Bold") { commands?.send(.toggleBold) }
        .keyboardShortcut("b")
      Button("Italic") { commands?.send(.toggleItalic) }
        .keyboardShortcut("i")
      Divider()
      ForEach(TextStyle.allCases) { style in
        Button(style.displayName) { commands?.send(.setBlockStyle(style)) }
          .keyboardShortcut(style.shortcutKey, modifiers: [.command, .option])
      }
      Divider()
      Button("Increase Font Size") { commands?.send(.increaseFontSize) }
        .keyboardShortcut("+", modifiers: .command)
      Button("Decrease Font Size") { commands?.send(.decreaseFontSize) }
        .keyboardShortcut("-", modifiers: .command)
    }
  }
}
