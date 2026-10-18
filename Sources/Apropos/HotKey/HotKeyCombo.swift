import Carbon.HIToolbox
import Foundation

/// A global shortcut: one key plus modifiers. Stored as the virtual key code, so it does not depend on the layout.
public struct HotKeyCombo: Codable, Sendable, Hashable {
    public var keyCode: UInt32
    public var modifiers: ModifierSet

    public init(keyCode: UInt32, modifiers: ModifierSet) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Option-Space.
    public static let `default` = HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: [.option])

    /// A shortcut with no modifier would swallow ordinary typing, so one is always required.
    public var isValid: Bool { !modifiers.isEmpty && Self.keyName(keyCode) != nil }

    public var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }

    /// The shortcut as printed in menus, for example `⌥Space`.
    public var display: String { modifiers.symbols + (Self.keyName(keyCode) ?? "?") }

    public var caps: [String] {
        var parts = modifiers.symbols.map(String.init)
        parts.append(Self.keyName(keyCode) ?? "?")
        return parts
    }

    static func keyName(_ code: UInt32) -> String? {
        keyNames[Int(code)]
    }

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
        kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// Persists the chosen shortcut.
public struct HotKeyStore: Sendable {
    private let key = "hotKey"
    private let defaults: UserDefaultsBox

    /// UserDefaults is documented as thread-safe; the box only carries it across concurrency domains.
    struct UserDefaultsBox: @unchecked Sendable { let defaults: UserDefaults }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = UserDefaultsBox(defaults: defaults)
    }

    public func load() -> HotKeyCombo {
        guard let data = defaults.defaults.data(forKey: key),
            let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data), combo.isValid
        else { return .default }
        return combo
    }

    public func save(_ combo: HotKeyCombo) {
        guard combo.isValid, let data = try? JSONEncoder().encode(combo) else { return }
        defaults.defaults.set(data, forKey: key)
    }
}
