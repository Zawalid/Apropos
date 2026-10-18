import AppKit
import Apropos

/// The one question Apropos asks before running something on behalf of a shortcut key, a link or Shortcuts: a plain
/// alert that says what will run. Used for commands that ask for confirmation and for the first outside run of a command.
@MainActor
enum CommandConfirmation {
    /// Returns true when the person chose to run it.
    static func ask(_ command: UserCommand, reason: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Run \u{201C}\(command.title)\u{201D}?"
        alert.informativeText = reason + "\n\n" + CommandSummary.lines(for: command).joined(separator: "\n")
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
