import Foundation

/// Replays a chronological run log: train on the past, predict the future, score against what really ran.
///
/// Everything is deterministic: no randomness, no clock, events processed in time order. The model keeps learning
/// as the test part replays (`online`), because that is how the app behaves: every run it sees is learned from.
public struct PredictionEvaluator: Sendable {
    public var trainFraction = 0.5
    public var threshold = PredictionPolicy.showThreshold
    public var maxRows = PredictionPolicy.maxRows
    public var online = true
    public var calendar = Calendar.current
    public var settings = PredictionModel.Settings()

    public init() {}

    public struct Score: Sendable, Equatable {
        public var name: String
        /// Over every test event; a missing prediction is a miss.
        public var hitAt1 = 0.0
        public var hitAt3 = 0.0
        /// How often something is shown (for the model: a prediction passed the threshold).
        public var coverage = 0.0
        /// Of the times something was shown, how often the first row was not what ran.
        public var wrongWhenShown = 0.0
        /// Of the times something was shown, how often what ran was in the shown rows.
        public var shownHit = 0.0
    }

    public struct Bin: Sendable, Equatable {
        public var lower: Double
        public var count: Int
        public var meanConfidence: Double
        public var hitRate: Double
    }

    public struct Sweep: Sendable, Equatable {
        public var threshold: Double
        public var coverage: Double
        public var wrongWhenShown: Double
    }

    public struct Report: Sendable, Equatable {
        public var trainEvents = 0
        public var testEvents = 0
        public var threshold = 0.0
        public var model = Score(name: "model")
        public var frecency = Score(name: "frecency only")
        public var repeatLast = Score(name: "repeat last command")
        /// hit@1 of each baseline restricted to the moments where the model was confident enough to show something.
        public var frecencyWhereShown = 0.0
        public var repeatLastWhereShown = 0.0
        public var modelWhereShown = 0.0
        public var reliability: [Bin] = []
        public var expectedCalibrationError = 0.0
        public var sweep: [Sweep] = []

        /// Aggregate numbers only, safe to print for a real log.
        public func render() -> String {
            func pct(_ value: Double) -> String { String(format: "%5.1f%%", value * 100) }
            var lines = [
                "train events: \(trainEvents)   test events: \(testEvents)   show threshold: \(String(format: "%.2f", threshold))"
            ]
            lines.append("                       hit@1    hit@3  coverage  wrong-when-shown")
            for score in [model, frecency, repeatLast] {
                lines.append(
                    "  \(score.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(pct(score.hitAt1)) \(pct(score.hitAt3)) \(pct(score.coverage))   \(pct(score.wrongWhenShown))"
                )
            }
            lines.append(
                "  on the moments the model shows: model \(pct(modelWhereShown)), frecency only \(pct(frecencyWhereShown)), repeat last \(pct(repeatLastWhereShown)) (hit@1)"
            )
            lines.append("  shown rows contain the right command: \(pct(model.shownHit))")
            lines.append(
                "  calibration (top confidence vs how often it was right), error \(String(format: "%.3f", expectedCalibrationError)):"
            )
            for bin in reliability where bin.count > 0 {
                lines.append(
                    "    confidence \(String(format: "%.1f", bin.lower))-\(String(format: "%.1f", bin.lower + 0.1)): n=\(bin.count) mean \(String(format: "%.2f", bin.meanConfidence)) right \(pct(bin.hitRate))"
                )
            }
            lines.append("  threshold sweep:")
            for row in sweep {
                lines.append(
                    "    \(String(format: "%.2f", row.threshold)): coverage \(pct(row.coverage)) wrong-when-shown \(pct(row.wrongWhenShown))"
                )
            }
            return lines.joined(separator: "\n")
        }
    }

    /// The smallest threshold at which no more than `maxWrong` of the shown predictions are wrong, if any.
    public static func recommendedThreshold(_ sweep: [Sweep], maxWrong: Double) -> Double? {
        sweep.first { $0.coverage > 0 && $0.wrongWhenShown <= maxWrong }?.threshold
    }

    // MARK: Replay

    /// Frecency and recency baselines, kept as the app would.
    private struct History {
        var runs: [CommandID: Int] = [:]
        var times: [CommandID: [Date]] = [:]
        var recentByApp: [String: [CommandID]] = [:]

