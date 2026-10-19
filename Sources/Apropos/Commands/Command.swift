import Foundation

/// Modifier keys of a keyboard shortcut, in the order macOS prints them: control, option, shift, command.
public struct ModifierSet: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = ModifierSet(rawValue: 1 << 0)
    public static let option = ModifierSet(rawValue: 1 << 1)
    public static let shift = ModifierSet(rawValue: 1 << 2)
    public static let command = ModifierSet(rawValue: 1 << 3)

    /// The symbols in display order, for example `⌃⌥⇧⌘`.
    public var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }
}

/// A keyboard shortcut as a menu item advertises it.
public struct KeyShortcut: Sendable, Hashable {
    public let key: String
    public let modifiers: ModifierSet

    public init(key: String, modifiers: ModifierSet) {
        self.key = key
        self.modifiers = modifiers
    }

    /// The shortcut as printed in a menu, for example `⇧⌘N`.
    public var display: String { modifiers.symbols + key }

    /// Each key as its own cap, modifiers first, for drawing keycaps.
    public var caps: [String] {
        var parts: [String] = []
        for symbol in modifiers.symbols { parts.append(String(symbol)) }
        parts.append(key)
        return parts
    }
}

/// Something that can run a command. The accessibility backend implements it with AXPress; tests use fakes.
public protocol CommandTarget: Sendable {
    func perform() throws
}

public enum CommandSource: Sendable, Hashable {
    case menuItem(bundleID: String?)
    /// A context action: it works on what Apropos senses (selection, files, page, folder), in any app.
    case contextAction(ActionID)
    /// A row of the send-to layer: "Send selection to...", or a destination for one kind of payload.
    case sendTo(SendTarget)
    /// A row of the sequence draft: its top row, its actions and its steps.
    case sequence(SequenceTarget)
    /// A row of Apropos itself ("New command", "Your commands"), listed only while searching.
    case app(AppCommand)
}

/// An Option-key variant of a menu item, such as Empty Trash Securely next to Empty Trash. It is a second way to run
/// the same row, not a row of its own.
public struct CommandAlternate: Sendable {
    public let stableID: CommandID
    public let title: String
    public let shortcut: KeyShortcut?
    public let isEnabled: Bool
    public let target: (any CommandTarget)?

    public init(
        stableID: CommandID, title: String, shortcut: KeyShortcut?, isEnabled: Bool, target: (any CommandTarget)?
    ) {
        self.stableID = stableID
        self.title = title
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.target = target
    }
}

/// One runnable thing in the palette.
public struct Command: Identifiable, Sendable {
    public let id: String
    public let title: String
    /// The menus that lead to this item, outermost first: `["File", "Open Recent"]`.
    public let path: [String]
    public let shortcut: KeyShortcut?
    public let isEnabled: Bool
    public let isChecked: Bool
    public let source: CommandSource
    public let target: (any CommandTarget)?
    /// The identity to save anything under. Unlike `id` it survives relaunches and app updates.
    public internal(set) var stableID: CommandID
    /// Option-key variants folded into this command. Empty when the app has none or when alternates are shown as
    /// rows of their own.
    public internal(set) var alternates: [CommandAlternate] = []
    /// Set on a row that is itself an alternate (only when alternates are shown): the command it varies.
    public internal(set) var alternateOf: CommandID?
    /// An SF Symbol the command brings along (context actions do). Used before any rule of the symbol resolver.
    public internal(set) var symbolName: String?
    /// Extra words the search matches, below the title.
    public internal(set) var keywords: [String] = []
    /// Names the person gave the command; typing one ranks the command first.
    public internal(set) var aliases: [String] = []
    /// A line of explanation to show under the title, when the command has one.
    public internal(set) var detail: String?
    /// True when the person should confirm before it runs.
    public internal(set) var needsConfirmation = false

    public init(
        id: String, title: String, path: [String], shortcut: KeyShortcut? = nil, isEnabled: Bool = true,
        isChecked: Bool = false, source: CommandSource, target: (any CommandTarget)? = nil,
        stableID: CommandID? = nil
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.source = source
        self.target = target
        if let stableID {
            self.stableID = stableID
        } else {
            switch source {
            case .menuItem(let bundle):
                self.stableID = CommandID.base(bundleID: bundle, path: path, title: title)
            case .contextAction(let action):
                self.stableID = CommandID(rawValue: action.rawValue)
            case .sendTo(let target):
                self.stableID = target.commandID
            case .sequence(let target):
                self.stableID = target.commandID
            case .app(let command):
                self.stableID = command.commandID
            }
        }
    }

    /// The menu trail as one line, for example `File › Open Recent`.
    public var breadcrumb: String { path.joined(separator: " › ") }

    /// Everything the search looks through for the path match: the trail then the title.
    public var searchPath: String { (path + [title]).joined(separator: " ") }
}
