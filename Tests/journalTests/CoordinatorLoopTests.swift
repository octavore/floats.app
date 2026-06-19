import SwiftUI
import XCTest

#if canImport(AppKit)
  import AppKit
#endif

@testable import journal

/// Reproduces the *entire* macOS editing loop: a real NSTextView wired to the
/// real `Coordinator` as its delegate, typing through `insertText` (which fires
/// `textDidChange`), then running what `updateNSView` does when SwiftUI reacts
/// to the binding the coordinator just wrote. This is the one path the
/// storage-only and highlighter-only tests don't cover.
@MainActor
final class CoordinatorLoopTests: XCTestCase {
  #if canImport(AppKit)
    /// Mirrors the body of `TextViewEditor.updateNSView` for a given coordinator
    /// + text view, so we can run the SwiftUI side of the loop in a test.
    private func runUpdate(_ coordinator: TextViewEditor.Coordinator, _ tv: NSTextView) {
      if coordinator.textViewDidChange {
        coordinator.textViewDidChange = false
        return
      }
      guard let storage = tv.textStorage else { return }
      let desired = NSAttributedString(coordinator.text)
      guard storage != desired else { return }
      let selected = tv.selectedRanges
      // Replacing the storage fires the highlighter (the storage delegate),
      // which restyles; no explicit highlight call, mirroring updateNSView.
      storage.setAttributedString(desired)
      tv.selectedRanges = selected
    }

    /// Runs the main queue until everything already enqueued has executed.
    private func drainMainQueue() {
      let exp = expectation(description: "drain main queue")
      DispatchQueue.main.async { exp.fulfill() }
      wait(for: [exp], timeout: 1)
    }

    private func isMono(_ storage: NSTextStorage, at loc: Int) -> Bool {
      let f = storage.attribute(.font, at: loc, effectiveRange: nil) as? PlatformFont
      return f?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false
    }

    func testTypingThroughCoordinatorLoopStylesCode() {
      var backing = AttributedString("")
      let binding = Binding(get: { backing }, set: { backing = $0 })
      let coordinator = TextViewEditor.Coordinator(text: binding, commands: EditorCommands())

      let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
      tv.isRichText = true
      tv.typingAttributes = TextStyle.body.attributes
      tv.delegate = coordinator
      tv.textStorage?.delegate = coordinator.highlighter
      coordinator.textView = tv

      let storage = tv.textStorage!
      let md = "a `code` b"
      for ch in md {
        tv.insertText(String(ch), replacementRange: tv.selectedRange())
        // The delegate now defers highlighting to the next runloop tick, so
        // drain the main queue to let it (and the binding write) run, mirroring
        // the edit cycle closing in the real app...
        drainMainQueue()
        // ...then SwiftUI reacts to the binding write the coordinator made.
        runUpdate(coordinator, tv)
      }

      let code = (storage.string as NSString).range(of: "code").location
      XCTAssertTrue(
        code != NSNotFound && isMono(storage, at: code),
        "after the full coordinator loop, code span should be monospaced; "
          + "storage=\(storage.string.debugDescription)")
    }
  #endif
}
