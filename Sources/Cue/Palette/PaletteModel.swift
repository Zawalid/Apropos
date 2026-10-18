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
        let key = CacheKey(revision: menus.revision, query: query)
        if key != cacheKey {
            cachedResults = ranker.rank(menus.commands, query: query)
            cacheKey = key
        }
        return cachedResults
    }
    /// An explicit choice made with the arrow keys; nil means the first available result.
    public private(set) var selectedID: String?
    /// Shown inline after a command failed to run.
    public private(set) var runError: String?

    @ObservationIgnored private let menus: AppMenuModel
    @ObservationIgnored private let tracker: FrontmostAppTracker
    @ObservationIgnored private let ranker: CommandRanker
    @ObservationIgnored private var runner: (@MainActor (Command) async -> Result<Void, CommandRunError>)?
    @ObservationIgnored private var cachedResults: [RankedCommand] = []
    @ObservationIgnored private var cacheKey: CacheKey?

    private struct CacheKey: Equatable {
        let revision: Int
        let query: String
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
        selectedID = nil
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

    public func setRunner(_ runner: @escaping @MainActor (Command) async -> Result<Void, CommandRunError>) {
        self.runner = runner
    }
}
