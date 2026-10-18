import Foundation

/// A command together with how it matched the current query.
public struct RankedCommand: Identifiable, Sendable {
    public let command: Command
    public let score: Int
    /// Offsets into `command.title` to highlight. Empty when only the path matched or the query is empty.
    public let titlePositions: [Int]

    public var id: String { command.id }
}

/// What the ranker knows besides the query: learned usage, pins, hidden commands and aliases. `UsageStore` produces
/// one; the defaults mean "nothing known".
public protocol RankingSignal: Sendable {
    /// Added to the match score.
    func boost(for command: Command) -> Int
    /// Hidden commands are left out of results unless the caller asks for them.
    func isHidden(_ command: Command) -> Bool
    /// When the command was pinned, or nil. Pinned commands lead the empty-query list, oldest pin first.
    func pinOrder(for command: Command) -> Date?
    /// Short names the user gave the command; the query matches them like a title.
    func aliases(for command: Command) -> [String]
    /// The raw learned score, used to pick suggestions. Zero means never run.
    func frecency(for command: Command) -> Double
}

extension RankingSignal {
    public func isHidden(_ command: Command) -> Bool { false }
    public func pinOrder(for command: Command) -> Date? { nil }
    public func aliases(for command: Command) -> [String] { [] }
    public func frecency(for command: Command) -> Double { 0 }
}

/// No learning: nothing is boosted, pinned, hidden or renamed.
public struct NoRankingSignal: RankingSignal {
    public init() {}
    public func boost(for command: Command) -> Int { 0 }
}

/// Orders commands for a query.
public struct CommandRanker: Sendable {
    /// A match in the path (menu names plus title) counts for less than one in the title itself.
    static let pathPenalty = 30
    static let disabledPenalty = 200

    private let signal: any RankingSignal

    public init(signal: any RankingSignal = NoRankingSignal()) {
        self.signal = signal
    }

    /// Commands that stay out of the Suggested section because they have been run too rarely to be a habit.
    static let minimumSuggestionScore = 100.0

    /// The commands the user pinned, oldest pin first. Hidden and unavailable ones are skipped.
    public func pinned(_ commands: [Command]) -> [Command] {
        commands.compactMap { command -> (Command, Date)? in
            guard command.isEnabled, !signal.isHidden(command), let date = signal.pinOrder(for: command) else {
                return nil
            }
            return (command, date)
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    /// The "Suggested for this moment" list: unpinned, available commands of the current app ordered by frecency,
    /// best first. Commands run only once or twice long ago do not qualify, so a new install shows nothing.
    public func suggested(_ commands: [Command], limit: Int = 5) -> [RankedCommand] {
        let candidates = commands.compactMap { command -> (Command, Double)? in
            guard command.isEnabled, !signal.isHidden(command), signal.pinOrder(for: command) == nil else { return nil }
            let score = signal.frecency(for: command)
            return score >= Self.minimumSuggestionScore ? (command, score) : nil
        }
        return candidates.sorted { $0.1 > $1.1 }.prefix(limit).map {
            RankedCommand(command: $0.0, score: Int($0.1), titlePositions: [])
        }
    }

    /// A keyword match counts for less than a path match: it only rescues a command the title and path missed.
    private func keywordScore(_ query: String, _ command: Command) -> Int? {
        var best: Int?
        for keyword in command.keywords {
            guard let match = FuzzyMatcher.match(query, in: keyword) else { continue }
            let score = match.score - Self.pathPenalty - 20
            if best == nil || score > (best ?? 0) { best = score }
        }
        return best
    }

    /// An alias counts like a title; typing it exactly puts the command first.
    private func aliasScore(_ query: String, _ command: Command) -> Int? {
        var best: Int?
        for alias in signal.aliases(for: command) + command.aliases {
            guard let match = FuzzyMatcher.match(query, in: alias) else { continue }
            let exact = alias.localizedCaseInsensitiveCompare(query) == .orderedSame
            let score = match.score + (exact ? 150 : 0)
            if best == nil || score > (best ?? 0) { best = score }
        }
        return best
    }

    public func rank(_ commands: [Command], query: String, includeHidden: Bool = false) -> [RankedCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let commands = includeHidden ? commands : commands.filter { !signal.isHidden($0) }
        if trimmed.isEmpty {
            // Without a query the menu order is kept, pinned commands first and unavailable items last.
            let enabled = commands.filter(\.isEnabled)
            let disabled = commands.filter { !$0.isEnabled }
            let pinned = pinned(enabled)
            let pinnedIDs = Set(pinned.map(\.stableID))
            let rest = enabled.filter { !pinnedIDs.contains($0.stableID) }
            return (pinned + rest + disabled).map {
                RankedCommand(command: $0, score: signal.boost(for: $0), titlePositions: [])
            }
        }

        var scored: [(ranked: RankedCommand, order: Int)] = []
        for (order, command) in commands.enumerated() {
            let titleMatch = FuzzyMatcher.match(trimmed, in: command.title)
            let pathMatch = FuzzyMatcher.match(trimmed, in: command.searchPath)
            var best: Int?
            var positions: [Int] = []
            if let titleMatch {
                best = titleMatch.score
                positions = titleMatch.positions
            }
            if let pathMatch {
                let adjusted = pathMatch.score - Self.pathPenalty
                if best == nil || adjusted > (best ?? 0) {
                    best = adjusted
                    positions = []
                }
            }
            if best == nil, let keywordScore = keywordScore(trimmed, command) {
                best = keywordScore
                positions = []
            }
            if let aliasScore = aliasScore(trimmed, command) {
                if best == nil || aliasScore > (best ?? 0) {
                    best = aliasScore
                    positions = []
                }
            }
            guard var total = best else { continue }
            if titleMatch != nil, command.title.count == trimmed.count,
                command.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
            {
                total += 40
            }
            total += signal.boost(for: command)
            if !command.isEnabled { total -= Self.disabledPenalty }
            scored.append((RankedCommand(command: command, score: total, titlePositions: positions), order))
        }
        scored.sort { lhs, rhs in
            if lhs.ranked.score != rhs.ranked.score { return lhs.ranked.score > rhs.ranked.score }
            if lhs.ranked.command.title.count != rhs.ranked.command.title.count {
                return lhs.ranked.command.title.count < rhs.ranked.command.title.count
            }
            return lhs.order < rhs.order
        }
        return scored.map(\.ranked)
    }
}
