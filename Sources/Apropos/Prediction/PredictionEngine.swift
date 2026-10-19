import Foundation
import Observation

/// Connects the run log, the model and the person's reactions: records runs, keeps the model current, answers "what
/// usually comes next" for the palette, and forgets everything on reset.
///
/// The log is the source of truth. The model is rebuilt from it at launch (off the main thread) and updated in place
/// after every run. Nothing here reaches the network.
@MainActor
@Observable
public final class PredictionEngine {
    public let log: SequenceLog

    /// Off: nothing is predicted and nothing new is logged. What is already in the log stays until it is reset.
    public var isEnabled = true {
        didSet { if isEnabled != oldValue { revision += 1 } }
    }
    /// Whether the reason sentence is offered for display. The engine always builds it; this is the person's choice.
    public var showsReasons = true
    /// How sure the model must be before a row is shown.
    public var sensitivity = PredictionSensitivity.balanced {
        didSet { if sensitivity != oldValue { revision += 1 } }
    }
    /// Rows under Usually next, 1 or 2.
    public var maxRows = PredictionPolicy.maxRows {
        didSet { if maxRows != oldValue { revision += 1 } }
    }
    /// Apps where nothing is learned and nothing is predicted.
    public var excludedApps: Set<String> = [] {
        didSet { if excludedApps != oldValue { revision += 1 } }
    }
    /// While set to a future time, runs are not recorded. Predictions keep working from what is known.
    public private(set) var pausedUntil: Date?

    public var isLearningPaused: Bool { pausedUntil.map { $0 > Date() } ?? false }

    public func pauseLearning(for interval: TimeInterval) { pausedUntil = Date().addingTimeInterval(interval) }

    public func resumeLearning() { pausedUntil = nil }
    /// Bumped whenever the answer to `rows` could differ, so a view knows to ask again.
    public private(set) var revision = 0
    public private(set) var isReady = false
    /// Called when the model finished building from the log, so a palette that opened first can ask again.
    @ObservationIgnored public var onReady: (() -> Void)?

    @ObservationIgnored private var model: PredictionModel
    @ObservationIgnored private var prior = FrecencyPrior.empty
    @ObservationIgnored private var titles: [CommandID: String] = [:]
    @ObservationIgnored private var lastRun: RunEvent?
    @ObservationIgnored private var offer: (command: CommandID, at: Date)?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var generation = 0

    /// A shown prediction stays attached to the next run for this long; after that the palette was probably closed
    /// without a choice and the run is unrelated.
    static let offerLifetime: TimeInterval = 120

    public init(log: SequenceLog, calendar: Calendar = .current, buildInBackground: Bool = true) {
        self.log = log
        self.calendar = calendar
        model = PredictionModel(calendar: calendar)
        lastRun = log.events.last { $0.kind == .run }
        if buildInBackground {
            let events = log.events
            let settings = model.settings
            generation += 1
            let token = generation
            Task { [weak self] in
                let trained = await Task.detached(priority: .utility) {
                    var fresh = PredictionModel(settings: settings, calendar: calendar)
                    fresh.train(events)
                    return fresh
                }.value
                self?.finishBuilding(trained, through: events.last?.time ?? 0, token: token)
            }
        } else {
            model.train(log.events)
            isReady = true
        }
    }

    private func finishBuilding(_ built: PredictionModel, through time: Double, token: Int) {
        guard token == generation else { return }
        var built = built
        // Runs that happened while the model was being built.
        var preceding = log.events.last { $0.kind == .run && $0.time <= time }
        for event in log.events where event.time > time {
            built.observe(event, preceding: preceding)
            if event.kind == .run { preceding = event }
        }
        model = built
        isReady = true
        revision += 1
        onReady?()
    }

    // MARK: Learning

    /// Records a run: appends it to the log and teaches the model. Does nothing while prediction is off.
    @discardableResult
    public func recordRun(
        _ id: CommandID, title: String? = nil, app: String?, contextKinds: [ContextKind] = [], at date: Date = Date()
    ) -> RunEvent? {
        guard isEnabled, !isLearningPaused, !(app.map(excludedApps.contains) ?? false) else { return nil }
        let shown = currentOffer(at: date)
        offer = nil
        guard let event = log.recordRun(id, app: app, contextKinds: contextKinds, offered: shown, at: date) else {
            return nil
        }
        if let title { remember(title, for: id) }
        model.observe(event, preceding: lastRun)
        lastRun = event
        revision += 1
        return event
    }

