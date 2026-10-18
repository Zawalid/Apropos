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
            targetPID: tracker.app?.pid)
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

    @ObservationIgnored private let menus: AppMenuModel
    @ObservationIgnored private let tracker: FrontmostAppTracker
    @ObservationIgnored private var ranker: CommandRanker
    @ObservationIgnored private var rankerRevision = 0
    @ObservationIgnored private var contextCommands: [Command] = []
    @ObservationIgnored private var contextPID: pid_t?
    @ObservationIgnored private var contextRevision = 0
    @ObservationIgnored private var contextRunner:
        (@MainActor (Command, TargetApp?, Bool) async -> Result<ActionOutcome, ActionError>)?
    @ObservationIgnored private var pinnedCount = 0
    @ObservationIgnored private var suggestedCount = 0
    @ObservationIgnored private var runner: (@MainActor (Command) async -> Result<Void, CommandRunError>)?
    @ObservationIgnored private var cachedResults: [RankedCommand] = []
    @ObservationIgnored private var cacheKey: CacheKey?

    private struct CacheKey: Equatable {
        let revision: Int
        let query: String
        let rankerRevision: Int
        let contextRevision: Int
        let targetPID: pid_t?
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

    /// Context actions for the app with `pid`, built from its latest context snapshot. They are listed only while that
    /// app is the target, so another app's selection never offers actions here. They come before the menu commands.
    public func setContextCommands(_ commands: [Command], forPID pid: pid_t?) {
        contextCommands = commands
        contextPID = pid
        contextRevision += 1
    }

    public func setContextRunner(
        _ runner: @escaping @MainActor (Command, TargetApp?, Bool) async -> Result<ActionOutcome, ActionError>
    ) {
        contextRunner = runner
    }

    /// The context actions currently listed.
    private var activeContextCommands: [Command] {
        guard let pid = tracker.app?.pid, pid == contextPID else { return [] }
        return contextCommands
    }

    private func computeResults() {
        let commands = activeContextCommands + menus.commands
        let base = ranker.rank(commands, query: query)
        pinnedCount = 0
        suggestedCount = 0
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else {
            cachedResults = base
            return
        }
        let pinned = ranker.pinned(commands.filter(\.isEnabled)).count
        let suggested = ranker.suggested(commands, limit: Self.suggestionLimit)
        let suggestedIDs = Set(suggested.map(\.command.stableID))
        let head = Array(base.prefix(pinned))
        let rest = base.dropFirst(pinned).filter { !suggestedIDs.contains($0.command.stableID) }
        // Suggestions come from the same list, so take the ranked rows to keep ids and scores consistent.
        let byStable = Dictionary(base.map { ($0.command.stableID, $0) }, uniquingKeysWith: { first, _ in first })
        let lifted = suggested.compactMap { byStable[$0.command.stableID] }
        pinnedCount = head.count
        suggestedCount = lifted.count
        cachedResults = head + lifted + rest
    }

    public var targetApp: TargetApp? { tracker.app }

    public var content: PaletteContent {
        switch menus.state {
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
        selectedID = nil
        // Context from the last time the panel was open may be gone. Actions come back when the fresh snapshot lands,
        // so a stale selection can never be acted on.
        if !contextCommands.isEmpty {
            contextCommands = []
            contextRevision += 1
        }
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
        if case .contextAction = command.source { return await runContextAction(command, confirmed: false) }
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

    /// Runs the action that was waiting for confirmation. Returns true when the palette can close.
    @discardableResult
    public func confirmPending() async -> Bool {
        guard let command = pendingConfirmation else { return false }
        return await runContextAction(command, confirmed: true)
    }

    public func cancelPending() { pendingConfirmation = nil }

    public func setRunner(_ runner: @escaping @MainActor (Command) async -> Result<Void, CommandRunError>) {
        self.runner = runner
    }
}
