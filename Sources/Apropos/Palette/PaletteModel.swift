import Foundation
import Observation

/// What the list area of the palette shows.
public enum PaletteContent: Equatable {
    case needsPermission
    case noApp
    case loading
    case noCommands(appName: String)
    case failed(String)
    case noMatches(query: String)
    case results
}

/// All the palette's behaviour: query, ranked results, selection and running a command. Views only render it.
@MainActor
@Observable
public final class PaletteModel {
    public var query = "" {
        didSet { if query != oldValue { selectedID = nil } }
    }
    /// The ranked commands for the current query. Recomputed only when the query or the command list changes.
    public var results: [RankedCommand] {
        let key = CacheKey(
            revision: menus.revision, query: query, rankerRevision: rankerRevision, contextRevision: contextRevision,
            predictionRevision: predictionRevision, targetPID: tracker.app?.pid, sendRevision: sendCenter?.revision ?? 0
        )
        if key != cacheKey {
            computeResults()
            cacheKey = key
        }
        return cachedResults
    }

    /// With an empty query the list opens with pinned commands, then suggestions, then the rest of the menus. These are
    /// the sizes of the first two groups (both 0 while searching), so a view can draw their headers.
    public var leadingGroups: (pinned: Int, suggested: Int) {
        _ = results
        return (pinnedCount, suggestedCount)
    }
    /// With an empty query, how many rows sit in the Usually next group: right after the pinned ones, before the
    /// suggestions. At most `PredictionPolicy.maxRows`, and 0 while searching or when nothing is likely enough.
    public var predictedCount: Int {
        _ = results
        return predictedRows
    }

    /// Why a row is in the Usually next group, a sentence built from real counts. Nil for any other row.
    public func predictionReason(forRowID id: String) -> String? {
        _ = results
        return predictionReasons[id]
    }

    /// Whether a row is in the Usually next group, for offering Not now on it.
    public func isPredicted(rowID id: String) -> Bool {
        _ = results
        return predictedRowIDs.contains(id)
    }

    /// The command the top Usually next row stands for, or nil when the group is empty.
    public var topPrediction: Command? {
        let list = results
        let start = pinnedCount
        return predictedRows > 0 && list.indices.contains(start) ? list[start].command : nil
    }

    /// An explicit choice made with the arrow keys; nil means the first available result.
    public private(set) var selectedID: String?
    /// Shown inline after a command failed to run.
    public private(set) var runError: String?
    /// The result of the last context action, for a short notice ("Copied", "12 words, 80 characters"). Cleared when a
    /// new command starts.
    public private(set) var lastOutcome: ActionOutcome?
    /// A context action waiting for the person to confirm it. The view asks, then calls `confirmPending()` or
    /// `cancelPending()`.
    public private(set) var pendingConfirmation: Command?
    /// What the last send-to row did: "Sent to Notes". Cleared when a new command starts.
    public private(set) var lastSend: SendOutcome?
    /// The row that last sent successfully, for the caller to record in the usage store. Ids only.
    public private(set) var lastSentCommand: Command?

    @ObservationIgnored private let menus: AppMenuModel
    @ObservationIgnored private let tracker: FrontmostAppTracker
    @ObservationIgnored private var ranker: CommandRanker
    @ObservationIgnored private var rankerRevision = 0
    @ObservationIgnored private var contextCommands: [Command] = []
    @ObservationIgnored private var contextPID: pid_t?
    @ObservationIgnored private var contextRevision = 0
    @ObservationIgnored private var openHook: ((TargetApp?) -> Void)?
    @ObservationIgnored private var sendCenter: SendToCenter?
    @ObservationIgnored private var queryBeforeSendLevel = ""
    @ObservationIgnored private var contextRunner:
        (@MainActor (Command, TargetApp?, Bool) async -> Result<ActionOutcome, ActionError>)?
    @ObservationIgnored private var pinnedCount = 0
    @ObservationIgnored private var suggestedCount = 0
    @ObservationIgnored private var predictedRows = 0
    @ObservationIgnored private var predictionReasons: [String: String] = [:]
    @ObservationIgnored private var predictedRowIDs: Set<String> = []
    @ObservationIgnored private var predictor: (@MainActor ([Command]) -> [Prediction])?
    /// Observed on purpose: asking again for predictions must redraw a list that is already on screen.
    private var predictionRevision = 0
    @ObservationIgnored private var runner: (@MainActor (Command) async -> Result<Void, CommandRunError>)?
    @ObservationIgnored private var cachedResults: [RankedCommand] = []
    @ObservationIgnored private var cacheKey: CacheKey?

