import Crumpet
import SunshineUI
import SwiftUI

extension EditorSettings {
  /// Shared `@AppStorage` key for the whole editor typography bundle. `EditorView`
  /// reads the same key, so a change in the Settings window restyles the editor
  /// live.
  static let defaultsKey = "editorSettings"
}

/// App-wide singletons that both the `Settings` scene and the main `Window`
/// reach. A `Settings` scene shares no state with a `Window`, so the channel
/// lives here where both can find it.
enum AppSettings {
  /// Pushes each slider step to every open editor mid-drag, before SwiftUI
  /// re-evaluates the editor's view in the other window.
  @MainActor static let editorChannel = EditorSettingsChannel()
}

/// The Settings window (⌘,). A tabbed shell following the macOS conventions:
/// one `Label` per tab, a fixed frame, top-aligned content.
struct SettingsView: View {
  /// The updates controller, backing the "Updates" tab.
  @ObservedObject var updaterUI: SunshineUpdaterUIController

  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }
      EditorSettingsTab()
        .tabItem { Label("Editor", systemImage: "textformat") }
      ScrollView {
        SunshineUpdateSettingsView(controller: updaterUI, appName: "floats")
      }
      .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
    }
    .frame(width: 460, height: 460, alignment: .top)
    .navigationTitle("floats")
  }
}

/// Window behavior that isn't part of the editor itself.
private struct GeneralSettingsView: View {
  @AppStorage("isFloating") private var isFloating = false

  var body: some View {
    Form {
      Toggle(isOn: $isFloating) {
        Text("Float on top")
        Text("Keep the window above other apps and visible on every Space.")
      }
    }
    .formStyle(.automatic)
    .padding(32)
  }
}

/// The library's pre-built `EditorSettingsForm`, plus this app's own colorful
/// syntax toggle. Persisted under `EditorSettings.defaultsKey`, the same key
/// `EditorView` reads.
private struct EditorSettingsTab: View {
  @AppStorage(EditorSettings.defaultsKey) private var settings = EditorSettings()
  @AppStorage(EditorColorScheme.colorfulDefaultsKey) private var colorfulSyntax = false

  var body: some View {
    Form {
      EditorSettingsForm(settings: $settings)
      Toggle("Colorful Syntax", isOn: $colorfulSyntax)
    }
    .formStyle(.automatic)
    .padding(32)
    // Make a slider drag visible in the editor window while it happens;
    // `@AppStorage` alone only lands the change at mouse-up.
    .onChange(of: settings) { _, new in AppSettings.editorChannel.send(new) }
  }
}

/// The app's syntax palette, showing how a host defines its own
/// `EditorColorScheme` via the library's public initializer.
extension EditorColorScheme {
  static let colorfulDefaultsKey = "colorfulSyntax"

  static let colorful = EditorColorScheme(
    heading: .blue,
    code: .pink,
    bold: .orange,
    italic: .teal
  )
}
