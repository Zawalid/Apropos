import Foundation
import Testing

@testable import Apropos

@MainActor
struct PredictionInsightsTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "apropos-ins-\(UUID().uuidString)", isDirectory: true)
    }

    private func id(_ title: String, app: String = "app.a") -> CommandID {
        CommandID.base(bundleID: app, path: ["Menu"], title: title)
    }

    private func engine(now: Date) -> PredictionEngine {
        let log = SequenceLog(url: directory().appendingPathComponent("sequence.json"), writeDelay: .zero, now: now)
        return PredictionEngine(log: log, buildInBackground: false)
    }

    /// Runs Test then Commit `times` times, a minute apart, one day apart.
    private func seed(_ engine: PredictionEngine, times: Int, app: String = "app.a") {
        for day in 0..<times {
            let at = start.addingTimeInterval(Double(day) * 86_400)
            engine.recordRun(id("Test", app: app), title: "Test", app: app, at: at)
            engine.recordRun(id("Commit", app: app), title: "Commit", app: app, at: at.addingTimeInterval(60))
        }
    }

    @Test func summaryCountsRunsDaysAndApps() {
        let engine = engine(now: start)
        seed(engine, times: 3)
        let summary = engine.summary()
        #expect(summary.runs == 6 && summary.commands == 2 && summary.apps == 1 && summary.daysOfUse == 3)
        #expect(summary.isWarmingUp)
    }

    @Test func habitsFindTheCommonFollowUp() {
        let engine = engine(now: start)
        seed(engine, times: 4)
        let habits = engine.habits(minimum: 3)
        #expect(habits.contains { $0.previous == id("Test") && $0.command == id("Commit") && $0.count == 4 })
        let habit = try? #require(habits.first { $0.command == id("Commit") })
        if let habit {
            engine.forget(habit)
            #expect(!engine.habits(minimum: 1).contains { $0.command == id("Commit") && $0.previous == id("Test") })
        }
    }

    @Test func accuracyCountsShownSuggestions() {
        let engine = engine(now: start)
        engine.recordRun(id("A"), app: "app.a", at: start)
        let first = start.addingTimeInterval(10)
        engine.recordRun(id("B"), app: "app.a", at: first)
        #expect(engine.accuracy(now: first).shown == 0)
        #expect(!engine.accuracy(now: first).isEnough)
    }

    @Test func excludedAppsLearnAndPredictNothing() {
        let engine = engine(now: start)
        engine.excludedApps = ["app.a"]
        #expect(engine.recordRun(id("Test"), app: "app.a", at: start) == nil)
        engine.excludedApps = []
        #expect(engine.recordRun(id("Test"), app: "app.a", at: start) != nil)
    }

    @Test func pausingStopsRecordingButNotForever() {
        let engine = engine(now: start)
        engine.pauseLearning(for: 3600)
        #expect(engine.isLearningPaused)
        #expect(engine.recordRun(id("Test"), app: "app.a", at: start) == nil)
        engine.resumeLearning()
        #expect(engine.recordRun(id("Test"), app: "app.a", at: start) != nil)
    }

    @Test func pruneDropsOldRuns() {
        let engine = engine(now: start)
        seed(engine, times: 3)
        engine.log.prune(keepingDays: 1, now: start.addingTimeInterval(10 * 86_400))
        #expect(engine.log.events.isEmpty)
        seed(engine, times: 3)
        engine.log.prune(keepingDays: 0, now: start.addingTimeInterval(400 * 86_400))
        #expect(!engine.log.events.isEmpty)
    }

    @Test func sensitivityOrdersTheThresholds() {
        #expect(PredictionSensitivity.cautious.threshold > PredictionSensitivity.balanced.threshold)
        #expect(PredictionSensitivity.balanced.threshold > PredictionSensitivity.eager.threshold)
    }

    @Test func settingsReachTheEngine() {
        let store = SettingsStore(url: directory().appendingPathComponent("s.json"), writeDelay: .zero)
        let engine = engine(now: start)
        store.set(.string("eager"), for: .predictionSensitivity)
        store.set(.string("1"), for: .predictionMaxRows)
        store.set(.stringList(["app.x"]), for: .predictionExcludedApps)
        engine.configure(from: store)
        #expect(engine.sensitivity == .eager && engine.maxRows == 1 && engine.excludedApps == ["app.x"])
    }
}