    private struct CacheKey: Equatable {
        let revision: Int
        let query: String
        let rankerRevision: Int
        let contextRevision: Int
        let predictionRevision: Int
        let targetPID: pid_t?
        let sendRevision: Int
    }

    public init(
        menus: AppMenuModel, tracker: FrontmostAppTracker, ranker: CommandRanker = CommandRanker(),
        runner: (@MainActor (Command) async -> Result<Void, CommandRunError>)? = nil
    ) {
        self.menus = menus
        self.tracker = tracker
        self.ranker = ranker
        self.runner = runner
    }

    /// How many suggestions open the list. Suggestions need some history, so a fresh install shows none.
    public static let suggestionLimit = 3

    /// Swaps the ranking rules, for example after a run, a pin or a hide changed what the usage store knows.
    public func setRanker(_ ranker: CommandRanker) {
        self.ranker = ranker
        rankerRevision += 1
    }

    /// Where "Usually next" comes from. The closure gets the commands that could be offered (available, not hidden, not
    /// pinned) and returns the predictions to show, already limited by the show threshold. Nothing is asked while the
    /// query is not empty.
    public func setPredictor(_ predictor: (@MainActor ([Command]) -> [Prediction])?) {
        self.predictor = predictor
        predictionRevision += 1
    }

    /// Asks the predictor again, for example after the context changed or the person said Not now.
    public func refreshPredictions() { predictionRevision += 1 }

    /// Context actions for the app with `pid`, built from its latest context snapshot. They are listed only while that
    /// app is the target, so another app's selection never offers actions here. They come before the menu commands.
    public func setContextCommands(_ commands: [Command], forPID pid: pid_t?) {
        contextCommands = commands
        contextPID = pid
        contextRevision += 1
    }

    /// Called each time the panel opens, after the old context actions are dropped, with the app being acted on.
    public func setOpenHook(_ hook: @escaping (TargetApp?) -> Void) { openHook = hook }

    public func setContextRunner(
        _ runner: @escaping @MainActor (Command, TargetApp?, Bool) async -> Result<ActionOutcome, ActionError>
    ) {
        contextRunner = runner
    }

    /// Connects the send-to layer: its rows are listed beside the context actions, and its destination list replaces the
    /// results while open.
    public func attachSend(_ center: SendToCenter) { sendCenter = center }

    /// The destination list that is open, for the breadcrumb chip. Nil at the top level.
    public var sendLevel: SendLevel? { sendCenter?.level }

    /// A send waiting for the confirming Return: show its one-line preview.
    public var sendPending: SendPending? { sendCenter?.pending }

    /// The send-to rows listed now, only while the app they were built for is the target.
    private var activeSendCommands: [Command] {
        guard let center = sendCenter, let pid = tracker.app?.pid, pid == center.pid else { return [] }
        return center.rootCommands
    }

    /// Context actions followed, in each group, by that group's send rows.
    private func listed(context: [Command], send: [Command]) -> [Command] {
        guard !send.isEmpty else { return context }
        var result = context
        var groups: [String] = []
        for command in send {
            let group = command.path.first ?? ""
            if !groups.contains(group) { groups.append(group) }
        }
        for group in groups {
            let rows = send.filter { ($0.path.first ?? "") == group }
            if let last = result.lastIndex(where: { ($0.path.first ?? "") == group }) {
                result.insert(contentsOf: rows, at: last + 1)
            } else {
                result.append(contentsOf: rows)
            }
        }
        return result
    }

    /// The context actions currently listed.
    private var activeContextCommands: [Command] {
        guard let pid = tracker.app?.pid, pid == contextPID else { return [] }
        return contextCommands
    }

