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
    // Each tab sets its own size; the Settings window resizes to match.
    TabView {
      GeneralSettingsView()
        .frame(width: 460, height: 460, alignment: .top)
        .tabItem { Label("General", systemImage: "gearshape") }
      EditorSettingsTab()
        .frame(width: 460, height: 460, alignment: .top)
        .tabItem { Label("Editor", systemImage: "textformat") }
      ThemeSettingsTab()
        .frame(width: 560, height: 560, alignment: .top)
        .tabItem { Label("Theme", systemImage: "paintpalette") }
      ScrollView {
        SunshineUpdateSettingsView(controller: updaterUI, appName: "floats")
      }
      .frame(width: 460, height: 460, alignment: .top)
      .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
    }
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

/// The library's pre-built `EditorSettingsForm`. Persisted under
/// `EditorSettings.defaultsKey`, the same key `EditorView` reads.
private struct EditorSettingsTab: View {
  @AppStorage(EditorSettings.defaultsKey) private var settings = EditorSettings()

  var body: some View {
    Form {
      EditorSettingsForm(settings: $settings)
    }
    .formStyle(.automatic)
    .padding(32)
    // Make a slider drag visible in the editor window while it happens;
    // `@AppStorage` alone only lands the change at mouse-up.
    .onChange(of: settings) { _, new in AppSettings.editorChannel.send(new) }
  }
}

/// The library's pre-built `EditorThemeForm` with the Custom theme enabled.
/// The theme, appearance, and custom colors persist under their own keys,
/// which `EditorView` reads.
private struct ThemeSettingsTab: View {
  @AppStorage(EditorTheme.defaultsKey) private var theme = EditorTheme.system
  @AppStorage(EditorAppearance.defaultsKey) private var appearance = EditorAppearance.system
  @AppStorage(EditorCustomColors.defaultsKey) private var customColors = EditorCustomColors()

  var body: some View {
    // Grouped so the theme cards and preview span the full width, and the
    // form scrolls when the Custom theme's rows exceed the window.
    Form {
      EditorThemeForm(theme: $theme, appearance: $appearance, customColors: $customColors)
    }
    .formStyle(.grouped)
  }
}

extension EditorTheme {
  /// `@AppStorage` key for the selected theme.
  static let defaultsKey = "editorTheme"
}

extension EditorAppearance {
  /// `@AppStorage` key for the light or dark appearance.
  static let defaultsKey = "editorAppearance"
}

extension EditorCustomColors {
  /// `@AppStorage` key for the Custom theme's colors.
  static let defaultsKey = "customColorScheme"
}
