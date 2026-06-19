import XCTest

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

@testable import journal

/// Isolates the two per-keystroke costs on a large (≈1.2M character, "Moby
/// Dick"-sized) document so we can see where the latency actually is:
///   - `testIncrementalEditLatency` times one character edit going through the
///     storage delegate (parse + scoped restyle).
///   - `testBindingConversionLatency` times `AttributedString(storage)`, the
///     whole-document conversion the coordinator pushes through the binding.
/// If the second dominates the first, the binding sync — not the highlighter —
/// is the bottleneck.
@MainActor
final class PerformanceTests: XCTestCase {

  /// ≈1.2M characters of markdown-flavored text with spans on every line.
  private func bigDocument() -> String {
    String(
      repeating: "The quick brown fox **jumps** over the lazy dog. `code` here.\n",
      count: 20_000)
  }

  func testIncrementalEditLatency() {
    let storage = NSTextStorage(string: bigDocument())
    let highlighter = MarkdownHighlighter()
    storage.delegate = highlighter
    highlighter.highlight(storage)  // initial full parse

    // Edit near the end — the worst case for any length-proportional work.
    let at = (storage.string as NSString).length - 5
    measure {
      storage.replaceCharacters(in: NSRange(location: at, length: 0), with: "x")
    }
  }

  func testBindingConversionLatency() {
    let storage = NSTextStorage(string: bigDocument())
    let highlighter = MarkdownHighlighter()
    storage.delegate = highlighter
    highlighter.highlight(storage)

    measure {
      _ = AttributedString(storage)
    }
  }
}
