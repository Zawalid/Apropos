import Foundation
import Testing

@testable import Apropos

struct PredictionEvaluationTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private func evaluator() -> PredictionEvaluator {
        var evaluator = PredictionEvaluator()
        evaluator.calendar = Self.utc
        return evaluator
    }

    private func profile(days: Int = 200, seed: UInt64 = 1) -> SyntheticProfile {
        var profile = SyntheticProfile()
        profile.days = days
        profile.seed = seed
        return profile
    }

    // MARK: Generator

    @Test func generatorIsDeterministicAndSeedDependent() {
        let first = SyntheticLog.generate(profile(days: 20, seed: 5))
        let again = SyntheticLog.generate(profile(days: 20, seed: 5))
        let other = SyntheticLog.generate(profile(days: 20, seed: 6))
        #expect(first == again)
        #expect(first != other)
        #expect(first.count > 300)
    }

    @Test func generatedLogIsChronologicalWithConsistentSessions() {
        let events = SyntheticLog.generate(profile(days: 30))
        let times = events.map(\.time)
        #expect(times == times.sorted())
        for (index, event) in events.enumerated().dropFirst() {
            let gap = event.time - events[index - 1].time
            if gap <= SequenceLog.sessionWindow {
                #expect(event.previous == events[index - 1].command)
            } else {
                #expect(event.previous == nil)
            }
        }
    }

    @Test func generatedLogContainsRoutinesInterleavingNoiseAndWeekendDifferences() {
        let events = SyntheticLog.generate(profile(days: 60))
        let titles = Set(events.map { $0.command.fallbackTitle })
        #expect(titles.contains("Run Tests") && titles.contains("Git Commit") && titles.contains("Reply"))
        #expect(titles.contains { $0.hasPrefix("Misc Command") })
        let xcode = events.filter { $0.app == "com.apple.dt.Xcode" }
        let weekend = xcode.filter {
            let weekday = Self.utc.component(.weekday, from: $0.date)
            return weekday == 1 || weekday == 7
        }
        // The development loop never runs on weekends; only interleaved steps and noise reach Xcode then.
        #expect(weekend.count * 20 < xcode.count)
    }

    @Test func driftChangesWhatFollowsTheTests() {
        var drifting = profile(days: 100)
        drifting.driftDay = 50
        let events = SyntheticLog.generate(drifting)
        let cut = drifting.start.timeIntervalSince1970 + 50 * 86_400
        let before = events.filter { $0.time < cut && $0.command.fallbackTitle == "Archive" && $0.app == "com.apple.Terminal" }
        let after = events.filter { $0.time >= cut && $0.command.fallbackTitle == "Archive" && $0.app == "com.apple.Terminal" }
        #expect(before.isEmpty)
        #expect(after.count > 50)
    }

    // MARK: Evaluation

    @Test func evaluationIsDeterministic() {
        let events = SyntheticLog.generate(profile(days: 120))
        #expect(evaluator().run(events) == evaluator().run(events))
    }

    @Test func modelBeatsBothBaselinesOnRoutines() {
        let report = evaluator().run(SyntheticLog.generate(profile()))
        #expect(report.model.hitAt1 > report.frecency.hitAt1 + 0.1)
        #expect(report.model.hitAt1 > report.repeatLast.hitAt1 + 0.3)
        #expect(report.model.hitAt3 >= report.frecency.hitAt3)
        #expect(report.modelWhereShown > report.frecencyWhereShown + 0.2)
        #expect(report.modelWhereShown > report.repeatLastWhereShown + 0.4)
    }

    @Test func whatIsShownIsMostlyRightAndCalibrated() {
        let report = evaluator().run(SyntheticLog.generate(profile()))
        #expect(report.model.coverage > 0.2)
        #expect(report.model.wrongWhenShown < 0.15)
        #expect(report.expectedCalibrationError < 0.1)
        let top = report.reliability.filter { $0.lower >= 0.9 && $0.count > 20 }
        for bin in top { #expect(bin.hitRate > 0.9) }
    }

    @Test func chosenThresholdMatchesTheDocumentedRule() {
        var profile = profile(days: 365)
        profile.driftDay = 243
        let report = evaluator().run(SyntheticLog.generate(profile))
        let recommended = PredictionEvaluator.recommendedThreshold(report.sweep, maxWrong: 0.10)
        #expect(recommended == PredictionPolicy.showThreshold)
    }

    @Test func noisyHabitsStillBeatTheBaselinesButShowLess() {
        var noisy = profile()
        noisy.noise = 0.25
        noisy.interleave = 0.3
        let calm = evaluator().run(SyntheticLog.generate(profile()))
        let report = evaluator().run(SyntheticLog.generate(noisy))
        #expect(report.model.hitAt1 > report.frecency.hitAt1)
        #expect(report.model.coverage < calm.model.coverage)
        #expect(report.model.wrongWhenShown < 0.25)
    }

    @Test func staysQuietWhenThereIsNothingToLearn() {
        var random = SeededGenerator(seed: 99)
        var events: [RunEvent] = []
        var time = 1_767_225_600.0
        var previous: RunEvent?
        for _ in 0..<6_000 {
            time += Double(30 + random.next() % 900)
            let app = "com.test.app\(random.next() % 3)"
            let id = CommandID.base(bundleID: app, path: ["Menu"], title: "Command \(random.next() % 30)")
            let chained = previous.map { time - $0.time <= SequenceLog.sessionWindow } == true
            guard
                let event = RunEvent(
                    at: Date(timeIntervalSince1970: time), command: id, app: app, previous: chained ? previous?.command : nil)
            else { continue }
            events.append(event)
            previous = event
        }
        let report = evaluator().run(events)
        #expect(report.model.coverage < 0.03)
    }

    @Test func recoversAfterAChangeOfHabit() {
        var drifting = profile(days: 300)
        drifting.driftDay = 150
        let report = evaluator().run(SyntheticLog.generate(drifting))
        let steady = evaluator().run(SyntheticLog.generate(profile(days: 300)))
        #expect(report.model.hitAt1 > steady.model.hitAt1 - 0.08)
    }

    @Test func tooFewEventsGiveAnEmptyReport() {
        let report = evaluator().run([])
        #expect(report.testEvents == 0)
    }

    @Test func reportNamesNoCommandsOrApps() {
        let text = evaluator().run(SyntheticLog.generate(profile(days: 60))).render()
        for word in ["com.apple", "Git", "Xcode", "Commit", "Notes", "Misc"] { #expect(!text.contains(word)) }
        #expect(text.contains("hit@1"))
    }

    // MARK: Policy

    @Test func policyShowsNothingBelowTheThresholdAndAtMostTwoRows() {
        func prediction(_ name: String, _ confidence: Double) -> Prediction {
            Prediction(
                command: CommandID(rawValue: "app|menu>\(name)"), confidence: confidence, reason: "", basis: .afterCommand)
        }
        #expect(PredictionPolicy.rows(from: []).isEmpty)
        #expect(PredictionPolicy.rows(from: [prediction("a", 0.6), prediction("b", 0.3)]).isEmpty)
        let two = PredictionPolicy.rows(from: [prediction("a", 0.7), prediction("b", 0.28), prediction("c", 0.26)])
        #expect(two.count == 2)
        let one = PredictionPolicy.rows(from: [prediction("a", 0.9), prediction("b", 0.05)])
        #expect(one.count == 1)
    }
}
