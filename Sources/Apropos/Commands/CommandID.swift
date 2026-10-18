import Foundation

/// An identity for a command that survives relaunches and app updates. `Command.id` is an index path that is only
/// unique inside one menu snapshot; anything saved to disk (usage, pins, aliases, hotkeys) is keyed by this instead.
///
/// The value is readable on purpose, so a hand-edited file is understandable:
/// `com.apple.finder|file>new folder|⇧⌘N`. It is built from the bundle identifier, the normalized menu trail and
/// title, and, only where two commands would otherwise collide, the shortcut and then an ordinal. A shortcut is not
/// part of every identity because users remap them, and that must not erase what Apropos learned.
public struct CommandID: RawRepresentable, Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public var description: String { rawValue }

    public static func < (lhs: CommandID, rhs: CommandID) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// The bundle identifier part, or nil for a command that has none.
    public var bundleID: String? {
        // Context actions have no bundle: their identity is just `ctx:text.upper`.
        guard rawValue.contains("|") else { return nil }
        guard let head = rawValue.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return nil
        }
        return head == Self.unknownBundle ? nil : String(head)
    }

    static let unknownBundle = "unknown"

    /// The base identity of a command: bundle, normalized path and title. No shortcut, no ordinal.
    public static func base(bundleID: String?, path: [String], title: String) -> CommandID {
        let trail = (path + [title]).map(normalize).joined(separator: ">")
        return CommandID(rawValue: "\(bundleID ?? unknownBundle)|\(trail)")
    }

    /// The identity of a command with its position fallback, used when a menu title has nothing usable in it.
    static func base(bundleID: String?, path: [String], title: String, shortcut: KeyShortcut?, position: Int)
        -> CommandID
    {
        guard !normalize(title).isEmpty else {
            let anchor = shortcut.map { "key \($0.display)" } ?? "item \(position)"
            let trail = (path.map(normalize) + [anchor]).joined(separator: ">")
            return CommandID(rawValue: "\(bundleID ?? unknownBundle)|\(trail)")
        }
        return base(bundleID: bundleID, path: path, title: title)
    }

    func adding(shortcut: KeyShortcut) -> CommandID { CommandID(rawValue: rawValue + "|" + shortcut.display) }

    func adding(ordinal: Int) -> CommandID { CommandID(rawValue: rawValue + "#\(ordinal)") }

    /// One menu name or title in canonical form. Two spellings of the same menu item must give the same text:
    /// trailing ellipses and update counts are dropped (`Save As…` and `Save As...`), case and diacritics are
    /// ignored, whitespace is collapsed, and the characters used as separators are neutralized. Localized titles are
    /// kept as they are: a French menu gets French identities, which are stable for as long as the app speaks French.
    static func normalize(_ text: String) -> String {
        let cleaned = CommandDisplay.cleanTitle(text).precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\u{2019}", with: "'")
        let folded = cleaned.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let neutral = folded.map { "|>#".contains($0) ? " " : $0 }
        let words = String(neutral).split(whereSeparator: { $0.isWhitespace || $0 == "\u{00A0}" })
        let joined = words.joined(separator: " ")
        // A title made only of ellipsis characters cleans to itself; treat it as empty.
        if joined.allSatisfy({ $0 == "…" || $0 == "." }) { return "" }
        return joined
    }
}

/// Makes the identities of one app's commands unique, leaving as many as possible untouched.
enum CommandIdentity {
    /// Colliding bases get the shortcut when it tells them apart, then an ordinal (the first keeps the plain form).
    static func disambiguate(_ entries: [(base: CommandID, shortcut: KeyShortcut?)]) -> [CommandID] {
        var result = entries.map(\.base)
        let groups = Dictionary(grouping: entries.indices, by: { entries[$0].base })
        for (_, members) in groups where members.count > 1 {
            for index in members {
                if let shortcut = entries[index].shortcut { result[index] = entries[index].base.adding(shortcut: shortcut) }
            }
            // Members that are still equal (no shortcut, or the same one) get ordinals in menu order.
            let again = Dictionary(grouping: members, by: { result[$0] })
            for (_, same) in again where same.count > 1 {
                for (offset, index) in same.sorted().enumerated() where offset > 0 {
                    result[index] = result[index].adding(ordinal: offset + 1)
                }
            }
        }
        return result
    }
}