        mutating func add(_ event: RunEvent) {
            runs[event.command, default: 0] += 1
            var list = times[event.command, default: []]
            list.append(event.date)
            if list.count > Frecency.sampleLimit { list.removeFirst(list.count - Frecency.sampleLimit) }
            times[event.command] = list
            var recent = recentByApp[event.app, default: []]
            recent.removeAll { $0 == event.command }
            recent.insert(event.command, at: 0)
            if recent.count > 3 { recent.removeLast() }
            recentByApp[event.app] = recent
        }

        func scores(now: Date) -> [CommandID: Double] {
            var result: [CommandID: Double] = [:]
            for (id, count) in runs { result[id] = Frecency.score(runs: count, recent: times[id] ?? [], now: now) }
            return result
        }
    }

    public func run(_ input: [RunEvent]) -> Report {
        let events = input.filter { $0.kind == .run }.sorted { $0.time < $1.time }
        var report = Report()
        report.threshold = threshold
        guard events.count >= 4 else { return report }
        let split = min(max(Int(Double(events.count) * trainFraction), 1), events.count - 1)
        var model = PredictionModel(settings: settings, calendar: calendar)
        var history = History()
        // The model trains on the past with the full log (dismissals included).
        let cutoff = events[split - 1].time
        let everything = input.sorted { $0.time < $1.time }
        model.train(everything.filter { $0.time <= cutoff })
        for event in events[..<split] { history.add(event) }
        report.trainEvents = split
        report.testEvents = events.count - split

        var prior = FrecencyPrior(scores: history.scores(now: events[split].date))
        var sinceRebuild = 0
        var tally = Tally()
        var preceding: RunEvent? = events[split - 1]
        for index in split..<events.count {
            let event = events[index]
            if sinceRebuild >= 10 {
                prior = FrecencyPrior(scores: history.scores(now: event.date))
                sinceRebuild = 0
            }
            let second = (preceding?.command == event.previous) ? preceding?.previous : nil
            let recent = [event.previous, second].compactMap { $0 }
            let context = PredictionContext(
                app: event.app, recent: recent, date: event.date, contextKinds: event.contextKinds)
            let predictions = model.predict(context, limit: 3, prior: prior)
            let frecencyRanked = prior.rankedCommands(app: event.app, limit: 3)
            let recentRanked = history.recentByApp[event.app] ?? []
            tally.add(
                actual: event.command, model: predictions, frecency: frecencyRanked, repeatLast: recentRanked,
                threshold: threshold, maxRows: maxRows)
            if online { model.observe(event, preceding: preceding) }
            history.add(event)
            sinceRebuild += 1
            preceding = event
        }
        tally.fill(&report)
        return report
    }

    private struct Tally {
        var total = 0
        var model = Counts(), frecency = Counts(), repeatLast = Counts()
        var bins = Array(repeating: (count: 0, confidence: 0.0, hits: 0), count: 10)
        var sweepShown: [Int] = Array(repeating: 0, count: PredictionEvaluator.sweepThresholds.count)
        var sweepWrong: [Int] = Array(repeating: 0, count: PredictionEvaluator.sweepThresholds.count)
        var shownOnModel = (model: 0, frecency: 0, repeatLast: 0, count: 0)

        struct Counts {
            var hit1 = 0, hit3 = 0, shown = 0, wrong = 0, shownHit = 0
        }

        mutating func add(
            actual: CommandID, model predictions: [Prediction], frecency: [CommandID], repeatLast: [CommandID],
            threshold: Double, maxRows: Int
        ) {
            total += 1
            let modelIDs = predictions.map(\.command)
            let top = predictions.first
            let shownRows = PredictionPolicy.rows(from: predictions, threshold: threshold, maxRows: maxRows)
            let modelShown = !shownRows.isEmpty
            model.hit1 += modelIDs.first == actual ? 1 : 0
            model.hit3 += modelIDs.prefix(3).contains(actual) ? 1 : 0
            if modelShown {
                let rows = shownRows.map(\.command)
                model.shown += 1
                model.wrong += modelIDs.first == actual ? 0 : 1
                model.shownHit += rows.contains(actual) ? 1 : 0
                shownOnModel.count += 1
                shownOnModel.model += modelIDs.first == actual ? 1 : 0
                shownOnModel.frecency += frecency.first == actual ? 1 : 0
                shownOnModel.repeatLast += repeatLast.first == actual ? 1 : 0
            }
            Self.baseline(&self.frecency, actual: actual, ranked: frecency)
            Self.baseline(&self.repeatLast, actual: actual, ranked: repeatLast)
            if let top {
                let slot = min(Int(top.confidence * 10), 9)
                bins[slot].count += 1
                bins[slot].confidence += top.confidence
                bins[slot].hits += top.command == actual ? 1 : 0
                for (index, level) in PredictionEvaluator.sweepThresholds.enumerated() where top.confidence >= level {
                    sweepShown[index] += 1
                    sweepWrong[index] += top.command == actual ? 0 : 1
                }
            }
        }

