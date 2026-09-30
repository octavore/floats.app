import Crumpet
import SunshineCore
import SunshineUI
import SwiftUI

@main
struct FloatsApp: App {
  @StateObject private var updaterUI = SunshineUpdaterUIController(
    updater: SunshineUpdater(
      configuration: SunshineConfiguration(
        owner: "octavore",
        repo: "floats.app",
        checkInterval: 3600
      ))
  )

  init() {
    SunshineUpdater.confirmSuccessfulRelaunchIfNeeded()
  }

  var body: some Scene {
    // A single, non-duplicable window — this app is one document, not a
    // multi-window editor, so there's no "New Window" command to remove.
    Window("floats", id: "main") {
      EditorView()
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(removing: .title)
        .sunshineUpdater(updaterUI)
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 480, height: 360)
    .commands {
      AboutCommand()
      FormatCommands()
      InsertCommands()
      FloatCommands()
      CheckForUpdatesCommand(updaterUI)
    }

    Settings {
      SettingsView(updaterUI: updaterUI)
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

/// Insert menu with date and time stamps at the cursor (⇧⌘7, ⇧⌘8, ⇧⌘9).
struct InsertCommands: Commands {
  @FocusedValue(\.editorCommands) private var commands

  private static let stamps: [(title: String, key: KeyEquivalent, format: String)] = [
    ("Date and Time", "7", "MMM d, yyyy 'at' h:mm a"),
    ("Date", "8", "MMM d, yyyy"),
    ("ISO Date", "9", "yyyy-MM-dd"),
  ]

  var body: some Commands {
    CommandMenu("Insert") {
      ForEach(Self.stamps, id: \.key.character) { stamp in
        Button(stamp.title) { commands?.send(.insertText(Self.format(stamp.format))) }
          .keyboardShortcut(stamp.key, modifiers: [.command, .shift])
      }
    }
  }

  private static func format(_ pattern: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = pattern
    return formatter.string(from: Date())
  }
}

/// App-level Format menu. Reaches the focused window's editor through the
/// focused-scene value, so the menu stays decoupled from whichever backend
/// is active.
struct FormatCommands: Commands {
  @FocusedValue(\.editorCommands) private var commands

  // The editor has no font-size command; ⌘+/⌘- nudge the same persisted
  // `EditorSettings` bundle the Settings window and `EditorView` read.
  @AppStorage(EditorSettings.defaultsKey) private var settings = EditorSettings()

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
      Button("Increase Font Size") { adjustFontSize(by: 1) }
        .keyboardShortcut("+", modifiers: .command)
      Button("Decrease Font Size") { adjustFontSize(by: -1) }
        .keyboardShortcut("-", modifiers: .command)
    }
  }

  private func adjustFontSize(by step: Double) {
    let range = Typography.sizeRange
    settings.fontSize = min(range.upperBound, max(range.lowerBound, settings.fontSize + step))
    AppSettings.editorChannel.send(settings)
  }
}
