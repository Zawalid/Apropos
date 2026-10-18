import Foundation

/// A plain-data copy of one menu item as read from an app, with its submenu. The accessibility reader produces
/// these; the mapper turns them into commands. Fixtures in tests build them directly.
public struct MenuItemSnapshot: Sendable {
    public var title: String
    public var isEnabled: Bool
    public var cmdChar: String
    /// The raw `AXMenuItemCmdModifiers` value: bit 0 shift, bit 1 option, bit 2 control, bit 3 means no command key.
    public var cmdModifiers: Int
    public var cmdGlyph: Int
    public var cmdVirtualKey: Int
    /// The mark character the app draws next to the item: a check mark or a dash.
    public var markChar: String
    public var children: [MenuItemSnapshot]
    public var target: (any CommandTarget)?

    public init(
        title: String, isEnabled: Bool = true, cmdChar: String = "", cmdModifiers: Int = 0, cmdGlyph: Int = 0,
        cmdVirtualKey: Int = 0, markChar: String = "", children: [MenuItemSnapshot] = [],
        target: (any CommandTarget)? = nil
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.cmdChar = cmdChar
        self.cmdModifiers = cmdModifiers
        self.cmdGlyph = cmdGlyph
        self.cmdVirtualKey = cmdVirtualKey
        self.markChar = markChar
        self.children = children
        self.target = target
    }
}

/// Turns a menu bar snapshot into a flat list of commands.
public enum MenuCommandMapper {
    /// Submenus that are not worth listing: the system fills them in and they are slow to read.
    static let skippedMenus: Set<String> = ["Services", "Dienste", "Services "]

    /// Flattens the menu bar. Separators, the Apple menu and submenu headers are dropped; every remaining item
    /// becomes a command whose path is the chain of menus above it. Ids are the index path, so they are unique and
    /// stable for one snapshot.
    public static func commands(from menuBar: [MenuItemSnapshot], bundleID: String?) -> [Command] {
        var result: [Command] = []
        for (index, top) in menuBar.enumerated() {
            if isAppleMenu(top, at: index) { continue }
            let title = top.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            collect(top.children, path: [title], indexPath: [index], bundleID: bundleID, into: &result)
        }
        return result
    }

    private static func isAppleMenu(_ item: MenuItemSnapshot, at index: Int) -> Bool {
        index == 0 && item.title == "Apple"
    }

    private static func collect(
        _ items: [MenuItemSnapshot], path: [String], indexPath: [Int], bundleID: String?, into result: inout [Command]
    ) {
        for (index, item) in items.enumerated() {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let here = indexPath + [index]
            if !item.children.isEmpty {
                guard !skippedMenus.contains(title) else { continue }
                collect(item.children, path: path + [title], indexPath: here, bundleID: bundleID, into: &result)
                continue
            }
            result.append(
                Command(
                    id: here.map(String.init).joined(separator: "."),
                    title: title,
                    path: path,
                    shortcut: shortcut(for: item),
                    isEnabled: item.isEnabled,
                    isChecked: item.markChar == "✓",
                    source: .menuItem(bundleID: bundleID),
                    target: item.target))
        }
    }

    /// Builds the shortcut from the key character or, when the item uses a special key, its glyph or virtual key.
    public static func shortcut(for item: MenuItemSnapshot) -> KeyShortcut? {
        let key: String
        if !item.cmdChar.isEmpty, item.cmdChar.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) {
            key = item.cmdChar.uppercased()
        } else if let glyph = glyphSymbol(item.cmdGlyph) {
            key = glyph
        } else if let virtual = virtualKeySymbol(item.cmdVirtualKey) {
            key = virtual
        } else {
            return nil
        }
        var modifiers = ModifierSet()
        if item.cmdModifiers & 1 != 0 { modifiers.insert(.shift) }
        if item.cmdModifiers & 2 != 0 { modifiers.insert(.option) }
        if item.cmdModifiers & 4 != 0 { modifiers.insert(.control) }
        if item.cmdModifiers & 8 == 0 { modifiers.insert(.command) }
        return KeyShortcut(key: key, modifiers: modifiers)
    }

    static func glyphSymbol(_ glyph: Int) -> String? {
        switch glyph {
        case 0x02: "⇥"
        case 0x03: "⇤"
        case 0x04: "⌅"
        case 0x09: "Space"
        case 0x0A: "⌦"
        case 0x0B: "↩"
        case 0x17: "⌫"
        case 0x1B: "⎋"
        case 0x1C: "⌧"
        case 0x62: "⇞"
        case 0x64: "←"
        case 0x65: "→"
        case 0x66: "↖"
        case 0x67: "?"
        case 0x68: "↑"
        case 0x69: "↘"
        case 0x6A: "↓"
        case 0x6B: "⇟"
        case 0x6F...0x7A: "F\(glyph - 0x6F + 1)"
        case 0x87...0x89: "F\(glyph - 0x87 + 13)"
        default: nil
        }
    }

    static func virtualKeySymbol(_ code: Int) -> String? {
        switch code {
        case 36, 76: "↩"
        case 48: "⇥"
        case 49: "Space"
        case 51: "⌫"
        case 53: "⎋"
        case 117: "⌦"
        case 115: "↖"
        case 119: "↘"
        case 116: "⇞"
        case 121: "⇟"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        case 122: "F1"
        case 120: "F2"
        case 99: "F3"
        case 118: "F4"
        case 96: "F5"
        case 97: "F6"
        case 98: "F7"
        case 100: "F8"
        case 101: "F9"
        case 109: "F10"
        case 103: "F11"
        case 111: "F12"
        default: nil
        }
    }
}
