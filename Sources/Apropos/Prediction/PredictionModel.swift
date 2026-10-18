import Foundation

/// How often each command was run per app, from the existing usage store: the cold-start fallback. A person with a
/// year of usage and no sequence log yet still gets an honest, if weak, guess.
public struct FrecencyPrior: Sendable {
    private let shares: [CommandID: Double]
    private let byApp: [String: [CommandID]]

    public init(scores: [CommandID: Double]) {
        var totals: [String: Double] = [:]
        for (id, score) in scores where score > 0 { totals[id.bundleID ?? "", default: 0] += score }
        var shares: [CommandID: Double] = [:]
        var byApp: [String: [CommandID]] = [:]
        for (id, score) in scores where score > 0 {
            let total = totals[id.bundleID ?? ""] ?? 0
            guard total > 0 else { continue }
            shares[id] = score / total
            byApp[id.bundleID ?? "", default: []].append(id)
        }
        self.shares = shares
        self.byApp = byApp
    }

    public static let empty = FrecencyPrior(scores: [:])

    /// The fraction of the app's learned usage that this command holds, 0 for an unknown one.
    public func share(of id: CommandID) -> Double { shares[id] ?? 0 }

    func commands(app: String) -> [CommandID] { byApp[app] ?? [] }
}

/// Counting model of which command comes next. Interpretable on purpose: every number is a count in a table, and a
/// prediction can say which counts it came from.
///
/// For one moment it looks up up to six small tables, from the vaguest to the most specific:
///
/// 1. the app alone,
/// 2. the app at this time of day and kind of weekday,
/// 3. the app with these kinds of context present,
/// 4. the command that ran just before, in any app (the cross-app link: after a build in Xcode, a command in Terminal),
/// 5. that command in this app,
/// 6. the last two commands in this app.
///
/// Each table answers "of the times we were here, how often was it this command", with Laplace smoothing. The answers
/// are blended from the vague end: each table is trusted in proportion to how much evidence it holds
/// (`evidence / (evidence + pseudoCount)`) and the rest of the trust falls back to the tables below it, with the
/// frecency share of the command as the floor. Counts decay exponentially with age, so a changed habit takes over.
public struct PredictionModel: Sendable {
    public struct Settings: Sendable, Equatable {
        /// Days after which a run counts for half.
        public var halfLifeDays = 30.0
        /// Laplace smoothing added to each command and once for "something else".
        public var smoothing = 0.5
        /// How much evidence a table needs before it is trusted halfway.
        public var pseudoCount = 2.0
        /// Minimum raw counts for a table to be quoted in a reason.
        public var reasonMinimumTotal = 3
        public var reasonMinimumCount = 2
        public init() {}
    }

    let settings: Settings
    let calendar: Calendar
    private let halfLife: Double

    private var commandIndex: [CommandID: Int32] = [:]
    private var commands: [CommandID] = []
    private var appIndex: [String: Int32] = [:]
    private var tables: [TableKey: Bucket] = [:]
    private var feedback: [Int32: Feedback] = [:]
    private var lastTime: Double = 0
    /// How many run events the model has seen.
    public private(set) var runCount = 0

    public init(settings: Settings = Settings(), calendar: Calendar = .current) {
        self.settings = settings
        self.calendar = calendar
        halfLife = settings.halfLifeDays * 86_400
    }

    // MARK: Tables

    private enum Level: UInt8, CaseIterable {
        case app = 0, slot, kinds, prevAny, prevApp, prevTwo
    }

    private struct TableKey: Hashable, Sendable {
        let level: Level
        let a: Int32
        let b: Int32
        let c: Int32
    }

    private struct Counter: Sendable {
        var weight = 0.0
        var stamp = 0.0
        var raw: Int32 = 0

        mutating func add(at time: Double, halfLife: Double) {
            weight = weight * Self.decay(time - stamp, halfLife) + 1
            stamp = max(stamp, time)
            raw += 1
        }

        func weight(at time: Double, halfLife: Double) -> Double { weight * Self.decay(time - stamp, halfLife) }

        static func decay(_ elapsed: Double, _ halfLife: Double) -> Double {
            elapsed <= 0 ? 1 : exp2(-elapsed / halfLife)
        }
    }

    private struct Bucket: Sendable {
        var total = Counter()
        var next: [Int32: Counter] = [:]
    }

    private struct Feedback: Sendable {
        var accepted = Counter()
        var ignored = Counter()
        var dismissed = Counter()
    }

    // MARK: Learning

    private mutating func intern(_ id: CommandID) -> Int32 {
        if let index = commandIndex[id] { return index }
        let index = Int32(commands.count)
        commands.append(id)
        commandIndex[id] = index
        return index
    }

    private mutating func intern(app: String) -> Int32 {
        if let index = appIndex[app] { return index }
        let index = Int32(appIndex.count)
        appIndex[app] = index
        return index
    }

