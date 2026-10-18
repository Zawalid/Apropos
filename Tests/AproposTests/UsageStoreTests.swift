import Foundation
import Testing

@testable import Apropos

@MainActor
struct UsageStoreTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-usage-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("usage.json")
    }

    private func store(_ url: URL) -> UsageStore { UsageStore(url: url, writeDelay: .zero, now: now) }

    private func command(_ title: String, path: [String] = ["File"], enabled: Bool = true, bundle: String = "app.test")
        -> Command
    {
        Command(id: title, title: title, path: path, isEnabled: enabled, source: .menuItem(bundleID: bundle))
    }

    @Test func frecencyRewardsRecencyAndFrequency() {
        let recentOnce = Frecency.score(runs: 1, recent: [now - day], now: now)
        let oldOnce = Frecency.score(runs: 1, recent: [now - 200 * day], now: now)
        let recentOften = Frecency.score(runs: 10, recent: Array(repeating: now - day, count: 10), now: now)
        #expect(recentOnce > oldOnce)
        #expect(recentOften > recentOnce)
        #expect(Frecency.score(runs: 0, recent: [], now: now) == 0)
        #expect(Frecency.boost(forScore: 1_000_000) == 60)
        #expect(Frecency.boost(forScore: 0) == 0)
    }

    @Test func runsAreCountedAndOnlyRecentTimesKept() {
        let store = store(tempURL())
        let id = CommandID(rawValue: "app.test|file>save")
        for offset in 0..<25 { store.recordRun(id: id, at: now - Double(25 - offset) * day) }
        #expect(store.runCount(id) == 25)
        #expect(store.lastRun(id) == now - day)
        #expect(store.frecency(id, now: now) > 0)
    }

    @Test func usageSurvivesARelaunch() {
        let url = tempURL()
        let id = CommandID(rawValue: "app.test|file>save")
        let first = store(url)
        first.recordRun(id: id, at: now - day)
        first.setPinned(true, for: id, at: now)
        first.setAliases(["  SV ", "sv", ""], for: id)
        let second = store(url)
        #expect(second.runCount(id) == 1)
        #expect(second.isPinned(id))
        #expect(second.aliases(id) == ["sv"])
    }

    @Test func fileHoldsNoQueryTextAndIsReadable() throws {
        let url = tempURL()
        let store = store(url)
        store.recordRun(of: command("Save"), at: now)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("app.test|file>save"))
        #expect(text.contains("\"runs\" : 1"))
        #expect(!text.contains("query"))
    }

    @Test func recentItemsAreNeverRecorded() {
        let store = store(tempURL())
        let recent = command("Secret Plans.pdf", path: ["File", "Open Recent"])
        let french = command("Contrat.pdf", path: ["Fichier", "Ouvrir récent"])
        store.recordRun(of: recent, at: now)
        store.recordRun(of: french, at: now)
        #expect(store.runCount(recent.stableID) == 0)
        #expect(store.runCount(french.stableID) == 0)
    }

    @Test func alternateRunsAreRecordedUnderTheAlternate() {
        let store = store(tempURL())
        let bar = [
            MenuItemSnapshot(title: "App"),
            MenuItemSnapshot(
                title: "File",
                children: [
                    MenuItemSnapshot(title: "Close", cmdChar: "w"),
                    MenuItemSnapshot(title: "Close All", cmdChar: "w", cmdModifiers: 2),
                ]),
        ]
        let close = MenuCommandMapper.commands(from: bar, bundleID: "app.test")[0]
        let alternate = close.alternates[0]
        store.recordRun(of: close, alternate: alternate, at: now)
        #expect(store.runCount(alternate.stableID) == 1)
        #expect(store.runCount(close.stableID) == 0)
    }

    @Test func resetKeepsPinsHidesAndAliases() {
        let url = tempURL()
        let store = store(url)
        let id = CommandID(rawValue: "app.test|file>save")
        store.recordRun(id: id, at: now)
        store.setPinned(true, for: id)
        store.setHidden(true, for: id)
        store.setAliases(["s"], for: id)
        store.resetLearnedRanking()
        #expect(store.runCount(id) == 0)
        #expect(store.isPinned(id) && store.isHidden(id) && store.aliases(id) == ["s"])
        let again = self.store(url)
        #expect(again.runCount(id) == 0 && again.isPinned(id))
    }

    @Test func perAppResetOnlyTouchesThatApp() {
        let store = store(tempURL())
        let one = CommandID(rawValue: "app.one|file>save")
        let two = CommandID(rawValue: "app.two|file>save")
        store.recordRun(id: one, at: now)
        store.recordRun(id: two, at: now)
        store.resetLearnedRanking(forBundleID: "app.one")
        #expect(store.runCount(one) == 0 && store.runCount(two) == 1)
    }

    @Test func clearingEveryPreferenceRemovesTheEntry() throws {
        let url = tempURL()
        let store = store(url)
        let id = CommandID(rawValue: "app.test|file>save")
        store.setHidden(true, for: id)
        store.setHidden(false, for: id)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("app.test"))
    }

    @Test func pinsAreListedInPinOrderPerApp() {
        let store = store(tempURL())
        let a = CommandID(rawValue: "app.test|a")
        let b = CommandID(rawValue: "app.test|b")
        let other = CommandID(rawValue: "other|c")
        store.setPinned(true, for: b, at: now)
        store.setPinned(true, for: a, at: now + 10)
        store.setPinned(true, for: other, at: now)
        #expect(store.pinnedIDs(forBundleID: "app.test") == [b, a])
        #expect(store.hiddenIDs(forBundleID: "app.test").isEmpty)
    }

    @Test func staleRecordsArePrunedAtLaunch() {
        let url = tempURL()
        let first = store(url)
        let old = CommandID(rawValue: "app.test|old")
        first.recordRun(id: old, at: now - 400 * day)
        first.recordRun(id: CommandID(rawValue: "app.test|fresh"), at: now - day)
        let second = store(url)
        #expect(second.runCount(old) == 0)
        #expect(second.runCount(CommandID(rawValue: "app.test|fresh")) == 1)
    }

    @Test func corruptFileIsCopiedAsideAndStoreStartsEmpty() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: url)
        let store = store(url)
        #expect(store.recoveredFromCorruption)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(siblings.contains { $0.contains(".broken-") })
    }

    // MARK: Ranking

    private func ranked(_ store: UsageStore, _ commands: [Command]) -> CommandRanker {
        CommandRanker(signal: store.rankingSignal(now: now))
    }

    @Test func usageBreaksTiesBetweenEqualMatches() {
        let store = store(tempURL())
        let commands = [command("Open File"), command("Open Folder")]
        for _ in 0..<8 { store.recordRun(of: commands[1], at: now - day) }
        let results = ranked(store, commands).rank(commands, query: "open f")
        #expect(results.first?.command.title == "Open Folder")
    }

    @Test func hiddenCommandsAreOmittedUnlessAsked() {
        let store = store(tempURL())
        let commands = [command("Copy"), command("Cut")]
        store.setHidden(true, for: commands[0].stableID)
        let ranker = ranked(store, commands)
        #expect(ranker.rank(commands, query: "").map(\.command.title) == ["Cut"])
        #expect(ranker.rank(commands, query: "copy").isEmpty)
        #expect(ranker.rank(commands, query: "copy", includeHidden: true).count == 1)
    }

    @Test func pinnedCommandsLeadTheEmptyQuery() {
        let store = store(tempURL())
        let commands = [command("Copy"), command("Cut"), command("Paste")]
        store.setPinned(true, for: commands[2].stableID, at: now)
        store.setPinned(true, for: commands[1].stableID, at: now + 5)
        let ranker = ranked(store, commands)
        #expect(ranker.rank(commands, query: "").map(\.command.title) == ["Paste", "Cut", "Copy"])
        #expect(ranker.pinned(commands).map(\.title) == ["Paste", "Cut"])
    }

    @Test func aliasFindsACommandItsTitleDoesNot() {
        let store = store(tempURL())
        let commands = [command("Show Path Bar"), command("Show Preview")]
        store.setAliases(["pb"], for: commands[0].stableID)
        let results = ranked(store, commands).rank(commands, query: "pb")
        #expect(results.first?.command.title == "Show Path Bar")
        #expect(results.first?.titlePositions.isEmpty == true)
    }

    @Test func suggestionsAreHabitsNotOneOffs() {
        let store = store(tempURL())
        let commands = [command("Save"), command("Close"), command("Print"), command("Export", enabled: false)]
        for _ in 0..<6 { store.recordRun(of: commands[0], at: now - day) }
        for _ in 0..<3 { store.recordRun(of: commands[1], at: now - day) }
        store.recordRun(of: commands[2], at: now - 300 * day)
        for _ in 0..<6 { store.recordRun(of: commands[3], at: now - day) }
        let ranker = ranked(store, commands)
        #expect(ranker.suggested(commands).map(\.command.title) == ["Save", "Close"])
        store.setPinned(true, for: commands[0].stableID)
        #expect(self.ranked(store, commands).suggested(commands).map(\.command.title) == ["Close"])
        #expect(CommandRanker().suggested(commands).isEmpty)
    }
}
