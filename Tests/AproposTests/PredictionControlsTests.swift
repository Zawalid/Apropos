import Foundation
import Testing

@testable import Apropos

@MainActor
struct PredictionControlsTests {
    private let now = Date(timeIntervalSince1970: 1_800_262_800)

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "apropos-ctl-\(UUID().uuidString)", isDirectory: true)
    }

    private func id(_ app: String, _ title: String) -> CommandID {
        CommandID.base(bundleID: app, path: ["Menu"], title: title)
    }

    // MARK: Settings

    @Test func predictionIsOnByDefaultAndReasonsToo() {
        let store = SettingsStore(url: directory().appendingPathComponent("settings.json"), writeDelay: .zero)
        #expect(store.bool(.predictNextCommand))
        #expect(store.bool(.showPredictionReasons))
        #expect(SettingsRegistry.definition(for: .predictNextCommand)?.page == .prediction)
        #expect(!SettingsRegistry.search("usually next").isEmpty)
        #expect(SettingsRegistry.search("reset").contains { $0.id == .predictNextCommand })
    }

    @Test func engineFollowsTheSettings() {
        let store = SettingsStore(url: directory().appendingPathComponent("settings.json"), writeDelay: .zero)
        let log = SequenceLog(url: directory().appendingPathComponent("sequence.json"), writeDelay: .zero, now: now)
        let engine = PredictionEngine(log: log, buildInBackground: false)
        engine.configure(from: store)
        #expect(engine.isEnabled && engine.showsReasons)
        store.set(.bool(false), for: .predictNextCommand)
        store.set(.bool(false), for: .showPredictionReasons)
        engine.configure(from: store)
        #expect(!engine.isEnabled && !engine.showsReasons)
        #expect(engine.recordRun(id("app.a", "Save"), app: "app.a", at: now) == nil)
        #expect(log.events.isEmpty)
    }

    // MARK: Reset

    @Test func resettingLearnedRankingClearsTheSequenceLogToo() {
        let folder = directory()
        let usage = UsageStore(url: folder.appendingPathComponent("usage.json"), writeDelay: .zero, now: now)
        let log = SequenceLog(url: SequenceLog.url(besides: usage.url), writeDelay: .zero, now: now)
        let engine = PredictionEngine(log: log, buildInBackground: false)
        usage.onLearnedRankingReset = { bundle in
            if let bundle { engine.reset(forApp: bundle) } else { engine.reset() }
        }
        usage.recordRun(id: id("app.a", "Save"), at: now)
        engine.recordRun(id("app.a", "Save"), app: "app.a", at: now)
        engine.recordRun(id("app.a", "Close"), app: "app.a", at: now + 5)
        #expect(log.events.count == 2)
        usage.resetLearnedRanking()
        #expect(log.events.isEmpty)
        #expect(SequenceLog(url: log.url, writeDelay: .zero, now: now).events.isEmpty)
        #expect(usage.runCount(id("app.a", "Save")) == 0)
    }

    @Test func resetForOneAppKeepsTheOthersAndDropsEveryMentionOfIt() throws {
        let log = SequenceLog(url: directory().appendingPathComponent("sequence.json"), writeDelay: .zero, now: now)
        let engine = PredictionEngine(log: log, buildInBackground: false)
        engine.recordRun(id("app.a", "Build"), app: "app.a", at: now)
        engine.recordRun(id("app.b", "Commit"), app: "app.b", at: now + 10)
        engine.recordRun(id("app.b", "Push"), app: "app.b", at: now + 20)
        engine.reset(forApp: "app.a")
        #expect(log.events.map(\.command) == [id("app.b", "Commit"), id("app.b", "Push")])
        #expect(log.events[0].previous == nil)
        #expect(log.events[1].previous == id("app.b", "Commit"))
        let file = try String(contentsOf: log.url, encoding: .utf8)
        #expect(!file.contains("app.a"))
    }

    @Test func clearingNeverTouchesPinsAndHiddenCommands() {
        let folder = directory()
        let usage = UsageStore(url: folder.appendingPathComponent("usage.json"), writeDelay: .zero, now: now)
        usage.setPinned(true, for: id("app.a", "Save"), at: now)
        usage.setHidden(true, for: id("app.a", "Close"))
        usage.onLearnedRankingReset = { _ in }
        usage.resetLearnedRanking()
        #expect(usage.isPinned(id("app.a", "Save")))
        #expect(usage.isHidden(id("app.a", "Close")))
    }

    // MARK: Export

    @Test func theSettingsExportDoesNotContainTheLog() throws {
        let folder = directory()
        let store = SettingsStore(url: folder.appendingPathComponent("settings.json"), writeDelay: .zero)
        let log = SequenceLog(url: folder.appendingPathComponent("sequence.json"), writeDelay: .zero, now: now)
        log.recordRun(id("app.a", "Secret Command"), app: "app.a", at: now)
        store.set(.string("dark"), for: .theme)
        let destination = folder.appendingPathComponent("export.json")
        try store.exportSettings(to: destination)
        let exported = try String(contentsOf: destination, encoding: .utf8)
        #expect(!exported.contains("Secret"))
        #expect(!exported.contains("secret command"))
        #expect(!exported.contains("events"))
        #expect(!exported.contains("app.a"))
    }

    @Test func theUsageFileNeverHoldsTheSequence() throws {
        let folder = directory()
        let usage = UsageStore(url: folder.appendingPathComponent("usage.json"), writeDelay: .zero, now: now)
        let log = SequenceLog(url: SequenceLog.url(besides: usage.url), writeDelay: .zero, now: now)
        log.recordRun(id("app.a", "Run Tests"), app: "app.a", at: now)
        log.recordRun(id("app.a", "Commit"), app: "app.a", at: now + 5)
        usage.recordRun(id: id("app.a", "Commit"), at: now)
        let text = try String(contentsOf: usage.url, encoding: .utf8)
        #expect(!text.contains("\"p\""))
        #expect(!text.contains("events"))
        #expect(usage.url != log.url)
    }

    @Test func theCommandsExportIsBuiltFromCommandsAlone() throws {
        // `CommandExchange.export` takes user commands and nothing else, so no run history can reach the file.
        let text = String(decoding: try CommandExchange.export([], name: "Mine"), as: UTF8.self)
        #expect(!text.contains("events"))
        #expect(!text.contains("sequence"))
        #expect(
            UserCommandStore.defaultDirectory.deletingLastPathComponent().path
                == SequenceLog.url(besides: UsageStore.defaultURL).deletingLastPathComponent().path)
        #expect(UserCommandStore.defaultDirectory.lastPathComponent != "sequence.json")
    }
}
