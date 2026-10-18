import Foundation

/// What kind of key a key code is. Decided from the key code alone, never from a character.
enum KeyClass: Equatable {
    /// Produces text (letters, digits, punctuation, space).
    case text
    /// Return, Tab, Escape, deletes, arrows, Home, End, Page Up and Down.
    case navigation
    case function
}

/// The symbols menus use for keys that are not characters, shared with `MenuCommandMapper` so a typed key and a menu
/// item's advertised key compare equal.
enum KeySymbols {
    static func special(_ keyCode: UInt16) -> String? {
        switch keyCode {
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
        default: functionKey(keyCode)
        }
    }

    private static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
        90: "F20",
    ]

    static func functionKey(_ keyCode: UInt16) -> String? { functionKeys[keyCode] }

    static func keyClass(_ keyCode: UInt16) -> KeyClass {
        if functionKeys[keyCode] != nil { return .function }
        switch keyCode {
        case 36, 76, 48, 51, 53, 117, 115, 119, 116, 121, 123, 124, 125, 126: return .navigation
        default: return .text
        }
    }
}

/// The base character a key produces with no modifiers on the current keyboard layout. Asked only to compare a chord
/// with a menu shortcut; the answer is never kept.
public protocol KeyLayout: Sendable {
    func baseCharacter(forKeyCode keyCode: UInt16) -> String?
}

/// The US layout. The fallback when the current layout cannot be read, and the layout tests use.
public struct USKeyLayout: KeyLayout {
    public init() {}

    private static let table: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q", 13: "w",
        14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l", 38: "j",
        39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 50: "`",
    ]

    public func baseCharacter(forKeyCode keyCode: UInt16) -> String? { Self.table[keyCode] }
}

extension KeyChord {
    var keyClass: KeyClass { KeySymbols.keyClass(keyCode) }

    /// A chord that could be a menu shortcut: it has the command or control key, or it is a function key. Everything
    /// else is typing or navigation and is dropped without being looked at.
    var isShortcutCandidate: Bool {
        modifiers.contains(.command) || modifiers.contains(.control) || keyClass == .function
    }

    /// The shortcut a menu would advertise for this chord, built in memory to compare and then forgotten.
    func shortcut(using layout: any KeyLayout) -> KeyShortcut? {
        if let symbol = KeySymbols.special(keyCode) { return KeyShortcut(key: symbol, modifiers: modifiers) }
        guard let character = layout.baseCharacter(forKeyCode: keyCode), !character.isEmpty else { return nil }
        return KeyShortcut(key: character.uppercased(), modifiers: modifiers)
    }
}