    private func computeResults() {
        pinnedCount = 0
        suggestedCount = 0
        predictedRows = 0
        predictionReasons = [:]
        predictedRowIDs = []
        if let center = sendCenter, center.isInDestinationList {
            cachedResults = ranker.rank(center.levelCommands, query: query)
            return
        }
        let commands = listed(context: activeContextCommands, send: activeSendCommands) + menus.commands
        let base = ranker.rank(commands, query: query)
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else {
            cachedResults = base
            return
        }
        let pinned = ranker.pinned(commands.filter(\.isEnabled)).count
        // Pinned stays first. Then what usually comes next, then the suggestions, then the menus.
        let pinnedIDs = Set(base.prefix(pinned).map(\.command.stableID))
        let byStable = Dictionary(base.map { ($0.command.stableID, $0) }, uniquingKeysWith: { first, _ in first })
        var predicted: [RankedCommand] = []
        if let predictor {
            let eligible = base.map(\.command).filter { $0.isEnabled && !pinnedIDs.contains($0.stableID) }
            for prediction in predictor(eligible).prefix(PredictionPolicy.maxRows) {
                guard let row = byStable[prediction.command], !pinnedIDs.contains(prediction.command) else { continue }
                predicted.append(row)
                predictedRowIDs.insert(row.id)
                if !prediction.reason.isEmpty { predictionReasons[row.id] = prediction.reason }
            }
        }
        let predictedIDs = Set(predicted.map(\.command.stableID))
        let suggested = ranker.suggested(commands, limit: Self.suggestionLimit + predicted.count)
            .filter { !predictedIDs.contains($0.command.stableID) }.prefix(Self.suggestionLimit)
        let suggestedIDs = Set(suggested.map(\.command.stableID))
        let head = Array(base.prefix(pinned))
        let rest = base.dropFirst(pinned).filter {
            !suggestedIDs.contains($0.command.stableID) && !predictedIDs.contains($0.command.stableID)
        }
        // Suggestions come from the same list, so take the ranked rows to keep ids and scores consistent.
        let lifted = suggested.compactMap { byStable[$0.command.stableID] }
        pinnedCount = head.count
        predictedRows = predicted.count
        suggestedCount = lifted.count
        cachedResults = head + predicted + lifted + rest
    }

    public var targetApp: TargetApp? { tracker.app }

    public var content: PaletteContent {
        if sendCenter?.isInDestinationList == true {
            return results.isEmpty ? .noMatches(query: query.trimmingCharacters(in: .whitespaces)) : .results
        }
        return switch menus.state {
        case .needsPermission: .needsPermission
        case .noApp: .noApp
        case .loading: .loading
        case .empty: .noCommands(appName: tracker.app?.name ?? "This app")
        case .failed(let message): .failed(message)
        case .loaded:
            results.isEmpty ? .noMatches(query: query.trimmingCharacters(in: .whitespaces)) : .results
        }
    }

    /// The highlighted result: the arrow-key choice if it is still listed, else the first enabled one.
    public var selected: RankedCommand? {
        let list = results
        if let selectedID, let chosen = list.first(where: { $0.id == selectedID }) { return chosen }
        return list.first(where: { $0.command.isEnabled }) ?? list.first
    }

    /// Called each time the palette opens: clears the query and refreshes the menus, since the app may have changed
    /// them while the palette was hidden.
    public func prepareForOpen() {
        query = ""
        runError = nil
        lastOutcome = nil
        pendingConfirmation = nil
        lastSend = nil
        lastSentCommand = nil
        sendCenter?.beginSession(for: tracker.app)
        selectedID = nil
        // Context from the last time the panel was open may be gone. Actions come back when the fresh snapshot lands,
        // so a stale selection can never be acted on.
        if !contextCommands.isEmpty {
            contextCommands = []
            contextRevision += 1
        }
        openHook?(tracker.app)
        menus.refresh()
    }

    public func moveSelection(by delta: Int) {
        let list = results
        guard !list.isEmpty else { return }
        let current = selected.flatMap { chosen in list.firstIndex { $0.id == chosen.id } } ?? 0
        let next = min(max(current + delta, 0), list.count - 1)
        selectedID = list[next].id
    }

