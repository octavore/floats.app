import SwiftUI

enum EditorCommand {
  case toggleBold
  case toggleItalic
  case setBlockStyle(TextStyle)
  case increaseFontSize
  case decreaseFontSize
}

/// Bridge from SwiftUI controls into the active editor backend. The view
/// that owns the editor creates one and passes it down; the backend installs
/// a handler when its platform view is made.
@MainActor
final class EditorCommands {
  var handler: ((EditorCommand) -> Void)?

  func send(_ command: EditorCommand) {
    handler?(command)
  }
}

extension FocusedValues {
  /// Lets app-level menu commands reach the editor in the focused window.
  @Entry var editorCommands: EditorCommands?
}
