import Foundation

/// Rows that belong to Apropos itself and open its own windows. The panel lists them only while something is typed that
/// matches them by name or keyword, never in the empty list, so they never push a menu item down.
public enum AppCommand: String, Sendable, Hashable, CaseIterable {
    /// Opens Settings on the Commands page with the New command sheet open.
    case newCommand
    /// Opens Settings on the Commands page.
    case yourCommands

    public var commandID: CommandID { CommandID(rawValue: "app:\(rawValue)") }

    public var title: String {
        switch self {
        case .newCommand: "New command"
        case .yourCommands: "Your commands"
        }
    }

    var symbol: String {
        switch self {
        case .newCommand: "plus.square"
        case .yourCommands: "list.bullet.rectangle"
        }
    }

    var keywords: [String] {
        switch self {
        case .newCommand: ["apropos", "create", "make", "add", "custom", "own", "shortcut", "command"]
        case .yourCommands: ["apropos", "list", "manage", "edit", "custom", "own", "commands", "settings"]
        }
    }

    var detail: String {
        switch self {
        case .newCommand: "In Apropos: make a command of your own"
        case .yourCommands: "In Apropos: see and edit the commands you made"
        }
    }

    /// The row the panel lists for it, under the group "Apropos".
    public var command: Command {
        var row = Command(id: commandID.rawValue, title: title, path: ["Apropos"], source: .app(self))
        row.symbolName = symbol
        row.keywords = keywords
        row.detail = detail
        return row
    }
}

/// What the Command-K list offers on one of your own commands.
public enum UserCommandAction: Sendable, Equatable {
    /// Opens Settings on the Commands page with this command's detail sheet open.
    case edit(ActionID)
    case duplicate(ActionID)
    case delete(ActionID)
}

/// What the app says back after a command action: it did it (with a line for the panel to show), or why it could not.
public enum UserCommandOutcome: Sendable, Equatable {
    case done(note: String?)
    case failed(String)
}

/// A delete waiting for its confirming Return.
public struct PendingDeletion: Sendable, Equatable {
    public let id: ActionID
    public let title: String

    public var heading: String { "Delete \u{201C}\(title)\u{201D}?" }
    public let detail = "The file is kept in its history, so it can be brought back from the commands folder."
}
