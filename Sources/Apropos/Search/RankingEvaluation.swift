import Foundation

/// Something that orders commands for a query and learns from what was chosen. The evaluation drives one of these
/// through a simulated person's history, one run at a time, exactly as the app would.
public protocol RankingEngine {
    /// The commands in the order the panel would list them for `query` (empty means the list as it opens).
    mutating func rank(app: String, commands: [Command], query: String, previous: CommandID?, now: Date) -> [Command]
    /// The person chose `command` after typing `query`, right after running `previous`.
    mutating func learn(_ command: Command, query: String, previous: CommandID?, now: Date)
}

/// The real ranking and the real learning, over in-memory records, for any tuning. `RankingTuning.legacy` is how it
/// worked before the learning work.
public struct SimulatedRankingEngine: RankingEngine {
    private var records: [CommandID: UsageRecord] = [:]
    private var signal = UsageSignal(scores: [:], pins: [:], hidden: [], aliases: [:])
    private var signalNow = Date.distantPast
    private let tuning: RankingTuning
    private var model = PredictionModel(calendar: SimulatedRankingEngine.utc)
    private var lastEvent: RunEvent?
    private var priorKey: String?
    private var priorCache: [CommandID: Double] = [:]

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// What usually comes next, asked once per moment and kept for every keystroke of the same query.
    private mutating func priors(_ app: String, _ commands: [Command], _ previous: CommandID?, _ now: Date) -> [CommandID: Double] {
        guard tuning.priorMax > 0 else { return [:] }
        let key = "\(app)|\(previous?.rawValue ?? "")|\(Int(now.timeIntervalSince1970 / 3600))"
        if key == priorKey { return priorCache }
        let context = PredictionContext(app: app, recent: previous.map { [$0] } ?? [], date: now)
        priorCache = model.confidences(context, candidates: Set(commands.map(\.stableID)))
        priorKey = key
        return priorCache
    }
    public init(tuning: RankingTuning = RankingTuning()) { self.tuning = tuning }

    public mutating func rank(
        app: String, commands: [Command], query: String, previous: CommandID?, now: Date
    ) -> [Command] {
        refresh(now)
        let ranker = CommandRanker(signal: signal, tuning: tuning)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return ranker.rank(commands, query: trimmed, priors: priors(app, commands, previous, now)).map(\.command)
        }
        // The list as it opens: suggestions by frecency first, then the menu order, as the palette does.
        // Usually next heads it, exactly as the panel's policy allows: a confident first row, a likely second.
        var head: [Command] = []
        if tuning.priorMax > 0 {
            let chances = priors(app, commands, previous, now)
            let ordered = commands.compactMap { command in chances[command.stableID].map { (command, $0) } }
                .sorted { $0.1 > $1.1 }
            if let top = ordered.first, top.1 >= PredictionPolicy.showThreshold {
                head = ordered.enumerated().filter { $0.offset == 0 || $0.element.1 >= PredictionPolicy.secondRowThreshold }
                    .prefix(PredictionPolicy.maxRows).map(\.element.0)
            }
        }
        let taken = Set(head.map(\.stableID))
        let suggested = ranker.suggested(commands.filter { !taken.contains($0.stableID) }, limit: tuning.suggestionLimit)
            .map(\.command)
        let ids = taken.union(suggested.map(\.stableID))
        return head + suggested + ranker.rank(commands, query: "").map(\.command).filter { !ids.contains($0.stableID) }
    }

    public mutating func learn(_ command: Command, query: String, previous: CommandID?, now: Date) {
        let app = command.stableID.bundleID ?? ""
        if tuning.priorMax > 0, let event = RunEvent(at: now, command: command.stableID, app: app, previous: previous) {
            model.observe(event, preceding: lastEvent)
            lastEvent = event
        }
        priorKey = nil
        var record = records[command.stableID] ?? UsageRecord(runs: 0, recent: [])
        record.runs += 1
        record.recent.append(now)
        if record.recent.count > Frecency.sampleLimit { record.recent.removeFirst() }
        RankingMemory.learn(RankingMemory.learnable(query, for: command), into: &record)
        records[command.stableID] = record
        signalNow = .distantPast
    }

    private mutating func refresh(_ now: Date) {
        guard now.timeIntervalSince(signalNow) > 900 else { return }
        signal = UsageSignal.build(records: records, pins: [:], hidden: [], aliases: [:], now: now, tuning: tuning)
        signalNow = now
    }
}

public enum RankingEvaluation {
    public struct Report: Sendable {
        public var runs = 0
        /// Keystrokes plus half a point per arrow-key press, until the target is chosen. Lower is better.
        public var meanCost = 0.0
        /// Share of runs where the target was first in the list at the point the person stopped.
        public var firstShare = 0.0
        public var withinThreeShare = 0.0
        /// Mean reciprocal rank after two typed characters, for people who type.
        public var mrrAtTwo = 0.0
        /// Mean cost for people who browse and pick from the list as it opens.
        public var browseCost = 0.0
        /// Mean cost by habit.
        public var costByHabit: [String: Double] = [:]
        /// The worst rank any target had when the person stopped, a sign of a bad surprise.
        public var worstRank = 0
    }

