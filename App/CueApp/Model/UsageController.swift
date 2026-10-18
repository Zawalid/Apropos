import Cue
import Foundation
import Observation

/// Connects the usage store to the palette: records runs, keeps the ranking up to date after pins, hides and runs, keeps
/// the short recent-commands list for the menu bar, and hands out row symbols.
@MainActor
@Observable
final class UsageController {
    /// One command that ran lately. Titles only: never the query, the selection or anything about the document.
    struct Recent: Codable, Identifiable, Equatable {
        let stableID: String
        let title: String
        let appName: String
        let bundleID: String?
        let date: Date
        var id: String { stableID }
    }

    static let recentLimit = 6
    private static let recentsKey = "cueRecentCommands"

    let store: UsageStore
    private(set) var recents: [Recent]

    @ObservationIgnored private let palette: PaletteModel
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var resolver: SymbolResolver
    @ObservationIgnored private var cachedIDs: [String] = []
    @ObservationIgnored private var cachedSymbols: [String: String] = [:]

    init(store: UsageStore, palette: PaletteModel, defaults: UserDefaults = .standard) {
        self.store = store
        self.palette = palette
        self.defaults = defaults
        resolver = store.symbolResolver()
        if let data = defaults.data(forKey: Self.recentsKey),
            let stored = try? JSONDecoder().decode([Recent].self, from: data)
        {
            recents = stored
        } else {
            recents = []
        }
    }

    // MARK: Ranking

    func refreshRanker() {
        palette.setRanker(CommandRanker(signal: store.rankingSignal()))
    }

    func recordRun(_ command: Command, appName: String?) {
        guard UsageStore.isRecordable(command) else { return }
        store.recordRun(of: command)
        let entry = Recent(
            stableID: command.stableID.rawValue, title: command.displayTitle, appName: appName ?? "",
            bundleID: command.stableID.bundleID, date: Date())
        recents = Array(([entry] + recents.filter { $0.stableID != entry.stableID }).prefix(Self.recentLimit))
        saveRecents()
        refreshRanker()
    }

    func isPinned(_ command: Command) -> Bool { store.isPinned(command.stableID) }

    func setPinned(_ pinned: Bool, for command: Command) {
        store.setPinned(pinned, for: command.stableID)
        refreshRanker()
    }

    func hide(_ command: Command) {
        store.setHidden(true, for: command.stableID)
        refreshRanker()
    }

    func hiddenIDs(forBundleID bundleID: String) -> [CommandID] { store.hiddenIDs(forBundleID: bundleID) }

    func unhide(_ id: CommandID) {
        store.setHidden(false, for: id)
        refreshRanker()
    }

    func resetLearnedRanking() {
        store.resetLearnedRanking()
        refreshRanker()
    }

    func clearHistory() {
        recents = []
        saveRecents()
    }

    func flush() { store.flush() }

    // MARK: Symbols

    /// One symbol per command, keyed by `Command.id`. The resolver looks at neighbours so the list must be passed in
    /// display order; the answer is cached until the list changes.
    func symbols(for commands: [Command]) -> [String: String] {
        let ids = commands.map(\.id)
        if ids == cachedIDs { return cachedSymbols }
        let names = resolver.symbols(for: commands)
        var map: [String: String] = [:]
        for (command, name) in zip(commands, names) { map[command.id] = name }
        cachedIDs = ids
        cachedSymbols = map
        return map
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recents) { defaults.set(data, forKey: Self.recentsKey) }
    }
}