    /// Selects a result by id, for the pointer. Unknown ids are ignored.
    public func select(id: String) {
        guard selectedID != id, results.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    public func selectFirst() { selectedID = results.first?.id }
    public func selectLast() { selectedID = results.last?.id }

    /// Runs the first Usually next row, whatever is highlighted. Returns true when the palette can close, false when
    /// there is no prediction or the command failed.
    @discardableResult
    public func runTopPrediction() async -> Bool {
        guard let command = topPrediction else { return false }
        return await run(command)
    }

    /// Runs the selected command. Returns true when the palette can close.
    @discardableResult
    public func runSelected() async -> Bool {
        guard let selected else { return false }
        return await run(selected.command)
    }

    @discardableResult
    public func run(_ command: Command) async -> Bool {
        runError = nil
        lastOutcome = nil
        lastSend = nil
        if case .contextAction = command.source { return await runContextAction(command, confirmed: false) }
        if case .sendTo = command.source { return await runSend(command) }
        let outcome: Result<Void, CommandRunError>
        if let runner {
            outcome = await runner(command)
        } else {
            outcome = await menus.run(command)
        }
        switch outcome {
        case .success:
            return true
        case .failure(let error):
            runError = error.message
            return false
        }
    }

    private func runContextAction(_ command: Command, confirmed: Bool) async -> Bool {
        guard let contextRunner else {
            runError = ActionError.notApplicable.message
            return false
        }
        if command.needsConfirmation, !confirmed {
            pendingConfirmation = command
            return false
        }
        pendingConfirmation = nil
        switch await contextRunner(command, tracker.app, confirmed) {
        case .success(let outcome):
            lastOutcome = outcome
            return true
        case .failure(.confirmationRequired):
            pendingConfirmation = command
            return false
        case .failure(let error):
            runError = error.message
            return false
        }
    }

    /// Whether the row is part of the send-to layer, which keeps the panel open until a send finishes.
    public func isSendRow(_ command: Command) -> Bool {
        if case .sendTo = command.source { return true }
        return false
    }

    /// Whether something waits for the confirming Return (a context action or a send).
    public var hasPendingConfirmation: Bool { pendingConfirmation != nil || sendCenter?.pending != nil }

    private func runSend(_ command: Command) async -> Bool {
        guard let center = sendCenter else {
            runError = ActionError.notApplicable.message
            return false
        }
        return handle(await center.perform(command), command: command)
    }

    private func handle(_ step: SendStep, command: Command) -> Bool {
        switch step {
        case .enteredLevel:
            queryBeforeSendLevel = query
            query = ""
            selectedID = nil
            return false
        case .needsConfirmation:
            return false
        case .sent(let outcome, let sent):
            lastSend = outcome
            lastSentCommand = sent
            return true
        case .failed(.cancelled):
            return false
        case .failed(let error):
            runError = error.message
            return false
        }
    }

    /// Runs the action or send that was waiting for confirmation. Returns true when the palette can close.
    @discardableResult
    public func confirmPending() async -> Bool {
        runError = nil
        if let center = sendCenter, let pending = center.pending {
            guard let step = await center.confirmPending() else { return false }
            return handle(step, command: pending.command)
        }
        guard let command = pendingConfirmation else { return false }
        return await runContextAction(command, confirmed: true)
    }

    public func cancelPending() {
        pendingConfirmation = nil
        sendCenter?.goBackFromPending()
    }

    /// Escape: cancels a confirmation, else leaves the destination list. Returns false when there was nothing to leave
    /// and the caller should close the panel.
    @discardableResult
    public func goBack() -> Bool {
        runError = nil
        if pendingConfirmation != nil {
            pendingConfirmation = nil
            return true
        }
        guard let center = sendCenter else { return false }
        let wasInList = center.isInDestinationList && center.pending == nil
        guard center.goBack() else { return false }
        if wasInList {
            query = queryBeforeSendLevel
            selectedID = nil
        }
        return true
    }

    public func setRunner(_ runner: @escaping @MainActor (Command) async -> Result<Void, CommandRunError>) {
        self.runner = runner
    }
}
