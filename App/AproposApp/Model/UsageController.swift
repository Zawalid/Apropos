import Apropos
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
    private static let recentsKey = "aproposRecentCommands"

    let store: UsageStore
    /// What usually comes next, learned from the order commands ran in. The log has its own file next to the usage file.
    let prediction: PredictionEngine
    /// Kinds of context present in the app in front, set by the panel. Kinds only, never values.
    @ObservationIgnored var contextKinds: () -> [ContextKind] = { [] }
    private(set) var recents: [Recent]

    @ObservationIgnored private let palette: PaletteModel
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var resolver: SymbolResolver
    @ObservationIgnored private var cachedIDs: [String] = []
    @ObservationIgnored private var cachedSymbols: [String: String] = [:]

    init(store: UsageStore, palette: PaletteModel, defaults: UserDefaults = .standard) {
        self.store = store
        prediction = PredictionEngine(log: SequenceLog(url: SequenceLog.url(besides: store.url)))
        self.palette = palette
        self.defaults = defaults
        resolver = store.symbolResolver()
        prediction.setPrior(store.frecencyPrior())
        if let data = defaults.data(forKey: Self.recentsKey),
            let stored = try? JSONDecoder().decode([Recent].self, from: data)
        {
            recents = stored
        } else {
            recents = []
        }
        palette.setPredictor { [weak self] commands in self?.predictions(for: commands) ?? [] }
        palette.setPriors { [weak self] commands in
            guard let self else { return [:] }
            return self.prediction.confidences(
                app: self.palette.targetApp?.bundleID, candidates: commands.map(\.stableID),
                contextKinds: self.contextKinds())
        }
        prediction.onReady = { [weak palette] in palette?.refreshPredictions() }
        let prediction = prediction
        store.onLearnedRankingReset = { bundleID in
            if let bundleID { prediction.reset(forApp: bundleID) } else { prediction.reset() }
        }
    }

    // MARK: Ranking

    func refreshRanker() {
        palette.setRanker(CommandRanker(signal: store.rankingSignal()))
        prediction.setPrior(store.frecencyPrior())
    }

    // MARK: Usually next

    /// The rows for "Usually next" given the commands that can be offered now.
    private func predictions(for commands: [Command]) -> [Prediction] {
        var titles: [CommandID: String] = [:]
        for command in commands { titles[command.stableID] = command.displayTitle }
        return prediction.rows(app: palette.targetApp?.bundleID, candidates: titles, contextKinds: contextKinds())
    }

    /// Applies the person's prediction settings (on or off, reasons) and asks the palette for its rows again.
    func applyPredictionSettings(_ settings: SettingsStore) {
        prediction.configure(from: settings)
        palette.refreshPredictions()
    }

    /// Not now on a predicted command: it is offered less until the person runs it again.
    func dismissPrediction(_ command: Command) {
        prediction.dismiss(command.stableID, app: palette.targetApp?.bundleID, contextKinds: contextKinds())
        palette.refreshPredictions()
    }

    func recordRun(
        _ command: Command, appName: String?, appBundleID: String? = nil, contextKinds: [ContextKind] = [],
        query: String = ""
    ) {
        guard UsageStore.isRecordable(command) else { return }
        // Rows of Apropos itself open Settings; they are not commands to learn or predict.
        if case .app = command.source { return }
        store.recordRun(of: command, query: query)
        if SequenceLog.isRecordable(command) {
            prediction.recordRun(
                command.stableID, title: command.displayTitle, app: appBundleID, contextKinds: contextKinds)
        }
        // Send-to rows are not offered again from the menu bar: a destination's title means little out of context.
        if case .sendTo = command.source {
            refreshRanker()
            return
        }
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

    /// Called after the shortcut of a menu item changed, so the keys registered with the system follow.
    var onItemShortcutsChanged: (() -> Void)?

    /// Adds a menu item to the list on the Shortcuts page, where it takes an alias and a shortcut.
    func listForCustomizing(_ command: Command, appName: String?) {
        store.listForCustomizing(command.stableID, title: command.displayTitle, appName: appName ?? "")
    }

    func setItemAlias(_ alias: String, for id: CommandID) {
        store.setAliases(alias.isEmpty ? [] : [alias], for: id)
        refreshRanker()
    }

    /// Sets or clears the shortcut of a menu item. False when another item of the same app already has it.
    @discardableResult
    func setItemHotKey(_ combo: HotKeyCombo?, for id: CommandID) -> Bool {
        guard store.setHotKey(combo, for: id) else { return false }
        onItemShortcutsChanged?()
        return true
    }

    func removeItemCustomization(_ id: CommandID) {
        store.removeCustomization(id)
        refreshRanker()
        onItemShortcutsChanged?()
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

    func flush() {
        store.flush()
        prediction.log.flush()
    }

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
