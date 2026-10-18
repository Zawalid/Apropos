import Foundation

/// A command together with how it matched the current query.
public struct RankedCommand: Identifiable, Sendable {
    public let command: Command
    public let score: Int
    /// Offsets into `command.title` to highlight. Empty when only the path matched or the query is empty.
    public let titlePositions: [Int]

    public var id: String { command.id }
}

/// An extra signal added to a command's score. M1 replaces the stub with per-app usage learned locally.
public protocol RankingSignal: Sendable {
    func boost(for command: Command) -> Int
}

/// The M0 signal: no learning yet, so nothing is boosted.
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

    public func rank(_ commands: [Command], query: String) -> [RankedCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            // Without a query the menu order is kept, with unavailable items last.
            let enabled = commands.filter(\.isEnabled)
            let disabled = commands.filter { !$0.isEnabled }
            return (enabled + disabled).map {
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
