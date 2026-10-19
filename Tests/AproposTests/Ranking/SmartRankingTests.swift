import Foundation
import Testing

@testable import Apropos

@Suite("Smart ranking")
struct SmartRankingTests {
    private let app = "com.apple.finder"

    private func command(_ title: String, _ path: [String] = ["File"]) -> Command {
        Command(
            id: "\(path.joined())>\(title)", title: title, path: path, source: .menuItem(bundleID: app),
            stableID: CommandID.base(bundleID: app, path: path, title: title))
    }

    private func titles(_ ranked: [RankedCommand]) -> [String] { ranked.map(\.command.title) }

    /// Usage in memory for tests: `uses` runs of each command, the last one at `now`.
    private func signal(_ uses: [(Command, Int)], queries: [(Command, String, Int)] = [], now: Date = Date()) -> UsageSignal {
        var records: [CommandID: UsageRecord] = [:]
        for (command, count) in uses {
            records[command.stableID] = UsageRecord(
                runs: count, recent: (0..<min(count, 10)).map { now.addingTimeInterval(-Double($0) * 3600) })
        }
        for (command, query, count) in queries {
            var record = records[command.stableID] ?? UsageRecord(runs: count, recent: [now])
            record.queries[query] = count
            records[command.stableID] = record
        }
        return UsageSignal.build(
            records: records, pins: [:], hidden: [], aliases: [:], now: now, tuning: RankingTuning())
    }

    @Test func theStartOfAWordBeatsLettersScatteredThroughAnother() {
        let list = [command("Add to Reading List"), command("Open Recent"), command("Remember")]
        #expect(titles(CommandRanker().rank(list, query: "rec")).first == "Open Recent")
    }

    @Test func typingTheStartOfAnExactTitleFindsItBeforeLongerOnes() {
        let list = [command("Close Other Tabs"), command("Close Window"), command("Close")]
        #expect(titles(CommandRanker().rank(list, query: "clo")).first == "Close")
    }

    @Test func firstLettersFindTheCommand() {
        let list = [command("New Folder"), command("Nine Frames"), command("Find Next")]
        #expect(titles(CommandRanker().rank(list, query: "nf")).first == "New Folder")
    }

    @Test func aSlipOfTwoLettersStillFindsIt() {
        let list = [command("Show Sidebar"), command("Hide Toolbar")]
        #expect(titles(CommandRanker().rank(list, query: "shwo")).first == "Show Sidebar")
        // Without the slip feature nothing would match at all.
        var strict = RankingTuning()
        strict.typoTolerance = false
        #expect(CommandRanker(tuning: strict).rank(list, query: "shwo").isEmpty)
    }

    @Test func accentsDoNotGetInTheWay() {
        let list = [command("Résumé"), command("Reset")]
        #expect(titles(CommandRanker().rank(list, query: "resume")).first == "Résumé")
    }

    @Test func useLiftsAGoodMatchButNeverARescuesAPoorOne() {
        let used = command("Copy Path")
        let better = command("Copy")
        let scattered = command("Open Recent Projects")
        let ranker = CommandRanker(signal: signal([(used, 40), (scattered, 60)]))
        // "cop": the used command wins among prefix matches, and a heavily used scattered match stays below a clean one.
        let ranked = titles(ranker.rank([better, used, scattered], query: "cop"))
        #expect(ranked.firstIndex(of: "Copy")! < ranked.firstIndex(of: "Open Recent Projects") ?? 99)
        #expect(ranked.first == "Copy" || ranked.first == "Copy Path")
    }

    @Test func aNameTheyOftenTypeFindsTheCommand() {
        let target = command("Show Original")
        let other = command("Show Path Bar", ["View"])
        let list = [other, target]
        let memory = signal([(target, 5), (other, 5)], queries: [(target, "so", 6)])
        let ranked = CommandRanker(signal: memory).rank(list, query: "so")
        #expect(ranked.first?.command.title == "Show Original")
    }

    @Test func aWhatComesNextPriorBreaksTiesBetweenLookalikes() {
        let build = command("Build", ["Product"])
        let buildFor = command("Build For Testing", ["Product"])
        let ranker = CommandRanker()
        let plain = titles(ranker.rank([buildFor, build], query: "bui"))
        #expect(plain.first == "Build")
        let primed = titles(ranker.rank([buildFor, build], query: "bui", priors: [buildFor.stableID: 0.9, build.stableID: 0.05]))
        #expect(primed.first == "Build For Testing")
    }

    @Test func learnedNamesKeepOnlyFragmentsOfTheCommandsOwnName() {
        let copy = command("Copy Path", ["Edit"])
        #expect(RankingMemory.learnable("cp", for: copy) == "cp")
        #expect(RankingMemory.learnable("Copy", for: copy) == "copy")
        // Free text that is not an abbreviation of the name is never kept.
        #expect(RankingMemory.learnable("my password is hunter2", for: copy).isEmpty)
        #expect(RankingMemory.learnable("zzz", for: copy).isEmpty)
        #expect(RankingMemory.learnable("a very long thing to type here", for: copy).isEmpty)
        #expect(RankingMemory.learnable("", for: copy).isEmpty)
    }

    @Test func storedNamesSurviveTheFileAndOldFilesStillLoad() throws {
        var record = UsageRecord(runs: 3, recent: [Date(timeIntervalSince1970: 1_800_000_000)])
        RankingMemory.learn("cp", into: &record)
        RankingMemory.learn("cp", into: &record)
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(UsageRecord.self, from: data).queries == ["cp": 2])
        let old = Data(#"{"runs":2,"recent":[0]}"#.utf8)
        #expect(try JSONDecoder().decode(UsageRecord.self, from: old).queries.isEmpty)
    }

    @Test func eachCommandKeepsFewNames() {
        var record = UsageRecord(runs: 1, recent: [])
        for name in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"] { RankingMemory.learn(name, into: &record) }
        #expect(record.queries.count <= RankingMemory.queriesPerCommand)
    }

    @Test func emptyQueryPutsUsedCommandsFirstInsideTheirMenu() {
        let a = command("Alpha", ["File"])
        let b = command("Beta", ["File"])
        let c = command("Gamma", ["Edit"])
        let ranker = CommandRanker(signal: signal([(b, 10)]))
        #expect(titles(ranker.rank([a, b, c], query: "")) == ["Beta", "Alpha", "Gamma"])
    }

    @Test func theOldTuningStillBehavesTheOldWay() {
        let list = [command("Show Sidebar")]
        #expect(CommandRanker(tuning: .legacy).rank(list, query: "shwo").isEmpty)
    }
}