    /// Runs one person through `intentCount` runs, learning as it goes, and scores the second half, after the engine
    /// has had time to learn.
    public static func evaluate(
        engine makeEngine: () -> some RankingEngine, seed: UInt64, intentCount: Int = 1200,
        driftAt: Int? = nil, runsPerDay: Int = 30
    ) -> Report {
        var engine = makeEngine()
        var person = RankingSimulation.person(seed: seed)
        person.driftAt = driftAt
        let intents = RankingSimulation.intents(for: person, count: intentCount)
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        var report = Report()
        var costs: [Double] = []
        var browse: [Double] = []
        var byHabit: [String: [Double]] = [:]
        var reciprocal: [Double] = []
        var first = 0
        var three = 0

        for (index, intent) in intents.enumerated() {
            let now = start.addingTimeInterval(Double(index) / Double(runsPerDay) * 86_400)
            guard let catalogue = RankingSimulation.catalogues.first(where: { $0.app == intent.app }),
                let item = catalogue.items.first(where: { $0.id == intent.itemID })
            else { continue }
            let commands = catalogue.commands
            let targetID = CommandID.base(bundleID: intent.app, path: item.path, title: item.title)
            let scored = index >= intentCount / 2
            let previousID = intent.previous.flatMap { previous -> CommandID? in
                guard let item = RankingSimulation.catalogues.first(where: { $0.app == previous.app })?.items.first(where: { $0.id == previous.id }) else { return nil }
                return CommandID.base(bundleID: previous.app, path: item.path, title: item.title)
            }

            var cost = 0.0
            var stoppedRank = 0
            var typedForLearning = intent.typed
            if intent.typed.isEmpty {
                let order = engine.rank(app: intent.app, commands: commands, query: "", previous: previousID, now: now)
                let rank = (order.firstIndex { $0.stableID == targetID } ?? order.count) + 1
                cost = Double(rank - 1) * 0.5
                stoppedRank = rank
                if scored { browse.append(cost) }
            } else {
                let letters = Array(intent.typed)
                var reached = false
                for length in 1...letters.count {
                    let query = String(letters.prefix(length))
                    let order = engine.rank(app: intent.app, commands: commands, query: query, previous: previousID, now: now)
                    let rank = (order.firstIndex { $0.stableID == targetID } ?? Int.max / 2) + 1
                    if length == min(2, letters.count), scored { reciprocal.append(1.0 / Double(rank)) }
                    // A person stops typing when the target is in the first three.
                    if rank <= 3 || length == letters.count {
                        cost = Double(length) + Double(min(rank, 12) - 1) * 0.5
                        stoppedRank = rank
                        typedForLearning = query
                        reached = true
                        break
                    }
                }
                if !reached { cost = Double(letters.count) + 6 }
            }
            if scored {
                costs.append(cost)
                byHabit["\(intent.habit)", default: []].append(cost)
                if stoppedRank == 1 { first += 1 }
                if stoppedRank <= 3 { three += 1 }
                report.worstRank = max(report.worstRank, min(stoppedRank, 999))
            }
            if let command = commands.first(where: { $0.stableID == targetID }) {
                engine.learn(command, query: typedForLearning, previous: previousID, now: now)
            }
        }
        report.runs = costs.count
        report.meanCost = costs.reduce(0, +) / Double(max(costs.count, 1))
        report.firstShare = Double(first) / Double(max(costs.count, 1))
        report.withinThreeShare = Double(three) / Double(max(costs.count, 1))
        report.mrrAtTwo = reciprocal.reduce(0, +) / Double(max(reciprocal.count, 1))
        report.browseCost = browse.reduce(0, +) / Double(max(browse.count, 1))
        report.costByHabit = byHabit.mapValues { $0.reduce(0, +) / Double($0.count) }
        return report
    }

    /// The average over several people, so one lucky seed does not decide.
    public static func average(
        engine: () -> some RankingEngine, seeds: [UInt64], intentCount: Int = 1200, driftAt: Int? = nil
    ) -> Report {
        let reports = seeds.map { evaluate(engine: engine, seed: $0, intentCount: intentCount, driftAt: driftAt) }
        var total = Report()
        let n = Double(reports.count)
        for report in reports {
            total.runs += report.runs
            total.meanCost += report.meanCost / n
            total.firstShare += report.firstShare / n
            total.withinThreeShare += report.withinThreeShare / n
            total.mrrAtTwo += report.mrrAtTwo / n
            total.browseCost += report.browseCost / n
            total.worstRank = max(total.worstRank, report.worstRank)
            for (habit, cost) in report.costByHabit { total.costByHabit[habit, default: 0] += cost / n }
        }
        return total
    }

    public static func describe(_ name: String, _ report: Report) -> String {
        let habits = report.costByHabit.sorted { $0.key < $1.key }
            .map { "\($0.key) \(String(format: "%.2f", $0.value))" }.joined(separator: ", ")
        return String(
            format: "%@: cost %.3f, first %.1f%%, top3 %.1f%%, MRR@2 %.3f, browse %.3f, worst %d  [%@]", name,
            report.meanCost, report.firstShare * 100, report.withinThreeShare * 100, report.mrrAtTwo,
            report.browseCost, report.worstRank, habits)
    }
}
