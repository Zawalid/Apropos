import Foundation

/// Frecency: how often and how recently a command was run, in one number. The same bucket weights Firefox uses for
/// its address bar: a run counts for more the more recent it is, and the score is scaled by the total run count so a
/// command run a hundred times beats one run five times even when only the last few runs are remembered.
public enum Frecency {
    /// How many individual run times are kept per command.
    public static let sampleLimit = 10

    static func weight(ageInDays days: Double) -> Double {
        switch days {
        case ..<4: 100
        case ..<14: 70
        case ..<31: 50
        case ..<90: 30
        default: 10
        }
    }

    /// - Parameters:
    ///   - runs: Total number of runs ever recorded.
    ///   - recent: The most recent run times, at most `sampleLimit`.
    public static func score(runs: Int, recent: [Date], now: Date) -> Double {
        guard runs > 0, !recent.isEmpty else { return 0 }
        let total = recent.reduce(0.0) { sum, date in
            sum + weight(ageInDays: max(now.timeIntervalSince(date), 0) / 86_400)
        }
        return Double(runs) * total / Double(recent.count)
    }

    /// Maps a frecency score to the integer the ranker adds to a fuzzy match score. Logarithmic and capped, so
    /// usage breaks ties and nudges close matches but never lifts a poor match over a good one.
    public static func boost(forScore score: Double) -> Int {
        guard score > 0 else { return 0 }
        return Int(min(60, 10 * log2(1 + score / 50)))
    }
}
