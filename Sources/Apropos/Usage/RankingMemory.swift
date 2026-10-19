import Foundation

/// What is learned from the person's choices: how strong a habit is, and which short names they type for which command.
/// Pure functions over `UsageRecord`, shared by the store and the evaluation so both measure the same code.
enum RankingMemory {
    static let queriesPerCommand = 8
    static let maxQueryLength = 16

    /// The typed name worth remembering for a run, or empty. Only a name that is an abbreviation of the command's own
    /// title, path or keywords is kept, in letters and digits: it is a fragment of a command name, never free text.
    static func learnable(_ query: String, for command: Command) -> String {
        let cleaned = normalise(query)
        guard !cleaned.isEmpty, cleaned.count <= maxQueryLength else { return "" }
        guard cleaned.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " }) else { return "" }
        let fields = [command.title, command.searchPath] + command.keywords + command.aliases
        return fields.contains { FuzzyMatcher.match(cleaned, in: $0) != nil } ? cleaned : ""
    }

    static func normalise(_ query: String) -> String {
        String(query.trimmingCharacters(in: .whitespaces).map { FuzzyMatcher.fold($0) })
    }

    static func learn(_ query: String, into record: inout UsageRecord) {
        guard !query.isEmpty else { return }
        record.queries[query, default: 0] += 1
        if record.queries.count > queriesPerCommand, let weakest = record.queries.min(by: { $0.value < $1.value })?.key {
            record.queries[weakest] = nil
        }
    }

    /// How strong a habit is, in effective recent uses: each remembered run counts for less as it ages, and runs beyond
    /// the remembered few add a little for staying power.
    static func habit(_ record: UsageRecord, now: Date, halfLifeDays: Double) -> Double {
        var total = 0.0
        for date in record.recent {
            let age = max(now.timeIntervalSince(date), 0) / 86_400
            total += pow(0.5, age / halfLifeDays)
        }
        let beyond = max(record.runs - record.recent.count, 0)
        return total + 0.5 * log2(1 + Double(beyond))
    }

    /// For every typed name, how often each prefix of it led to each command, per app. P(command | query) falls out.
    struct Index: Sendable {
        /// "bundle|prefix" -> total choices behind that prefix.
        private var totals: [String: Double] = [:]
        /// command -> prefix -> choices.
        private var byCommand: [CommandID: [String: Double]] = [:]

        init() {}

        init(records: [CommandID: UsageRecord]) {
            for (id, record) in records where !record.queries.isEmpty {
                let bundle = id.bundleID ?? ""
                for (query, count) in record.queries {
                    let letters = Array(query)
                    for length in 1...letters.count {
                        let prefix = String(letters.prefix(length))
                        totals["\(bundle)|\(prefix)", default: 0] += Double(count)
                        byCommand[id, default: [:]][prefix, default: 0] += Double(count)
                    }
                }
            }
        }

        func signal(for id: CommandID, query: String) -> LearnedSignal {
            let key = normalise(query)
            guard !key.isEmpty, let mine = byCommand[id]?[key] else { return .none }
            let total = totals["\(id.bundleID ?? "")|\(key)"] ?? mine
            return LearnedSignal(share: mine / max(total, 1), support: total)
        }
    }
}
