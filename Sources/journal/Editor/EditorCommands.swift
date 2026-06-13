import SwiftUI

/// A formatting action aimed at the current selection. Senders (menus,
/// toolbar buttons) describe intent; the active backend decides how to
/// apply it to its text view.
enum EditorCommand {
    case toggleBold
    case toggleItalic
    case toggleUnderline
    case setBlockStyle(TextStyle)
}

/// Bridge from SwiftUI controls into the active editor backend. The view
/// that owns the editor creates one and passes it down; the backend installs
/// a handler when its platform view is made. Senders never learn which
/// backend is behind it, so the `JournalEditor` seam stays intact.
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
