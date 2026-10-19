import Foundation

/// How sure the model must be before a row is shown.
public enum PredictionSensitivity: String, CaseIterable, Sendable {
    case cautious, balanced, eager

    public var threshold: Double {
        switch self {
        case .cautious: 0.8
        case .balanced: PredictionPolicy.showThreshold
        case .eager: 0.5
        }
    }
}

/// What the log holds, as counts only.
public struct PredictionSummary: Equatable, Sendable {
    public var runs = 0
    public var since: Date?
    public var apps = 0
    public var commands = 0
    /// Distinct calendar days with at least one run.
    public var daysOfUse = 0

    /// Under two weeks or fifty runs, predictions are rare. This says how far along it is, from 0 to 1.
    public var warmUp: Double { min(1, min(Double(daysOfUse) / 14, Double(runs) / 50)) }
    public var isWarmingUp: Bool { warmUp < 1 }
}

/// How often a shown suggestion was the command the person then ran.
public struct PredictionAccuracy: Equatable, Sendable {
    public var shown = 0
    public var chosen = 0
    public var rate: Double { shown == 0 ? 0 : Double(chosen) / Double(shown) }
    public var isEnough: Bool { shown >= 5 }
}

/// One habit the log shows: in an app, after one command, this one follows.
public struct HabitPattern: Identifiable, Equatable, Sendable {
    public let app: String
    public let previous: CommandID
    public let command: CommandID
    /// Times this command followed that one.
    public let count: Int
    /// Times anything followed that command in this app.
    public let total: Int

    public var id: String { "\(app)|\(previous.rawValue)|\(command.rawValue)" }
}

extension PredictionEngine {
    public func summary(calendar: Calendar = .current) -> PredictionSummary {
        let runs = log.events.filter { $0.kind == .run }
        var summary = PredictionSummary()
        summary.runs = runs.count
        summary.since = runs.map(\.date).min()
        summary.apps = Set(runs.map(\.app)).count
        summary.commands = Set(runs.map(\.command)).count
        summary.daysOfUse = Set(runs.map { calendar.startOfDay(for: $0.date) }).count
        return summary
    }

    /// Of the suggestions shown in the last `days` days, how many were the command that ran next.
    public func accuracy(lastDays days: Int = 30, now: Date = Date()) -> PredictionAccuracy {
        let cutoff = now.timeIntervalSince1970 - Double(days) * 86_400
        var result = PredictionAccuracy()
        for event in log.events where event.time >= cutoff && event.kind == .run {
            guard let offered = event.offered else { continue }
            result.shown += 1
            if offered == event.command { result.chosen += 1 }
        }
        return result
    }

    /// The strongest habits, best first: seen at least `minimum` times and followed most of the time.
    public func habits(limit: Int = 8, minimum: Int = 3) -> [HabitPattern] {
        struct Pair: Hashable {
            let app: String
            let previous: CommandID
            let command: CommandID
        }
        struct After: Hashable {
            let app: String
            let previous: CommandID
        }
        var pairs: [Pair: Int] = [:]
        var totals: [After: Int] = [:]
        for event in log.events where event.kind == .run {
            guard let previous = event.previous, event.app != PredictionPrivacy.unknownApp else { continue }
            pairs[Pair(app: event.app, previous: previous, command: event.command), default: 0] += 1
            totals[After(app: event.app, previous: previous), default: 0] += 1
        }
        return pairs.compactMap { pair, count -> HabitPattern? in
            guard count >= minimum, pair.previous != pair.command else { return nil }
            let total = totals[After(app: pair.app, previous: pair.previous)] ?? count
            return HabitPattern(app: pair.app, previous: pair.previous, command: pair.command, count: count, total: total)
        }
        .sorted { ($0.count, Double($0.count) / Double($0.total)) > ($1.count, Double($1.count) / Double($1.total)) }
        .prefix(limit).map { $0 }
    }

    /// Apps with runs in the log, most runs first.
    public func appsInLog() -> [(app: String, runs: Int)] {
        var counts: [String: Int] = [:]
        for event in log.events where event.kind == .run && event.app != PredictionPrivacy.unknownApp {
            counts[event.app, default: 0] += 1
        }
        return counts.map { (app: $0.key, runs: $0.value) }.sorted { $0.runs > $1.runs }
    }

    public func forget(_ habit: HabitPattern) {
        log.forgetPattern(app: habit.app, previous: habit.previous, command: habit.command)
        relearn()
    }
}
