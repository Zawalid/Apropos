import AppKit
import Apropos

/// The one question Apropos asks before running something on behalf of a shortcut key, a link or Shortcuts: a plain
/// alert that says what will run. Used for commands that ask for confirmation and for the first outside run of a command.
@MainActor
enum CommandConfirmation {
    /// Returns true when the person chose to run it.
    static func ask(_ command: UserCommand, reason: String, effects: [String] = []) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Run \u{201C}\(command.title)\u{201D}?"
        // A sequence lists what it will do outside Apropos; everything else lists what it runs.
        let lines = effects.isEmpty ? CommandSummary.lines(for: command) : effects
        alert.informativeText = reason + "\n\n" + lines.joined(separator: "\n")
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
