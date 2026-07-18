import SwiftUI

/// The app's settings: the editor typeface and its line spacing. Both are
/// persisted via `@AppStorage` under the same keys `EditorView` reads, so
/// changing them here updates the editor live.
///
/// Presented as the standard Settings window (⌘,).
struct SettingsView: View {
  @AppStorage(FloatsFont.defaultsKey) private var fontFamily: FloatsFont = .system
  @AppStorage(LineSpacing.defaultsKey) private var lineSpacing: LineSpacing = .normal

  var body: some View {
    Form {
      fontPicker
      lineSpacingPicker
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

  private var lineSpacingPicker: some View {
    Picker("Line Spacing", selection: $lineSpacing) {
      ForEach(LineSpacing.allCases) { spacing in
        Text(spacing.displayName).tag(spacing)
      }
    }
  }
}
