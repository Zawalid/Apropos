import Carbon.HIToolbox
import Foundation

/// Shortcuts macOS itself uses by default, so a clash can be warned about before a key is registered. It is a short list
/// of the ones people actually hit; the person may have changed theirs in System Settings, so it is a warning and never a ban.
public enum SystemShortcuts {
    public struct Entry: Sendable, Equatable {
        public let combo: HotKeyCombo
        public let name: String
    }

    public static let all: [Entry] = [
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: [.command]), name: "Spotlight"),
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: [.command, .option]), name: "Finder search"),
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: [.control]), name: "Input sources"),
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: [.control, .option]), name: "Previous input source"),
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_Tab), modifiers: [.command]), name: "App switcher"),
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_ANSI_Grave), modifiers: [.command]), name: "Window switcher"),
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_Escape), modifiers: [.command, .option]), name: "Force Quit"),
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_ANSI_Q), modifiers: [.command, .control]), name: "Lock Screen"),
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: [.command, .shift]), name: "Screenshot"),
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: [.command, .shift]), name: "Screenshot selection"),
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_ANSI_5), modifiers: [.command, .shift]), name: "Screenshot options"),
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_ANSI_H), modifiers: [.command]), name: "Hide app"),
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_ANSI_Q), modifiers: [.command]), name: "Quit app"),
        Entry(combo: HotKeyCombo(keyCode: UInt32(kVK_ANSI_M), modifiers: [.command]), name: "Minimize window"),
    ]

    /// The macOS feature this combination is normally used by, if any.
    public static func name(for combo: HotKeyCombo) -> String? {
        all.first { $0.combo == combo }?.name
    }
}
