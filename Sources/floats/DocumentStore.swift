import Foundation

/// Persists the app's document to a file in the app's Application Support
/// directory. The document's source of truth is plain Markdown text — see
/// `MarkdownHighlighter` — so that's all that's saved; formatting is re-derived
/// on load the same way it is on every edit.
enum DocumentStore {
  private static let filename = "Document.md"

  private static var fileURL: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent(
      Bundle.main.bundleIdentifier ?? "floats", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(filename)
  }

  static func load() -> String {
    (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
  }

  static func save(_ text: String) {
    try? text.write(to: fileURL, atomically: true, encoding: .utf8)
  }
}
