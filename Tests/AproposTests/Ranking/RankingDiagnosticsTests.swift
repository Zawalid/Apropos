import Foundation
import Testing

@testable import Apropos

@Suite("Ranking diagnostics")
struct RankingDiagnosticsTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["APROPOS_RANK_EVAL"] != nil))
    func worstCases() {
        var engine = SimulatedRankingEngine()
        let person = RankingSimulation.person(seed: 3)
        let intents = RankingSimulation.intents(for: person, count: 1200)
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        var shown = 0
        for (index, intent) in intents.enumerated() {
            let now = start.addingTimeInterval(Double(index) / 30 * 86_400)
            guard let catalogue = RankingSimulation.catalogues.first(where: { $0.app == intent.app }),
                let item = catalogue.items.first(where: { $0.id == intent.itemID })
            else { continue }
            let commands = catalogue.commands
            let id = CommandID.base(bundleID: intent.app, path: item.path, title: item.title)
            if index >= 600, !intent.typed.isEmpty, shown < 40 {
                let order = engine.rank(app: intent.app, commands: commands, query: intent.typed, previous: nil, now: now)
                let rank = (order.firstIndex { $0.stableID == id } ?? 999) + 1
                if rank > 3 {
                    shown += 1
                    print("MISS \(intent.habit) typed=\(intent.typed) target=\(item.title) rank=\(rank) top=\(order.prefix(3).map(\.title))")
                }
            }
            if let command = commands.first(where: { $0.stableID == id }) {
                engine.learn(command, query: intent.typed, previous: nil, now: now)
            }
        }
    }
}