        private static func baseline(_ counts: inout Counts, actual: CommandID, ranked: [CommandID]) {
            counts.hit1 += ranked.first == actual ? 1 : 0
            counts.hit3 += ranked.prefix(3).contains(actual) ? 1 : 0
            guard !ranked.isEmpty else { return }
            counts.shown += 1
            counts.wrong += ranked.first == actual ? 0 : 1
            counts.shownHit += ranked.prefix(1).contains(actual) ? 1 : 0
        }

        func fill(_ report: inout Report) {
            guard total > 0 else { return }
            func score(_ name: String, _ counts: Counts) -> Score {
                Score(
                    name: name, hitAt1: Double(counts.hit1) / Double(total),
                    hitAt3: Double(counts.hit3) / Double(total),
                    coverage: Double(counts.shown) / Double(total),
                    wrongWhenShown: counts.shown > 0 ? Double(counts.wrong) / Double(counts.shown) : 0,
                    shownHit: counts.shown > 0 ? Double(counts.shownHit) / Double(counts.shown) : 0)
            }
            report.model = score("model", model)
            report.frecency = score("frecency only", frecency)
            report.repeatLast = score("repeat last command", repeatLast)
            if shownOnModel.count > 0 {
                let count = Double(shownOnModel.count)
                report.modelWhereShown = Double(shownOnModel.model) / count
                report.frecencyWhereShown = Double(shownOnModel.frecency) / count
                report.repeatLastWhereShown = Double(shownOnModel.repeatLast) / count
            }
            var ece = 0.0
            var counted = 0
            for (index, bin) in bins.enumerated() {
                let rate = bin.count > 0 ? Double(bin.hits) / Double(bin.count) : 0
                let mean = bin.count > 0 ? bin.confidence / Double(bin.count) : 0
                report.reliability.append(
                    Bin(lower: Double(index) / 10, count: bin.count, meanConfidence: mean, hitRate: rate))
                ece += Double(bin.count) * abs(rate - mean)
                counted += bin.count
            }
            report.expectedCalibrationError = counted > 0 ? ece / Double(counted) : 0
            for (index, level) in PredictionEvaluator.sweepThresholds.enumerated() {
                report.sweep.append(
                    Sweep(
                        threshold: level, coverage: Double(sweepShown[index]) / Double(total),
                        wrongWhenShown: sweepShown[index] > 0
                            ? Double(sweepWrong[index]) / Double(sweepShown[index]) : 0))
            }
        }
    }

    static let sweepThresholds: [Double] = stride(from: 0.2, through: 0.95, by: 0.05).map { ($0 * 100).rounded() / 100 }
}

/// When the palette may show a prediction. The numbers come from `PredictionEvaluator` runs on the synthetic log
/// (`apropos-probe --predict-eval --synthetic 365`), recorded in docs/prediction.md: the first threshold is the smallest
/// one at which no more than one shown prediction in ten was wrong.
public enum PredictionPolicy {
    /// The first row is shown only when the model puts at least this probability on it. Nothing is shown otherwise.
    public static let showThreshold = 0.65
    /// A second row joins the first when it is at least this likely too: the runner-up of a clear favourite.
    public static let secondRowThreshold = 0.25
    /// Rows under "Usually next".
    public static let maxRows = 2

    /// The predictions to show, best first: empty unless the best one passes `threshold`.
    public static func rows(
        from predictions: [Prediction], threshold: Double = showThreshold, maxRows: Int = maxRows
    ) -> [Prediction] {
        guard let top = predictions.first, top.confidence >= threshold else { return [] }
        return Array(
            predictions.enumerated().filter { $0.offset == 0 || $0.element.confidence >= secondRowThreshold }
                .map(\.element).prefix(maxRows))
    }
}

extension FrecencyPrior {
    /// The app's commands by learned usage, best first.
    func rankedCommands(app: String, limit: Int) -> [CommandID] {
        commands(app: app).sorted { (share(of: $0), $1) > (share(of: $1), $0) }.prefix(limit).map { $0 }
    }
}
