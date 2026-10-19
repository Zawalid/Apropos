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
    /// The form that saves the sequence draft as a command.
    case sequenceSave
}

/// All the palette's behaviour: query, ranked results, selection and running a command. Views only render it.
@MainActor
@Observable
public final class PaletteModel {
    public var query = "" {
        didSet {
            guard query != oldValue else { return }
            selectedID = nil
            // Typing is a change of mind: a send waiting for its Return is dropped.
            sendCenter?.goBackFromPending()
            sequenceCenter?.dropConfirmation()
        }
    }
    /// The ranked commands for the current query. Recomputed only when the query or the command list changes.
    public var results: [RankedCommand] {
        let key = CacheKey(
            revision: menus.revision, query: query, rankerRevision: rankerRevision, contextRevision: contextRevision,
            predictionRevision: predictionRevision, targetPID: tracker.app?.pid, sendRevision: sendCenter?.revision ?? 0,
            sequenceRevision: sequenceCenter?.revision ?? 0, sourcesRevision: sourcesRevision, menuOffRevision: menuOffRevision
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
        let start = draftRows + pinnedCount
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
    /// Why the last send did not happen, in a sentence that names the destination and never the content. The payload
    /// and the destination list stay as they were, so the person can retry or pick another destination.
    public private(set) var sendFailure: String?
    /// The row that last sent successfully, for the caller to record in the usage store. Ids only.
    public private(set) var lastSentCommand: Command?

    @ObservationIgnored private let menus: AppMenuModel
    @ObservationIgnored private let tracker: FrontmostAppTracker
    @ObservationIgnored private var ranker: CommandRanker
    @ObservationIgnored private var rankerRevision = 0
    @ObservationIgnored private var sourcesRevision = 0
    @ObservationIgnored private var menuOffRevision = 0

    /// Apps whose menu items are not listed. Everything else still is.
    public var menuDisabledApps: Set<String> = [] {
        didSet { if menuDisabledApps != oldValue { menuOffRevision += 1 } }
    }

    /// True when the person turned menu items off for the app in front.
    public var menuItemsOff: Bool { tracker.app?.bundleID.map(menuDisabledApps.contains) ?? false }

    /// Which sources besides the front app's menu the list draws from. All on by default.
    public struct Sources: Sendable, Equatable {
        public var contextActions = true
        public var userCommands = true
        public var sendTo = true

        public init(contextActions: Bool = true, userCommands: Bool = true, sendTo: Bool = true) {
            self.contextActions = contextActions
            self.userCommands = userCommands
            self.sendTo = sendTo
        }
    }

    public var sources = Sources() {
        didSet { if sources != oldValue { sourcesRevision += 1 } }
    }
    @ObservationIgnored private var contextCommands: [Command] = []
    @ObservationIgnored private var contextPID: pid_t?
    @ObservationIgnored private var contextRevision = 0
    @ObservationIgnored private var openHook: ((TargetApp?) -> Void)?
    @ObservationIgnored private var sendCenter: SendToCenter?
    @ObservationIgnored private var queryBeforeSendLevel = ""
    @ObservationIgnored private var sequenceCenter: SequenceCenter?
    @ObservationIgnored private var queryBeforeSequenceLevel = ""
    @ObservationIgnored private var draftRows = 0
    @ObservationIgnored private var contextRunner:
        (@MainActor (Command, TargetApp?, Bool) async -> Result<ActionOutcome, ActionError>)?
    @ObservationIgnored private var pinnedCount = 0
    @ObservationIgnored private var suggestedCount = 0
    @ObservationIgnored private var predictedRows = 0
    @ObservationIgnored private var predictionReasons: [String: String] = [:]
    @ObservationIgnored private var predictedRowIDs: Set<String> = []
    @ObservationIgnored private var predictor: (@MainActor ([Command]) -> [Prediction])?
    /// How likely each command is to come next, used to rank typed searches. Nil means nothing is known.
    @ObservationIgnored private var priorsProvider: (@MainActor ([Command]) -> [CommandID: Double])?
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
        let sequenceRevision: Int
        let sourcesRevision: Int
        let menuOffRevision: Int
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
    public func setPriors(_ provider: (@MainActor ([Command]) -> [CommandID: Double])?) {
        priorsProvider = provider
    }

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

    /// Connects the sequence builder: its draft row heads the list and its level replaces the results while open.
    public func attachSequences(_ center: SequenceCenter) { sequenceCenter = center }

    /// The builder, for the views that draw the save form and the draft chip.
    public var sequences: SequenceCenter? { sequenceCenter }

    /// How many rows at the head of the list belong to the sequence draft (0 or 1), so a view can draw its header.
    public var draftRowCount: Int {
        _ = results
        return draftRows
    }

    /// The draft level that is open, for the breadcrumb chip. Nil at the top level.
    public var sequenceLevel: SequenceLevel? { sequenceCenter?.level }

    /// The steps in the draft, for the chip in the search field. Zero when there is no draft.
    public var draftStepCount: Int { sequenceCenter?.steps.count ?? 0 }

    /// A question waiting for its answer in the search field.
    public var sequenceAsking: SequenceAsking? {
        if case .asking(let asking)? = sequenceCenter?.phase { asking } else { nil }
    }

    /// The combined confirmation of a sequence run, waiting for the confirming Return.
    public var sequencePending: SequencePending? {
        if case .confirming(let pending)? = sequenceCenter?.phase { pending } else { nil }
    }

    /// Why the last sequence step did not happen (a row that could not be added, a run that stopped, a save that failed).
    public var sequenceFailure: String? { sequenceCenter?.failure }

    /// "Saved ... under Your commands", until the next thing the person does.
    public var sequenceNotice: String? { sequenceCenter?.notice }

    /// The step highlighted in the draft level, or nil when another row is.
    public var selectedStepID: String? {
        guard sequenceCenter?.level == .steps, case .sequence(.step(let id))? = selected?.command.source else {
            return nil
        }
        return id
    }

    /// Adds a row to the sequence draft. Refused rows say why in `sequenceFailure`.
    @discardableResult
    public func addToSequence(_ command: Command) -> SequenceAddResult {
        guard let sequenceCenter else { return .refused("Sequences are not available.") }
        return sequenceCenter.add(command)
    }

    /// Deletes the highlighted step of the draft.
    public func deleteSelectedStep() {
        guard let id = selectedStepID else { return }
        let neighbour = results.firstIndex { $0.id == selected?.id }
        sequenceCenter?.delete(stepID: id)
        selectedID = nil
        // The last step gone: there is no draft to show, so go back to the list the person came from, like Escape.
        guard sequenceCenter?.isInLevel == true else {
            query = queryBeforeSequenceLevel
            return
        }
        if let neighbour, !results.isEmpty { selectedID = results[min(neighbour, results.count - 1)].id }
    }

    /// Moves the highlighted step up (-1) or down (+1) and keeps it highlighted.
    public func moveSelectedStep(by delta: Int) {
        guard let id = selectedStepID else { return }
        sequenceCenter?.move(stepID: id, by: delta)
        selectedID = SequenceTarget.step(id).commandID.rawValue
    }

    /// The destination list that is open, for the breadcrumb chip. Nil at the top level.
    public var sendLevel: SendLevel? { sendCenter?.level }

    /// A send waiting for the confirming Return: show its one-line preview.
    public var sendPending: SendPending? { sendCenter?.pending }

    /// The send-to rows listed now, only while the app they were built for is the target.
    private var activeSendCommands: [Command] {
        guard sources.sendTo, let center = sendCenter, let pid = tracker.app?.pid, pid == center.pid else { return [] }
        return center.rootCommands
    }

    /// Context actions with, at the head of each group, that group's send rows: a group has a dozen actions and the send
    /// rows would otherwise sit at the bottom, out of sight.
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
            if let first = result.firstIndex(where: { ($0.path.first ?? "") == group }) {
                result.insert(contentsOf: rows, at: first)
            } else {
                result.append(contentsOf: rows)
            }
        }
        return result
    }

