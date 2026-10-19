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
    /// Effective recent uses with age counted, or nil when the signal only has the older frecency.
    func habit(for command: Command) -> Double?
    /// What the person's past choices say about this query for this command.
    func learned(for command: Command, query: String) -> LearnedSignal
}

extension RankingSignal {
    public func isHidden(_ command: Command) -> Bool { false }
    public func pinOrder(for command: Command) -> Date? { nil }
    public func aliases(for command: Command) -> [String] { [] }
    public func frecency(for command: Command) -> Double { 0 }
    public func habit(for command: Command) -> Double? { nil }
    public func learned(for command: Command, query: String) -> LearnedSignal { .none }
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
    public let tuning: RankingTuning

    public init(signal: any RankingSignal = NoRankingSignal(), tuning: RankingTuning = RankingTuning()) {
        self.signal = signal
        self.tuning = tuning
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
            if tuning.halfLifeDays != nil, let habit = signal.habit(for: command) {
                return habit >= tuning.suggestionMinimumHabit ? (command, habit * 100) : nil
            }
            let score = signal.frecency(for: command)
            return score >= Self.minimumSuggestionScore ? (command, score) : nil
        }
        return candidates.sorted { $0.1 > $1.1 }.prefix(limit).map {
            RankedCommand(command: $0.0, score: Int($0.1), titlePositions: [])
        }
    }

    /// The menus keep their order, and inside each menu the commands that are used come first, the strongest habit first.
    private func orderedByUse(_ commands: [Command]) -> [Command] {
        var groups: [String] = []
        var members: [String: [(order: Int, command: Command)]] = [:]
        for (order, command) in commands.enumerated() {
            let group = command.path.first ?? ""
            if members[group] == nil { groups.append(group) }
            members[group, default: []].append((order, command))
        }
        return groups.flatMap { group in
            (members[group] ?? []).sorted { lhs, rhs in
                let left = signal.habit(for: lhs.command) ?? 0
                let right = signal.habit(for: rhs.command) ?? 0
                if left != right { return left > right }
                return lhs.order < rhs.order
            }.map(\.command)
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

    /// What a match is worth, by how it matched. A near miss never gets the weight of a clean match.
    private struct Candidate {
        var score: Int
        var positions: [Int]
        var kind: FuzzyMatch.Kind
        /// How far use and learned names may be trusted on top of this match, 0 to 1.
        var confidence: Double
    }

    private func confidence(_ kind: FuzzyMatch.Kind) -> Double {
        switch kind {
        case .exact, .prefix: 1
        case .wordPrefix, .initials: 0.9
        case .scattered: 0.55
        }
    }

    /// The bonus for how the query sits in the title, less a little for each character the title has beyond the query.
    private func tierBonus(_ match: FuzzyMatch, command: Command, query: String) -> Int {
        var bonus = 0
        switch match.kind {
        case .exact: bonus = tuning.exactBonus
        case .prefix: bonus = tuning.prefixBonus
        case .wordPrefix: bonus = tuning.wordPrefixBonus
        case .initials: bonus = tuning.initialsBonus
        case .scattered: break
        }
        if tuning.lengthPenalty > 0, match.kind >= .wordPrefix {
            let extra = max(command.title.count - query.filter { !$0.isWhitespace }.count, 0)
            bonus -= Int(min(Double(extra) * tuning.lengthPenalty, tuning.lengthPenaltyCap))
        }
        return bonus
    }

    /// One slip: two neighbouring letters swapped. The match counts for less than a clean one.
    private func typoMatch(_ query: String, _ command: Command) -> Candidate? {
        let letters = Array(query.filter { !$0.isWhitespace })
        guard letters.count >= 3 else { return nil }
        var best: FuzzyMatch?
        for index in 0..<(letters.count - 1) where letters[index] != letters[index + 1] {
            var swapped = letters
            swapped.swapAt(index, index + 1)
            if let match = FuzzyMatcher.match(String(swapped), in: command.title),
                match.kind >= .wordPrefix, best == nil || match.score > (best?.score ?? 0)
            {
                best = match
            }
        }
        guard let best else { return nil }
        return Candidate(
            score: best.score - tuning.typoPenalty, positions: best.positions, kind: .scattered, confidence: 0.6)
    }

    /// The final score of a matched command: the match, what use adds, what the person's own names add.
    private func rankedCommand(
        _ command: Command, _ found: Candidate, query: String, priors: [CommandID: Double]
    ) -> RankedCommand {
        var total = found.score
        if tuning.halfLifeDays != nil, let habit = signal.habit(for: command) {
            let weight = habit / (habit + tuning.usageHalfPoint)
            total += Int(tuning.usageCap * weight * (tuning.gateUsage ? found.confidence : 1))
        } else {
            total += signal.boost(for: command)
        }
        if tuning.learnedMax > 0 {
            let learned = signal.learned(for: command, query: query)
            if learned.support >= tuning.learnedMinSupport, learned.share >= tuning.learnedMinShare {
                total += Int(tuning.learnedMax * learned.share * learned.support / (learned.support + 1.2))
            }
        }
        if tuning.priorMax > 0, let probability = priors[command.stableID] {
            total += Int(tuning.priorMax * min(probability, 1) * found.confidence)
        }
        if tuning.contextBonus > 0 {
            switch command.source {
            case .contextAction, .sendTo: total += tuning.contextBonus
            default: break
            }
        }
        if !command.isEnabled { total -= Self.disabledPenalty }
        return RankedCommand(command: command, score: total, titlePositions: found.positions)
    }

    /// - Parameter priors: how likely each command is to be the next one, from what was just run, the time and the
    ///   context. Empty when nothing is known.
    public func rank(
        _ commands: [Command], query: String, includeHidden: Bool = false, priors: [CommandID: Double] = [:]
    ) -> [RankedCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let commands = includeHidden ? commands : commands.filter { !signal.isHidden($0) }
        if trimmed.isEmpty {
            // Without a query the menu order is kept, pinned commands first and unavailable items last.
            let enabled = commands.filter(\.isEnabled)
            let disabled = commands.filter { !$0.isEnabled }
            let pinned = pinned(enabled)
            let pinnedIDs = Set(pinned.map(\.stableID))
            var rest = enabled.filter { !pinnedIDs.contains($0.stableID) }
            if tuning.orderMenusByUse { rest = orderedByUse(rest) }
            return (pinned + rest + disabled).map {
                RankedCommand(command: $0, score: signal.boost(for: $0), titlePositions: [])
            }
        }

        func candidate(for command: Command, query: String, tolerant: Bool) -> Candidate? {
            let titleMatch = FuzzyMatcher.match(query, in: command.title)
            let pathMatch = FuzzyMatcher.match(query, in: command.searchPath)
            var best: Candidate?
            if let titleMatch {
                best = Candidate(
                    score: titleMatch.score + tierBonus(titleMatch, command: command, query: query),
                    positions: titleMatch.positions, kind: titleMatch.kind, confidence: confidence(titleMatch.kind))
            }
            if let pathMatch {
                let adjusted = pathMatch.score - Self.pathPenalty
                if best == nil || adjusted > (best?.score ?? 0) {
                    best = Candidate(score: adjusted, positions: [], kind: .scattered, confidence: 0.5)
                }
            }
            if best == nil, let keywordScore = keywordScore(query, command) {
                best = Candidate(score: keywordScore, positions: [], kind: .scattered, confidence: 0.5)
            }
            if let aliasScore = aliasScore(query, command), best == nil || aliasScore > (best?.score ?? 0) {
                best = Candidate(score: aliasScore, positions: [], kind: .exact, confidence: 1)
            }
            if best == nil, tolerant, tuning.typoTolerance, let typo = typoMatch(query, command) {
                best = typo
            }
            return best
        }

        var scored: [(ranked: RankedCommand, order: Int)] = []
        var unmatched: [(order: Int, command: Command)] = []
        var clean = 0
        for (order, command) in commands.enumerated() {
            guard let found = candidate(for: command, query: trimmed, tolerant: false) else {
                unmatched.append((order, command))
                continue
            }
            if found.kind >= .wordPrefix { clean += 1 }
            scored.append((rankedCommand(command, found, query: trimmed, priors: priors), order))
        }
        // A slip of two neighbouring letters is looked for only when nothing matched cleanly (a name's start, a word's
        // start, or first letters), so it never crowds out real matches.
        if tuning.typoTolerance, clean == 0, trimmed.count >= 3 {
            for (order, command) in unmatched {
                if let found = candidate(for: command, query: trimmed, tolerant: true) {
                    scored.append((rankedCommand(command, found, query: trimmed, priors: priors), order))
                }
            }
        }
        // A command the person reaches with a name of their own is found even when the name is not in its title.
        if tuning.learnedMax > 0 {
            let present = Set(scored.map(\.ranked.command.stableID))
            for (order, command) in unmatched where !present.contains(command.stableID) {
                let learned = signal.learned(for: command, query: trimmed)
                guard learned.share >= max(0.5, tuning.learnedMinShare), learned.support >= tuning.learnedMinSupport else { continue }
                let found = Candidate(score: 40, positions: [], kind: .scattered, confidence: 1)
                scored.append((rankedCommand(command, found, query: trimmed, priors: priors), order))
            }
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