    private static func kindsMask(_ names: [String]) -> Int32 {
        var mask: Int32 = 0
        for (index, kind) in ContextKind.allCases.enumerated() where names.contains(kind.rawValue) { mask |= 1 << Int32(index) }
        return mask
    }

    /// Learns from events oldest first. Events are expected in time order; `PredictionModel.train` sorts them.
    public mutating func train(_ events: [RunEvent]) {
        var last: RunEvent?
        for event in events.sorted(by: { $0.time < $1.time }) {
            observe(event, preceding: last)
            if event.kind == .run { last = event }
        }
    }

    /// Learns from one more event. `preceding` is the run event before it, which gives the second command back.
    public mutating func observe(_ event: RunEvent, preceding: RunEvent?) {
        let time = event.time
        lastTime = max(lastTime, time)
        let command = intern(event.command)
        switch event.kind {
        case .dismiss:
            feedback[command, default: Feedback()].dismissed.add(at: time, halfLife: halfLife)
            return
        case .run:
            break
        }
        runCount += 1
        if let offered = event.offered {
            let index = intern(offered)
            if offered == event.command {
                feedback[index, default: Feedback()].accepted.add(at: time, halfLife: halfLife)
            } else {
                feedback[index, default: Feedback()].ignored.add(at: time, halfLife: halfLife)
            }
        }
        let app = intern(app: event.app)
        let slot = TimeSlot(event.date, calendar: calendar).packed
        let mask = Self.kindsMask(event.contextKinds)
        func add(_ key: TableKey) {
            var bucket = tables[key] ?? Bucket()
            bucket.total.add(at: time, halfLife: halfLife)
            bucket.next[command, default: Counter()].add(at: time, halfLife: halfLife)
            tables[key] = bucket
        }
        // Whether something ran a moment ago is part of the moment: the first command after a pause is not the same
        // question as the next one in a run of work.
        let continuing: Int32 = event.previous == nil ? 0 : 1
        add(TableKey(level: .app, a: app, b: 0, c: continuing))
        add(TableKey(level: .slot, a: app, b: slot, c: continuing))
        if mask != 0 { add(TableKey(level: .kinds, a: app, b: mask, c: continuing)) }
        if let previous = event.previous {
            let first = intern(previous)
            add(TableKey(level: .prevAny, a: first, b: 0, c: 0))
            add(TableKey(level: .prevApp, a: app, b: first, c: 0))
            if let preceding, preceding.command == previous, let second = preceding.previous {
                add(TableKey(level: .prevTwo, a: app, b: first, c: intern(second)))
            }
        }
    }

    // MARK: Predicting

    /// The commands run in this app, plus context actions, are the ones a prediction may name by default.
    public static func isAvailable(_ id: CommandID, in app: String) -> Bool {
        guard let bundle = id.bundleID else { return true }
        return bundle == app
    }

    /// The most likely next commands, best first.
    ///
    /// - Parameters:
    ///   - candidates: The commands that can run right now. When nil, every command of the app and every context
    ///     action the model has seen.
    ///   - prior: The frecency fallback.
    ///   - title: How to name a command in a reason. Defaults to a title taken from the identity.
    public func predict(
        _ context: PredictionContext, limit: Int = 3, candidates: Set<CommandID>? = nil,
        prior: FrecencyPrior = .empty, title: (CommandID) -> String = { $0.fallbackTitle }
    ) -> [Prediction] {
        let now = context.date.timeIntervalSince1970
        let appID = appIndex[context.app]
        let slot = TimeSlot(context.date, calendar: calendar)
        let mask = Self.kindsMask(context.contextKinds)
        let first = context.recent.first.flatMap { commandIndex[$0] }
        let second = context.recent.dropFirst().first.flatMap { commandIndex[$0] }

        // The tables that exist for this moment, vague to specific.
        var chain: [(level: Level, bucket: Bucket, total: Double)] = []
        func add(_ level: Level, _ key: TableKey?) {
            guard let key, let bucket = tables[key] else { return }
            chain.append((level, bucket, bucket.total.weight(at: now, halfLife: halfLife)))
        }
        let continuing: Int32 = first == nil ? 0 : 1
        add(.app, appID.map { TableKey(level: .app, a: $0, b: 0, c: continuing) })
        add(.slot, appID.map { TableKey(level: .slot, a: $0, b: slot.packed, c: continuing) })
        if mask != 0 { add(.kinds, appID.map { TableKey(level: .kinds, a: $0, b: mask, c: continuing) }) }
        add(.prevAny, first.map { TableKey(level: .prevAny, a: $0, b: 0, c: 0) })
        if let appID, let first {
            add(.prevApp, TableKey(level: .prevApp, a: appID, b: first, c: 0))
            if let second { add(.prevTwo, TableKey(level: .prevTwo, a: appID, b: first, c: second)) }
        }

        // Who can be named: the given commands, else everything the tables mention that belongs here.
        var universe: [CommandID]
        if let candidates {
            universe = Array(candidates)
        } else {
            var seen = Set<Int32>()
            for entry in chain { seen.formUnion(entry.bucket.next.keys) }
            universe = seen.map { commands[Int($0)] }.filter { Self.isAvailable($0, in: context.app) }
            universe.append(contentsOf: prior.commands(app: context.app).filter { commandIndex[$0] == nil })
        }

        var scored: [Prediction] = []
        scored.reserveCapacity(min(universe.count, 64))
        for id in universe {
            let index = commandIndex[id]
            var probability = prior.share(of: id)
            var basis = probability > 0 ? PredictionBasis.frecency : nil
            var strongest = 0.0
            for entry in chain {
                let counter = index.flatMap { entry.bucket.next[$0] }
                let count = counter?.weight(at: now, halfLife: halfLife) ?? 0
                let distinct = Double(entry.bucket.next.count)
                let smoothed = (count + settings.smoothing) / (entry.total + settings.smoothing * (distinct + 1))
                let trust = entry.total / (entry.total + settings.pseudoCount)
                probability = trust * smoothed + (1 - trust) * probability
                let contribution = trust * smoothed
                if count > 0, contribution >= strongest * 0.9 || basis == nil {
                    // The most specific table that still carries real weight is the one quoted.
                    strongest = max(strongest, contribution)
                    basis = Self.basis(for: entry.level)
                }
            }
            guard probability > 0, let basis else { continue }
            let confidence = probability * feedbackFactor(index, at: now)
            scored.append(
                Prediction(command: id, confidence: confidence, reason: "", basis: basis))
        }
        scored.sort { ($0.confidence, $1.command) > ($1.confidence, $0.command) }
        return scored.prefix(limit).map { prediction in
            Prediction(
                command: prediction.command, confidence: prediction.confidence,
                reason: reason(
                    for: prediction, context: context, chain: chain.map { ($0.level, $0.bucket) }, slot: slot,
                    prior: prior, title: title),
                basis: prediction.basis)
        }
    }

