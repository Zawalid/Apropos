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
            let bundleID: String?
            switch source {
            case .menuItem(let bundle): bundleID = bundle
            }
            self.stableID = CommandID.base(bundleID: bundleID, path: path, title: title)
        }
    }

    /// The menu trail as one line, for example `File › Open Recent`.
    public var breadcrumb: String { path.joined(separator: " › ") }

    /// Everything the search looks through for the path match: the trail then the title.
    public var searchPath: String { (path + [title]).joined(separator: " ") }
}
