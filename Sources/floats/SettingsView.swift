import SwiftUI

/// The app's settings. Today it's just the editor typeface; the choice is
/// persisted via `@AppStorage` under `FloatsFont.defaultsKey`, the same key
/// `EditorView` reads, so selecting a font here updates the editor live.
///
/// Presented as the standard Settings window (⌘,).
struct SettingsView: View {
  @AppStorage(FloatsFont.defaultsKey) private var fontFamily: FloatsFont = .system

  var body: some View {
    Form {
      fontPicker
    }
    .padding(20)
    .frame(width: 340)
  }

  private var fontPicker: some View {
    Picker("Editor Font", selection: $fontFamily) {
      ForEach(FloatsFont.allCases) { font in
        // Render each option in its own typeface so the menu previews the choice.
        Text(font.displayName).font(font.previewFont).tag(font)
      }
    }
  }
}