    /// The person chose Not now on a prediction.
    public func dismiss(_ id: CommandID, app: String?, contextKinds: [ContextKind] = [], at date: Date = Date()) {
        guard isEnabled, let event = log.recordDismissal(of: id, app: app, contextKinds: contextKinds, at: date) else {
            return
        }
        model.observe(event, preceding: lastRun)
        offer = nil
        revision += 1
    }

    /// Takes in fresh frecency scores from the usage store for the cold-start fallback.
    public func setPrior(_ prior: FrecencyPrior) {
        self.prior = prior
    }

    /// Reads the person's choices: whether to predict at all and whether to show reasons.
    public func configure(from settings: SettingsStore) {
        isEnabled = settings.bool(.predictNextCommand)
        showsReasons = settings.bool(.showPredictionReasons)
        sensitivity = PredictionSensitivity(rawValue: settings.string(.predictionSensitivity)) ?? .balanced
        maxRows = Int(settings.string(.predictionMaxRows)).map { min(max($0, 1), PredictionPolicy.maxRows) } ?? 2
        excludedApps = Set(settings.stringList(.predictionExcludedApps))
        if let days = Int(settings.string(.predictionKeepDays)) { log.prune(keepingDays: days) }
    }

    /// Forgets one app's part of the log and relearns from what is left.
    public func reset(forApp bundleID: String) {
        log.clear(forApp: bundleID)
        relearn()
    }

    /// Rebuilds the model from the log as it is now, after part of it was removed.
    public func relearn() {
        generation += 1
        model = PredictionModel(settings: model.settings, calendar: calendar)
        model.train(log.events)
        lastRun = log.events.last { $0.kind == .run }
        offer = nil
        isReady = true
        revision += 1
    }

    /// Forgets the log and everything learned from it.
    public func reset() {
        log.clear()
        generation += 1
        model = PredictionModel(settings: model.settings, calendar: calendar)
        lastRun = nil
        offer = nil
        titles = [:]
        isReady = true
        revision += 1
    }

    /// A readable name for a command in the log: its title if it was on screen this session, else one made from its id.
    public func title(for id: CommandID) -> String { titles[id] ?? id.fallbackTitle }

    private func remember(_ title: String, for id: CommandID) {
        if titles.count > 400 { titles.removeAll(keepingCapacity: true) }
        titles[id] = title
    }

    private func currentOffer(at date: Date) -> CommandID? {
        guard let offer, date.timeIntervalSince(offer.at) <= Self.offerLifetime else { return nil }
        return offer.command
    }

    // MARK: Asking

    /// How likely each candidate is to be run next, for ranking typed searches. Empty while prediction is off or the
    /// app is excluded. Reasons are not built, so asking for a whole menu is cheap.
    public func confidences(
        app: String?, candidates: [CommandID], contextKinds: [ContextKind] = [], at date: Date = Date()
    ) -> [CommandID: Double] {
        guard isEnabled, isReady, let app, !candidates.isEmpty, !excludedApps.contains(PredictionPrivacy.cleanApp(app))
        else { return [:] }
        let context = PredictionContext(
            app: PredictionPrivacy.cleanApp(app), recent: log.recentCommands(at: date), date: date,
            contextKinds: contextKinds.map(\.rawValue))
        return model.confidences(context, candidates: Set(candidates), prior: prior)
    }

    /// What to show under "Usually next" now: empty unless the best prediction clears the threshold.
    ///
    /// - Parameters:
    ///   - candidates: The commands that can run right now with their on-screen titles. Pinned and hidden commands are
    ///     left out by the caller.
    ///   - kinds: The kinds of context present in the app in front.
    public func rows(
        app: String?, candidates: [CommandID: String], contextKinds: [ContextKind] = [], at date: Date = Date()
    ) -> [Prediction] {
        guard isEnabled, isReady, let app, !candidates.isEmpty, !excludedApps.contains(PredictionPrivacy.cleanApp(app))
        else { return [] }
        let context = PredictionContext(
            app: PredictionPrivacy.cleanApp(app), recent: log.recentCommands(at: date), date: date,
            contextKinds: contextKinds.map(\.rawValue))
        let known = titles
        let predictions = model.predict(
            context, limit: PredictionPolicy.maxRows + 1, candidates: Set(candidates.keys), prior: prior,
            title: { candidates[$0] ?? known[$0] ?? $0.fallbackTitle })
        let rows = PredictionPolicy.rows(from: predictions, threshold: sensitivity.threshold, maxRows: maxRows)
            .map { showsReasons ? $0 : $0.withoutReason() }
        if let top = rows.first { offer = (top.command, date) }
        return rows
    }
}
