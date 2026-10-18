import Testing

@testable import Cue

@Suite("CommandRanker")
struct CommandRankerTests {
    let commands = MenuCommandMapper.commands(from: Fixtures.menuBar(), bundleID: nil)
    let ranker = CommandRanker()

    @Test func emptyQueryKeepsMenuOrderWithDisabledLast() {
        let ranked = ranker.rank(commands, query: "")
        #expect(ranked.count == commands.count)
        #expect(ranked.last?.command.title == "Move to Trash")
        let enabledOrder = commands.filter(\.isEnabled).map(\.id)
        #expect(ranked.dropLast().map(\.id) == enabledOrder)
    }

    @Test func queryKeepsOnlyMatches() {
        let ranked = ranker.rank(commands, query: "list")
        #expect(ranked.map(\.command.title) == ["as List"])
    }

    @Test func bestMatchComesFirst() {
        let ranked = ranker.rank(commands, query: "new")
        #expect(ranked.first?.command.title == "New Folder" || ranked.first?.command.title == "New Finder Window")
        #expect(ranked.prefix(2).allSatisfy { $0.command.title.hasPrefix("New") })
    }

    @Test func matchesThroughTheMenuName() {
        let ranked = ranker.rank(commands, query: "edit copy")
        #expect(ranked.first?.command.title == "Copy")
        #expect(ranked.first?.titlePositions.isEmpty == true)
    }

    @Test func highlightsTitleMatches() {
        let ranked = ranker.rank(commands, query: "sel")
        #expect(ranked.first?.command.title == "Select All")
        #expect(ranked.first?.titlePositions == [0, 1, 2])
    }

    @Test func disabledCommandsSinkBelowEnabledOnes() {
        let ranked = ranker.rank(commands, query: "move")
        #expect(ranked.count == 1)
        let both = ranker.rank(
            commands + [Command(id: "x", title: "Move Along", path: ["X"], source: .menuItem(bundleID: nil))],
            query: "move")
        #expect(both.first?.command.title == "Move Along")
    }

    @Test func exactTitleWins() {
        let list = [
            Command(id: "1", title: "Copy Path", path: [], source: .menuItem(bundleID: nil)),
            Command(id: "2", title: "Copy", path: [], source: .menuItem(bundleID: nil)),
        ]
        #expect(ranker.rank(list, query: "copy").first?.id == "2")
    }

    @Test func shorterTitleBreaksTies() {
        let list = [
            Command(id: "1", title: "Zoom In Fully", path: [], source: .menuItem(bundleID: nil)),
            Command(id: "2", title: "Zoom In", path: [], source: .menuItem(bundleID: nil)),
        ]
        #expect(ranker.rank(list, query: "zoo").map(\.id) == ["2", "1"])
    }

    @Test func noMatchGivesNothing() {
        #expect(ranker.rank(commands, query: "zzzzqq").isEmpty)
    }

    @Test func aSignalBoostsACommand() {
        struct Prefer: RankingSignal {
            func boost(for command: Command) -> Int { command.title == "Select All" ? 1000 : 0 }
        }
        let boosted = CommandRanker(signal: Prefer()).rank(commands, query: "e")
        #expect(boosted.first?.command.title == "Select All")
    }

    @Test func stubSignalChangesNothing() {
        #expect(NoRankingSignal().boost(for: commands[0]) == 0)
    }
}