    /// The context actions currently listed.
    private var activeContextCommands: [Command] {
        guard let pid = tracker.app?.pid, pid == contextPID else { return [] }
        guard !(sources.contextActions && sources.userCommands) else { return contextCommands }
        return contextCommands.filter { command in
            guard case .contextAction(let id) = command.source else { return true }
            return id.rawValue.hasPrefix("user:") ? sources.userCommands : sources.contextActions
        }
    }

    private func computeResults() {
        pinnedCount = 0
        suggestedCount = 0
        predictedRows = 0
        predictionReasons = [:]
        predictedRowIDs = []
        draftRows = 0
        if let center = sequenceCenter, center.isInLevel {
            cachedResults = center.level == .steps ? ranker.rank(center.levelCommands, query: query) : []
            return
        }
        if let center = sendCenter, center.isInDestinationList {
            cachedResults = ranker.rank(center.levelCommands, query: query)
            return
        }
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        // The draft row heads the list. While searching it takes part like any other row, so typing "draft" finds it.
        let draft = sequenceCenter?.rootCommands ?? []
        let commands =
            (searching ? draft : []) + listed(context: activeContextCommands, send: activeSendCommands) + (menuItemsOff ? [] : menus.commands)
        let base = ranker.rank(
            commands, query: query, priors: searching ? (priorsProvider?(commands.filter(\.isEnabled)) ?? [:]) : [:])
        guard !searching else {
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
        let leading = draft.map { RankedCommand(command: $0, score: 0, titlePositions: []) }
        draftRows = leading.count
        cachedResults = leading + head + predicted + lifted + rest
    }

    public var targetApp: TargetApp? { tracker.app }

    public var content: PaletteContent {
        if sequenceCenter?.level == .save { return .sequenceSave }
        if sequenceCenter?.isInLevel == true {
            return results.isEmpty ? .noMatches(query: query.trimmingCharacters(in: .whitespaces)) : .results
        }
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
    /// - Parameter restoringLevel: the panel was closed a moment ago. The draft level stays open, so going to the draft,
    ///   clicking away and coming back lands in the draft again.
    public func prepareForOpen(restoringLevel: Bool = false) {
        query = ""
        runError = nil
        lastOutcome = nil
        pendingConfirmation = nil
        lastSend = nil
        lastSentCommand = nil
        sendFailure = nil
        sendCenter?.beginSession(for: tracker.app)
        sequenceCenter?.beginSession(for: tracker.app, keepingLevel: restoringLevel)
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
        if sequenceAsking != nil { return await submitSequenceAnswer() }
        if sequencePending != nil { return await confirmPending() }
        guard let selected else { return false }
        return await run(selected.command)
    }

    @discardableResult
    public func run(_ command: Command) async -> Bool {
        runError = nil
        lastOutcome = nil
        lastSend = nil
        sendFailure = nil
        if case .contextAction = command.source { return await runContextAction(command, confirmed: false) }
        if case .sendTo = command.source { return await runSend(command) }
        if case .sequence = command.source { return await runSequence(command) }
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

    /// Whether the row belongs to the sequence draft, which keeps the panel open until a run finishes.
    public func isSequenceRow(_ command: Command) -> Bool {
        if case .sequence = command.source { return true }
        return false
    }

    /// Whether something waits for the confirming Return (a context action, a send or a sequence run).
    public var hasPendingConfirmation: Bool {
        pendingConfirmation != nil || sendCenter?.pending != nil || sequencePending != nil
    }

    private func runSequence(_ command: Command) async -> Bool {
        guard let center = sequenceCenter else {
            runError = ActionError.notApplicable.message
            return false
        }
        let wasInLevel = center.isInLevel
        return handle(await center.perform(command), wasInLevel: wasInLevel)
    }

    private func handle(_ result: SequenceDraftResult, wasInLevel: Bool = true) -> Bool {
        switch result {
        case .enteredLevel:
            if !wasInLevel { queryBeforeSequenceLevel = query }
            query = ""
            selectedID = nil
            return false
        case .discarded, .saved:
            query = queryBeforeSequenceLevel
            selectedID = nil
            return false
        case .needsInput:
            query = ""
            return false
        case .needsConfirmation, .nothing, .failed:
            return false
        case .finished:
            return true
        }
    }

    /// Return while a question is asked: the search field holds the answer.
    public func submitSequenceAnswer() async -> Bool {
        guard let center = sequenceCenter, sequenceAsking != nil else { return false }
        let answer = query
        query = ""
        return handle(await center.submitAnswer(answer))
    }

    /// Saves the draft with what the form holds. True when it is saved.
    @discardableResult
    public func saveSequence() -> Bool {
        guard let center = sequenceCenter, center.save() else { return false }
        query = queryBeforeSequenceLevel
        selectedID = nil
        return true
    }

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
            sendFailure = error.message
            return false
        }
    }

    /// Runs the action or send that was waiting for confirmation. Returns true when the palette can close.
    @discardableResult
    public func confirmPending() async -> Bool {
        runError = nil
        sendFailure = nil
        if let center = sequenceCenter, sequencePending != nil { return handle(await center.confirmPending()) }
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
        sequenceCenter?.dropConfirmation()
    }

    /// Escape: cancels a confirmation, else leaves the destination list. Returns false when there was nothing to leave
    /// and the caller should close the panel.
    @discardableResult
    public func goBack() -> Bool {
        runError = nil
        sendFailure = nil
        if pendingConfirmation != nil {
            pendingConfirmation = nil
            return true
        }
        if let sequences = sequenceCenter, sequences.isInLevel || sequences.phase != nil {
            let leaving = sequences.level == .steps && sequences.phase == nil
            guard sequences.goBack() else { return false }
            if leaving {
                query = queryBeforeSequenceLevel
                selectedID = nil
            }
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