    private static func basis(for level: Level) -> PredictionBasis {
        switch level {
        case .prevTwo: .afterTwoCommands
        case .prevApp: .afterCommand
        case .prevAny: .afterCommandAnyApp
        case .kinds: .contextKinds
        case .slot: .timeOfDay
        case .app: .appHabit
        }
    }

    /// How much the person's reactions to this prediction scale it: accepting keeps it, ignoring weakens it a little,
    /// Not now weakens it a lot. With no reactions the factor is 1.
    private func feedbackFactor(_ index: Int32?, at time: Double) -> Double {
        guard let index, let record = feedback[index] else { return 1 }
        let accepted = record.accepted.weight(at: time, halfLife: halfLife)
        let ignored = record.ignored.weight(at: time, halfLife: halfLife)
        let dismissed = record.dismissed.weight(at: time, halfLife: halfLife)
        return (accepted + 1) / (accepted + 0.5 * ignored + 2 * dismissed + 1)
    }

    // MARK: Reasons

    private func reason(
        for prediction: Prediction, context: PredictionContext, chain: [(Level, Bucket)], slot: TimeSlot,
        prior: FrecencyPrior, title: (CommandID) -> String
    ) -> String {
        let name = title(prediction.command)
        guard let index = commandIndex[prediction.command] else {
            return "You use \(name) often in this app"
        }
        // The most specific table with enough raw evidence and a real share for this command.
        for (level, bucket) in chain.reversed() {
            let total = Int(bucket.total.raw)
            guard let count = bucket.next[index].map({ Int($0.raw) }),
                total >= settings.reasonMinimumTotal, count >= settings.reasonMinimumCount,
                Double(count) / Double(total) >= 0.3
            else { continue }
            let times = "\(count) of \(total) times"
            switch level {
            case .prevTwo:
                let one = context.recent.first.map(title) ?? ""
                let two = context.recent.dropFirst().first.map(title) ?? ""
                return "After \(two) then \(one) you chose \(name) \(times)"
            case .prevApp, .prevAny:
                return "After \(context.recent.first.map(title) ?? "that") you chose \(name) \(times)"
            case .kinds:
                return "\(Self.kindsPhrase(context.contextKinds)) you chose \(name) \(times)"
            case .slot:
                return "\(slot.phrase.prefix(1).uppercased() + slot.phrase.dropFirst()) you chose \(name) \(times)"
            case .app:
                return "You chose \(name) \(times) in this app"
            }
        }
        if prior.share(of: prediction.command) > 0 { return "You use \(name) often in this app" }
        return "You have run \(name) before in this app"
    }

    private static func kindsPhrase(_ kinds: [String]) -> String {
        let phrases: [String: String] = [
            "selection": "With text selected", "selectionCount": "With items selected", "document": "In a document",
            "url": "On a web page", "folder": "In a folder", "branch": "In a git repository",
        ]
        let names = ContextKind.allCases.map(\.rawValue).filter { kinds.contains($0) }
        return names.first.flatMap { phrases[$0] } ?? "In this context"
    }
}
