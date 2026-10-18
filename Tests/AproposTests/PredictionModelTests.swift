import Foundation
import Testing

@testable import Apropos

struct PredictionModelTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Monday 2027-01-18 09:00 UTC.
    private let monday9 = Date(timeIntervalSince1970: 1_800_262_800)
    private let day: TimeInterval = 86_400

    private let xcode = "com.apple.dt.Xcode"
    private let terminal = "com.apple.Terminal"
    private let safari = "com.apple.Safari"

    private func id(_ bundle: String, _ title: String, menu: String = "Menu") -> CommandID {
        CommandID.base(bundleID: bundle, path: [menu], title: title)
    }

    private func event(
        _ command: CommandID, app: String, at date: Date, previous: CommandID? = nil, kinds: [ContextKind] = [],
        offered: CommandID? = nil
    ) -> RunEvent {
        guard
            let event = RunEvent(
                at: date, command: command, app: app, previous: previous, contextKinds: kinds, offered: offered)
        else { fatalError("test event refused") }
        return event
    }

    private func model(_ events: [RunEvent]) -> PredictionModel {
        var model = PredictionModel(calendar: Self.utc)
        model.train(events)
        return model
    }

    /// `build -> tests -> commit` repeated, with a given number of deviations to `deploy`.
    private func routine(repeats: Int, deviations: Int = 0, start: Date) -> [RunEvent] {
        let build = id(xcode, "Build", menu: "Product")
        let tests = id(xcode, "Run Tests", menu: "Product")
        let commit = id(terminal, "Commit", menu: "Git")
        let deploy = id(terminal, "Deploy", menu: "Git")
        var events: [RunEvent] = []
        for index in 0..<repeats {
            let base = start + Double(index) * 3_600
            events.append(event(build, app: xcode, at: base))
            events.append(event(tests, app: xcode, at: base + 20, previous: build))
            events.append(event(index < deviations ? deploy : commit, app: terminal, at: base + 60, previous: tests))
        }
        return events
    }

    @Test func nothingIsPredictedWithoutAnyDataOrUsage() {
        let model = PredictionModel(calendar: Self.utc)
        #expect(model.predict(PredictionContext(app: xcode, date: monday9)).isEmpty)
    }

    @Test func learnsTheCommandThatFollowsAnother() throws {
        let events = routine(repeats: 12, start: monday9 - 5 * day)
        let model = model(events)
        let tests = id(xcode, "Run Tests", menu: "Product")
        let commit = id(terminal, "Commit", menu: "Git")
        let predictions = model.predict(
            PredictionContext(app: terminal, recent: [tests], date: monday9), title: { $0.fallbackTitle })
        let top = try #require(predictions.first)
        #expect(top.command == commit)
        #expect(top.confidence > 0.7)
        #expect(top.reason == "After Run Tests you chose Commit 12 of 12 times")
        #expect(top.basis == .afterCommand || top.basis == .afterTwoCommands)
    }

    @Test func crossAppLinkIsFoundThroughTheCommandNotTheApp() throws {
        let events = routine(repeats: 10, start: monday9 - 3 * day)
        let model = model(events)
        let build = id(xcode, "Build", menu: "Product")
        // In Terminal after a Build: the app-keyed table is empty for this pair of (Terminal, Build), the any-app one is not.
        let predictions = model.predict(PredictionContext(app: terminal, recent: [build], date: monday9))
        #expect(predictions.first?.command == id(terminal, "Commit", menu: "Git"))
    }

    @Test func secondOrderBeatsFirstOrderWhenItIsMoreSpecific() throws {
        // After "Save": "Close" if "Open" came before it, "Share" if "New" did.
        let open = id(safari, "Open"), new = id(safari, "New"), save = id(safari, "Save")
        let close = id(safari, "Close"), share = id(safari, "Share")
        var events: [RunEvent] = []
        for index in 0..<10 {
            let base = monday9 - Double(20 - index) * 3_600
            events.append(event(open, app: safari, at: base))
            events.append(event(save, app: safari, at: base + 10, previous: open))
            events.append(event(close, app: safari, at: base + 20, previous: save))
            let second = base + 1_800
            events.append(event(new, app: safari, at: second))
            events.append(event(save, app: safari, at: second + 10, previous: new))
            events.append(event(share, app: safari, at: second + 20, previous: save))
        }
        let model = model(events)
        let afterOpen = model.predict(PredictionContext(app: safari, recent: [save, open], date: monday9))
        let afterNew = model.predict(PredictionContext(app: safari, recent: [save, new], date: monday9))
        #expect(afterOpen.first?.command == close)
        #expect(afterNew.first?.command == share)
        #expect(afterOpen.first?.basis == .afterTwoCommands)
        #expect(afterOpen.first?.reason.hasPrefix("After Open then Save") == true)
    }

    @Test func timeOfDayPriorSeparatesMorningFromEvening() throws {
        let news = id(safari, "News"), game = id(safari, "Games")
        var events: [RunEvent] = []
        for index in 0..<14 {
            // 09:00 and 21:00 on consecutive Mondays..Sundays.
            let dayStart = monday9 - Double(30 - index) * day
            events.append(event(news, app: safari, at: dayStart))
            events.append(event(game, app: safari, at: dayStart + 12 * 3_600))
        }
        let model = model(events)
        let morning = model.predict(PredictionContext(app: safari, date: monday9 + day))
        let evening = model.predict(PredictionContext(app: safari, date: monday9 + day + 12 * 3_600))
        #expect(morning.first?.command == news)
        #expect(evening.first?.command == game)
        #expect(morning.first?.reason.contains("in the morning") == true)
    }

    @Test func contextKindsShiftThePrediction() throws {
        let format = id(safari, "Format"), search = id(safari, "Search")
        var events: [RunEvent] = []
        for index in 0..<12 {
            let when = monday9 - Double(30 - index) * 3_600
            events.append(event(format, app: safari, at: when, kinds: [.selection]))
            events.append(event(search, app: safari, at: when + 7_200, kinds: [.url]))
        }
        let model = model(events)
        let withSelection = model.predict(PredictionContext(app: safari, date: monday9, contextKinds: ["selection"]))
        #expect(withSelection.first?.command == format)
        #expect(withSelection.first?.reason.hasPrefix("With text selected") == true)
    }

    @Test func recencyDecayLetsANewHabitTakeOver() throws {
        let tests = id(xcode, "Run Tests", menu: "Product")
        let commit = id(terminal, "Commit", menu: "Git")
        let archive = id(terminal, "Archive", menu: "Git")
        var events: [RunEvent] = []
        for index in 0..<30 {  // old habit, 90 days ago
            let base = monday9 - 90 * day + Double(index) * 600
            events.append(event(tests, app: xcode, at: base))
            events.append(event(commit, app: terminal, at: base + 30, previous: tests))
        }
        for index in 0..<8 {  // new habit, last two weeks
            let base = monday9 - 10 * day + Double(index) * 600
            events.append(event(tests, app: xcode, at: base))
            events.append(event(archive, app: terminal, at: base + 30, previous: tests))
        }
        let model = model(events)
        let top = model.predict(PredictionContext(app: terminal, recent: [tests], date: monday9)).first
        #expect(top?.command == archive)
    }

    @Test func confidenceGrowsWithEvidence() {
        let tests = id(xcode, "Run Tests", menu: "Product")
        let few = model(routine(repeats: 2, start: monday9 - day))
        let many = model(routine(repeats: 20, start: monday9 - day))
        let context = PredictionContext(app: terminal, recent: [tests], date: monday9)
        let low = few.predict(context).first?.confidence ?? 0
        let high = many.predict(context).first?.confidence ?? 0
        #expect(low > 0)
        #expect(high > low)
    }

    @Test func confidenceReflectsRealUncertainty() throws {
        // After Run Tests: Commit 6 times, Deploy 6 times. Neither may look certain.
        let events = routine(repeats: 12, deviations: 6, start: monday9 - 2 * day)
        let model = model(events)
        let tests = id(xcode, "Run Tests", menu: "Product")
        let top = try #require(model.predict(PredictionContext(app: terminal, recent: [tests], date: monday9)).first)
        #expect(top.confidence > 0.3 && top.confidence < 0.65)
    }

    @Test func frecencyIsTheColdStartFallback() throws {
        let save = id(safari, "Save"), close = id(safari, "Close")
        let prior = FrecencyPrior(scores: [save: 900, close: 100])
        let model = PredictionModel(calendar: Self.utc)
        let predictions = model.predict(PredictionContext(app: safari, date: monday9), prior: prior)
        #expect(predictions.map(\.command) == [save, close])
        #expect(predictions[0].basis == .frecency)
        #expect(abs(predictions[0].confidence - 0.9) < 1e-9)
        #expect(predictions[0].reason == "You use Save often in this app")
    }

    @Test func candidatesRestrictWhatCanBeNamed() throws {
        let model = model(routine(repeats: 10, start: monday9 - day))
        let tests = id(xcode, "Run Tests", menu: "Product")
        let commit = id(terminal, "Commit", menu: "Git")
        let other = id(terminal, "Other", menu: "Git")
        let predictions = model.predict(
            PredictionContext(app: terminal, recent: [tests], date: monday9), candidates: [other])
        #expect(!predictions.contains { $0.command == commit })
    }

    @Test func defaultCandidatesStayInsideTheFrontmostApp() {
        let model = model(routine(repeats: 10, start: monday9 - day))
        let build = id(xcode, "Build", menu: "Product")
        let predictions = model.predict(PredictionContext(app: xcode, recent: [id(terminal, "Commit", menu: "Git")], date: monday9))
        #expect(predictions.allSatisfy { $0.command.bundleID == xcode })
        _ = build
    }

    // MARK: Feedback

    @Test func notNowAndIgnoringLowerAPredictionAndAcceptingKeepsIt() throws {
        let tests = id(xcode, "Run Tests", menu: "Product")
        let commit = id(terminal, "Commit", menu: "Git")
        let base = routine(repeats: 12, start: monday9 - 2 * day)
        let context = PredictionContext(app: terminal, recent: [tests], date: monday9)
        let before = try #require(model(base).predict(context).first { $0.command == commit }).confidence

        let dismissed = base + [
            RunEvent(kind: .dismiss, at: monday9 - 100, command: commit, app: terminal)
        ].compactMap { $0 }
        let afterDismiss = try #require(model(dismissed).predict(context).first { $0.command == commit }).confidence
        #expect(afterDismiss < before * 0.6)

        let ignored = base + (0..<4).map { event(id(terminal, "Other", menu: "Git"), app: terminal, at: monday9 - 500 + Double($0), offered: commit) }
        let afterIgnore = try #require(model(ignored).predict(context).first { $0.command == commit }).confidence
        #expect(afterIgnore < before)

        let accepted = base + (0..<4).map { event(commit, app: terminal, at: monday9 - 500 + Double($0), offered: commit) }
        let afterAccept = try #require(model(accepted).predict(context).first { $0.command == commit }).confidence
        #expect(afterAccept > afterIgnore)
    }

    // MARK: Determinism and speed

    @Test func trainingAndPredictingAreDeterministic() {
        let events = routine(repeats: 30, deviations: 9, start: monday9 - 5 * day)
        let context = PredictionContext(app: terminal, recent: [id(xcode, "Run Tests", menu: "Product")], date: monday9)
        let first = model(events).predict(context, limit: 5)
        let second = model(events.reversed()).predict(context, limit: 5)
        #expect(first == second)
    }

    @Test func predictsWithinTwoMillisecondsOnAYearOfData() {
        var generator = SplitMix64(seed: 7)
        let apps = (0..<12).map { "com.test.app\($0)" }
        let commandsPerApp = 80
        var events: [RunEvent] = []
        var previous: RunEvent?
        let start = monday9 - 365 * day
        for index in 0..<36_500 {  // about one hundred runs a day for a year
            let app = apps[Int(generator.next() % UInt64(apps.count))]
            let title = "Command \(generator.next() % UInt64(commandsPerApp))"
            let time = start + Double(index) * 864
            let command = id(app, title)
            let chained = previous.map { time.timeIntervalSince($0.date) <= SequenceLog.sessionWindow } == true
            let built = event(
                command, app: app, at: time, previous: chained ? previous?.command : nil,
                kinds: index % 3 == 0 ? [.document, .selection] : [])
            events.append(built)
            previous = built
        }
        let model = model(events)
        let all = Set((0..<commandsPerApp).map { id(apps[0], "Command \($0)") })
        let context = PredictionContext(
            app: apps[0], recent: [id(apps[1], "Command 3"), id(apps[0], "Command 9")], date: monday9,
            contextKinds: ["document"])
        _ = model.predict(context, limit: 3, candidates: all)  // warm up
        let runs = 50
        let clock = ContinuousClock()
        let elapsed = clock.measure { for _ in 0..<runs { _ = model.predict(context, limit: 3, candidates: all) } }
        let perCall = Double(elapsed.components.attoseconds) / 1e18 / Double(runs) + Double(elapsed.components.seconds) / Double(runs)
        #expect(perCall < 0.002, "a prediction took \(perCall * 1000) ms")
        let unrestricted = clock.measure { for _ in 0..<runs { _ = model.predict(context, limit: 3) } }
        let perCallOpen = Double(unrestricted.components.attoseconds) / 1e18 / Double(runs) + Double(unrestricted.components.seconds) / Double(runs)
        #expect(perCallOpen < 0.002, "an unrestricted prediction took \(perCallOpen * 1000) ms")
    }
}

/// A small deterministic random source, so tests and the evaluation harness repeat exactly.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
