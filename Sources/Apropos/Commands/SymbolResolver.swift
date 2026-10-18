import Foundation

/// Which rule produced a symbol, strongest first.
public enum SymbolTier: Int, Sendable, Comparable {
    case userOverride
    case pack
    case standardCommand
    case verb
    case keyword
    case menuGroup
    case fallback

    public static func < (lhs: SymbolTier, rhs: SymbolTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Picks the SF Symbol drawn at the start of a command row. It never fails: the last tier is a fixed symbol.
///
/// Tiers, strongest first:
/// 1. the user's own choice for that command (`overrides`, kept in `UsageStore`)
/// 2. a curated pack for the app (`SymbolPackLibrary`)
/// 3. standard macOS commands, by shortcut first and then by English or French title
/// 4. a leading verb ("Export", "Exporter")
/// 5. a keyword anywhere in the title ("Toggle Sidebar")
/// 6. the top-level menu the command sits in
///
/// For a list, use `symbols(for:)`: it also makes neighbouring rows differ whenever a lower tier offers another symbol.
public struct SymbolResolver: Sendable {
    public struct Resolution: Sendable, Equatable {
        /// Every symbol that fits, best first. Never empty. The first is what `symbol(for:)` returns.
        public let candidates: [String]
        public let tier: SymbolTier
        public var symbol: String { candidates[0] }
    }

    private let overrides: [CommandID: String]
    private let library: SymbolPackLibrary

    /// - Parameters:
    ///   - overrides: Symbols the user picked, by command identity.
    ///   - library: Curated packs; defaults to the bundled ones.
    public init(overrides: [CommandID: String] = [:], library: SymbolPackLibrary = .bundled()) {
        self.overrides = overrides
        self.library = library
    }

    /// The best symbol for one command, with no regard for its neighbours.
    public func symbol(for command: Command) -> String { resolve(command).symbol }

    public func resolve(_ command: Command) -> Resolution {
        var candidates: [(String, SymbolTier)] = []
        func add(_ symbol: String?, _ tier: SymbolTier) {
            guard let symbol, !candidates.contains(where: { $0.0 == symbol }) else { return }
            candidates.append((symbol, tier))
        }

        add(overrides[command.stableID], .userOverride)
        add(command.symbolName, .pack)
        add(
            library.symbol(
                bundleID: command.stableID.bundleID, title: command.title, path: command.path,
                shortcut: command.shortcut), .pack)
        let title = CommandID.normalize(command.title)
        add(command.shortcut.flatMap { StandardCommandSymbols.shortcuts[$0.display] }, .standardCommand)
        add(StandardCommandSymbols.titles[title], .standardCommand)
        let words = title.split(separator: " ").map(String.init)
        add(words.first.flatMap { StandardCommandSymbols.verbs[$0] }, .verb)
        for word in words.dropFirst() { add(StandardCommandSymbols.keywords[word], .keyword) }
        if let first = words.first { add(StandardCommandSymbols.keywords[first], .keyword) }
        if let group = command.path.first.map(CommandID.normalize) { add(StandardCommandSymbols.groups[group], .menuGroup) }
        for spare in StandardCommandSymbols.spare { add(spare, .fallback) }

        return Resolution(candidates: candidates.map(\.0), tier: candidates[0].1)
    }

    /// Symbols for rows in display order, aligned with `commands`. A row never repeats the symbol of the row above
    /// when a weaker rule offers another one. A user override is never changed. Between two rows that clash, the one
    /// resolved by the weaker rule gives way.
    public func symbols(for commands: [Command]) -> [String] {
        let resolutions = commands.map(resolve)
        var chosen = resolutions.map(\.symbol)

        /// Moves one row to its best candidate that its neighbours do not use. Tries to avoid both neighbours, then
        /// only the one it clashes with.
        func move(_ target: Int, clashingWith other: Int) -> Bool {
            guard resolutions[target].tier != .userOverride else { return false }
            var neighbours = Set<String>()
            if target > 0 { neighbours.insert(chosen[target - 1]) }
            if target + 1 < chosen.count { neighbours.insert(chosen[target + 1]) }
            let candidates = resolutions[target].candidates
            if let better = candidates.first(where: { !neighbours.contains($0) }) ?? candidates.first(where: { $0 != chosen[other] }) {
                chosen[target] = better
                return true
            }
            return false
        }

        for index in chosen.indices.dropFirst() where chosen[index] == chosen[index - 1] {
            let previous = index - 1
            // The row resolved by the weaker rule gives way first.
            let previousFirst = resolutions[index].tier < resolutions[previous].tier
            if previousFirst {
                if !move(previous, clashingWith: index) { _ = move(index, clashingWith: previous) }
            } else if !move(index, clashingWith: previous) {
                _ = move(previous, clashingWith: index)
            }
        }
        return chosen
    }
}

extension CommandDisplay {
    /// The default symbol for a command with no user override. Rows in a list should use `SymbolResolver.symbols(for:)`
    /// instead so neighbours differ.
    public static func symbol(for command: Command) -> String { defaultResolver.symbol(for: command) }

    private static let defaultResolver = SymbolResolver()
}
