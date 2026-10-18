import Foundation
import Testing

@testable import Apropos

@MainActor
@Suite("Usually next")
struct PalettePredictionTests {
    private let bundle = "app.test"

    private func command(_ title: String, path: [String] = ["File"], enabled: Bool = true) -> Command {
        Command(id: title, title: title, path: path, isEnabled: enabled, source: .menuItem(bundleID: bundle))
    }

    private func makeModel(_ commands: [Command], run: (@MainActor (Command) async -> Result<Void, CommandRunError>)? = nil)
        -> PaletteModel
    {
        let tracker = FrontmostAppTracker(ownBundleID: "test")
        let menus = AppMenuModel(tracker: tracker, permission: AccessibilityPermission(probe: { true }))
        menus.seed(commands)
        return PaletteModel(menus: menus, tracker: tracker, runner: run)
    }

    private func prediction(_ command: Command, _ confidence: Double = 0.9) -> Prediction {
        Prediction(
            command: command.stableID, confidence: confidence, reason: "After Alpha you chose \(command.title) 9 of 12 times",
            basis: .afterCommand)
    }

    private let list = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"].map {
        Command(id: $0, title: $0, path: ["File"], source: .menuItem(bundleID: "app.test"))
    }

    @Test func predictedRowsSitAfterPinnedAndBeforeSuggestions() {
        let model = makeModel(list)
        let store = UsageStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("apropos-\(UUID().uuidString)/usage.json"),
            writeDelay: .zero)
        store.setPinned(true, for: list[3].stableID)
        for _ in 0..<5 { store.recordRun(id: list[2].stableID) }
        model.setRanker(CommandRanker(signal: store.rankingSignal()))
        model.setPredictor { _ in [self.prediction(self.list[4])] }
        #expect(model.results.map(\.command.title) == ["Delta", "Epsilon", "Gamma", "Alpha", "Beta"])
        #expect(model.leadingGroups.pinned == 1)
        #expect(model.predictedCount == 1)
        #expect(model.leadingGroups.suggested == 1)
        #expect(model.topPrediction?.title == "Epsilon")
        #expect(model.predictionReason(forRowID: "Epsilon") == "After Alpha you chose Epsilon 9 of 12 times")
        #expect(model.predictionReason(forRowID: "Gamma") == nil)
        #expect(model.isPredicted(rowID: "Epsilon"))
        #expect(!model.isPredicted(rowID: "Gamma"))
    }

    @Test func atMostTwoRowsAndNeverWhileSearching() {
        let model = makeModel(list)
        var asked = 0
        model.setPredictor { _ in
            asked += 1
            return [self.prediction(self.list[1]), self.prediction(self.list[2]), self.prediction(self.list[3])]
        }
        #expect(model.predictedCount == 2)
        #expect(model.results.prefix(2).map(\.command.title) == ["Beta", "Gamma"])
        let before = asked
        model.query = "al"
        #expect(model.predictedCount == 0)
        #expect(model.topPrediction == nil)
        #expect(model.results.map(\.command.title).contains("Alpha"))
        #expect(asked == before)
    }

    @Test func aPinnedCommandIsNotPredictedAgain() {
        let model = makeModel(list)
        let store = UsageStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("apropos-\(UUID().uuidString)/usage.json"),
            writeDelay: .zero)
        store.setPinned(true, for: list[1].stableID)
        model.setRanker(CommandRanker(signal: store.rankingSignal()))
        var offered: [String] = []
        model.setPredictor { eligible in
            offered = eligible.map(\.title)
            return [self.prediction(self.list[1]), self.prediction(self.list[2])]
        }
        _ = model.results
        #expect(!offered.contains("Beta"))
        #expect(model.results.map(\.command.title).filter { $0 == "Beta" }.count == 1)
        #expect(model.results.first?.command.title == "Beta")
        #expect(model.predictedCount == 1)
    }

    @Test func disabledCommandsAreNotOffered() {
        let items = [command("Alpha"), command("Beta", enabled: false)]
        let model = makeModel(items)
        var offered: [String] = []
        model.setPredictor { eligible in
            offered = eligible.map(\.title)
            return []
        }
        _ = model.results
        #expect(offered == ["Alpha"])
    }

    @Test func aPredictionWithoutAReasonStillFormsTheGroup() {
        let model = makeModel(list)
        model.setPredictor { _ in [Prediction(command: self.list[2].stableID, confidence: 0.9, reason: "", basis: .afterCommand)] }
        #expect(model.predictedCount == 1)
        #expect(model.predictionReason(forRowID: "Gamma") == nil)
        #expect(model.isPredicted(rowID: "Gamma"))
    }

    @Test func noPredictorMeansNoGroup() {
        let model = makeModel(list)
        #expect(model.predictedCount == 0)
        #expect(model.topPrediction == nil)
        #expect(model.results.map(\.command.title) == list.map(\.title))
    }

    @Test func refreshAsksThePredictorAgain() {
        let model = makeModel(list)
        var answer: [Prediction] = []
        model.setPredictor { _ in answer }
        #expect(model.predictedCount == 0)
        answer = [prediction(list[2])]
        #expect(model.predictedCount == 0)
        model.refreshPredictions()
        #expect(model.predictedCount == 1)
    }

    @Test func runTopPredictionRunsItWhateverIsHighlighted() async {
        var ran: [String] = []
        let model = makeModel(list) { command in
            ran.append(command.title)
            return .success(())
        }
        model.setPredictor { _ in [self.prediction(self.list[3])] }
        model.select(id: "Beta")
        let closed = await model.runTopPrediction()
        #expect(closed)
        #expect(ran == ["Delta"])
    }

    @Test func runTopPredictionDoesNothingWithoutAPrediction() async {
        var ran = 0
        let model = makeModel(list) { _ in
            ran += 1
            return .success(())
        }
        #expect(await model.runTopPrediction() == false)
        #expect(ran == 0)
    }

    // MARK: Engine

    private let now = Date(timeIntervalSince1970: 1_800_262_800)
    private func engine(_ url: URL? = nil) -> PredictionEngine {
        let location =
            url ?? FileManager.default.temporaryDirectory.appendingPathComponent("apropos-eng-\(UUID().uuidString)/sequence.json")
        return PredictionEngine(
            log: SequenceLog(url: location, writeDelay: .zero, now: now), buildInBackground: false)
    }

    private func id(_ title: String) -> CommandID { CommandID.base(bundleID: bundle, path: ["Menu"], title: title) }

    /// Alpha is always followed by Beta, thirty times.
    private func learnRoutine(_ engine: PredictionEngine) {
        for index in 0..<30 {
            let base = now - Double(40 - index) * 3_600
            engine.recordRun(id("Alpha"), app: bundle, at: base)
            engine.recordRun(id("Beta"), app: bundle, at: base + 20)
        }
    }

    private var candidates: [CommandID: String] { [id("Alpha"): "Alpha", id("Beta"): "Beta", id("Gamma"): "Gamma"] }

    @Test func engineShowsTheLearnedNextCommandWithItsReason() throws {
        let engine = engine()
        learnRoutine(engine)
        engine.recordRun(id("Alpha"), app: bundle, at: now)
        let rows = engine.rows(app: bundle, candidates: candidates, at: now + 5)
        let top = try #require(rows.first)
        #expect(top.command == id("Beta"))
        #expect(top.reason == "After Alpha you chose Beta 30 of 31 times" || top.reason.hasPrefix("After Alpha"))
    }

    @Test func reasonsCanBeSwitchedOff() throws {
        let engine = engine()
        learnRoutine(engine)
        engine.recordRun(id("Alpha"), app: bundle, at: now)
        engine.showsReasons = false
        let top = try #require(engine.rows(app: bundle, candidates: candidates, at: now + 5).first)
        #expect(top.command == id("Beta"))
        #expect(top.reason.isEmpty)
    }

    @Test func engineIsQuietWithoutHistoryOrWhenOff() {
        let engine = engine()
        #expect(engine.rows(app: bundle, candidates: candidates, at: now).isEmpty)
        learnRoutine(engine)
        engine.recordRun(id("Alpha"), app: bundle, at: now)
        engine.isEnabled = false
        #expect(engine.rows(app: bundle, candidates: candidates, at: now + 5).isEmpty)
        let count = engine.log.events.count
        engine.recordRun(id("Gamma"), app: bundle, at: now + 9)
        #expect(engine.log.events.count == count)
    }

    @Test func acceptingAndIgnoringArePutInTheLog() throws {
        let engine = engine()
        learnRoutine(engine)
        engine.recordRun(id("Alpha"), app: bundle, at: now)
        _ = engine.rows(app: bundle, candidates: candidates, at: now + 5)
        engine.recordRun(id("Beta"), app: bundle, at: now + 8)
        #expect(engine.log.events.last?.offered == id("Beta"))

        engine.recordRun(id("Alpha"), app: bundle, at: now + 100)
        _ = engine.rows(app: bundle, candidates: candidates, at: now + 105)
        engine.recordRun(id("Gamma"), app: bundle, at: now + 110)
        #expect(engine.log.events.last?.offered == id("Beta"))
        #expect(engine.log.events.last?.command == id("Gamma"))
    }

    @Test func aStaleOfferIsNotAttachedToALaterRun() {
        let engine = engine()
        learnRoutine(engine)
        engine.recordRun(id("Alpha"), app: bundle, at: now)
        _ = engine.rows(app: bundle, candidates: candidates, at: now + 5)
        engine.recordRun(id("Gamma"), app: bundle, at: now + 5 + PredictionEngine.offerLifetime + 10)
        #expect(engine.log.events.last?.offered == nil)
    }

    @Test func notNowSilencesAPredictionUntilItEarnsTrustAgain() throws {
        let engine = engine()
        learnRoutine(engine)
        engine.recordRun(id("Alpha"), app: bundle, at: now)
        #expect(!engine.rows(app: bundle, candidates: candidates, at: now + 5).isEmpty)
        engine.dismiss(id("Beta"), app: bundle, at: now + 6)
        engine.dismiss(id("Beta"), app: bundle, at: now + 7)
        #expect(engine.rows(app: bundle, candidates: candidates, at: now + 8).isEmpty)
        #expect(engine.log.events.suffix(2).allSatisfy { $0.kind == .dismiss })
    }

    @Test func resetForgetsTheLogAndTheModel() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("apropos-eng-\(UUID().uuidString)/sequence.json")
        let engine = engine(url)
        learnRoutine(engine)
        engine.recordRun(id("Alpha"), app: bundle, at: now)
        engine.reset()
        #expect(engine.log.events.isEmpty)
        #expect(engine.rows(app: bundle, candidates: candidates, at: now + 5).isEmpty)
        #expect(SequenceLog(url: url, writeDelay: .zero, now: now).events.isEmpty)
    }

    @Test func modelIsRebuiltFromTheLogAtLaunch() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("apropos-eng-\(UUID().uuidString)/sequence.json")
        let first = engine(url)
        learnRoutine(first)
        first.recordRun(id("Alpha"), app: bundle, at: now)
        first.log.flush()
        let reopened = PredictionEngine(log: SequenceLog(url: url, writeDelay: .zero, now: now))
        for _ in 0..<200 where !reopened.isReady { try await Task.sleep(for: .milliseconds(10)) }
        #expect(reopened.isReady)
        #expect(reopened.rows(app: bundle, candidates: candidates, at: now + 5).first?.command == id("Beta"))
    }

    @Test func commandsThatCannotBeLoggedAreNeverPredictedFromTheLog() {
        let engine = engine()
        let window = CommandID.base(bundleID: bundle, path: ["Window"], title: "Quarterly report")
        engine.recordRun(window, app: bundle, at: now)
        #expect(engine.log.events.isEmpty)
    }
}
