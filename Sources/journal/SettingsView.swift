import SwiftUI

/// The journal's settings. Today it's just the editor typeface; the choice is
/// persisted via `@AppStorage` under `JournalFont.defaultsKey`, the same key
/// `EditorView` reads, so selecting a font here updates the editor live.
///
/// Presented as the standard Settings window (⌘,) on macOS and as a sheet on
/// iOS — both render this same view.
struct SettingsView: View {
  @AppStorage(JournalFont.defaultsKey) private var fontFamily: JournalFont = .system

  #if os(iOS)
    @Environment(\.dismiss) private var dismiss
  #endif

  var body: some View {
    #if os(macOS)
      Form {
        fontPicker
      }
      .padding(20)
      .frame(width: 340)
    #else
      NavigationStack {
        Form {
          fontPicker
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
      }
    #endif
  }

  private var fontPicker: some View {
    Picker("Editor Font", selection: $fontFamily) {
      ForEach(JournalFont.allCases) { font in
        // Render each option in its own typeface so the menu previews the choice.
        Text(font.displayName).font(font.previewFont).tag(font)
      }
    }
    #if os(iOS)
      .pickerStyle(.inline)
    #endif
  }
}
