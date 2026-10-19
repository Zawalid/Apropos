import Foundation
import Testing

@testable import Apropos

/// The full comparison is slow (hundreds of thousands of rankings, in a debug build) and prints numbers, so it only runs
/// when asked: APROPOS_RANK_EVAL=1 swift test --filter RankingEvaluation. One small check always runs.
@Suite("Ranking evaluation")
struct RankingEvaluationTests {
    static let seeds: [UInt64] = [1, 2, 3, 4, 5, 6, 7, 8]

    private func run(_ name: String, _ change: (inout RankingTuning) -> Void) -> RankingEvaluation.Report {
        var tuning = RankingTuning()
        change(&tuning)
        let report = RankingEvaluation.average(engine: { SimulatedRankingEngine(tuning: tuning) }, seeds: Self.seeds)
        print(RankingEvaluation.describe(name, report))
        return report
    }

    @Test func theSmartRankingBeatsTheOldOneOnASmallWorld() {
        let seeds: [UInt64] = [1, 2]
        let legacy = RankingEvaluation.average(
            engine: { SimulatedRankingEngine(tuning: .legacy) }, seeds: seeds, intentCount: 500)
        let smart = RankingEvaluation.average(engine: { SimulatedRankingEngine() }, seeds: seeds, intentCount: 500)
        #expect(smart.meanCost < legacy.meanCost)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["APROPOS_RANK_EVAL"] != nil))
    func grid() {
        let seeds: [UInt64] = [1, 2, 3, 4]
        func show(_ name: String, drift: Int? = nil, _ change: (inout RankingTuning) -> Void) {
            var tuning = RankingTuning()
            change(&tuning)
            let report = RankingEvaluation.average(
                engine: { SimulatedRankingEngine(tuning: tuning) }, seeds: seeds, intentCount: 800, driftAt: drift)
            print(RankingEvaluation.describe(name.padding(toLength: 16, withPad: " ", startingAt: 0), report))
        }
        print("== base")
        show("default") { _ in }
        show("learned 0") { $0.learnedMax = 0 }
        show("learned strict") { $0.learnedMinSupport = 3; $0.learnedMinShare = 0.7 }
        show("learned loose") { $0.learnedMinSupport = 1; $0.learnedMinShare = 0.3 }
        show("learned 60 s4") { $0.learnedMax = 60; $0.learnedMinSupport = 4; $0.learnedMinShare = 0.7 }
        print("== habits drift")
        show("default drift", drift: 400) { _ in }
        show("halfLife7 drift", drift: 400) { $0.halfLifeDays = 7 }
        show("legacy drift", drift: 400) { $0 = .legacy }
    }
}
