import Testing

@testable import Cue

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {
    @Test func emptyQueryMatchesEverythingWithNoPositions() {
        let match = FuzzyMatcher.match("", in: "Anything")
        #expect(match == FuzzyMatch(score: 0, positions: []))
    }

    @Test func requiresEveryCharacterInOrder() {
        #expect(FuzzyMatcher.match("cpy", in: "Copy") != nil)
        #expect(FuzzyMatcher.match("ypc", in: "Copy") == nil)
        #expect(FuzzyMatcher.match("copyx", in: "Copy") == nil)
        #expect(FuzzyMatcher.match("copying", in: "Copy") == nil)
    }

    @Test func ignoresCaseAndSpacesInTheQuery() {
        #expect(FuzzyMatcher.match("NEW win", in: "new window") != nil)
    }

    @Test func prefersWordStartsOverScatteredLetters() throws {
        let match = try #require(FuzzyMatcher.match("nw", in: "New Window"))
        #expect(match.positions == [0, 4])
    }

    @Test func positionsPointAtTheMatchedCharacters() throws {
        let match = try #require(FuzzyMatcher.match("sel", in: "Select All"))
        #expect(match.positions == [0, 1, 2])
    }

    @Test func prefixBeatsInnerMatch() throws {
        let prefix = try #require(FuzzyMatcher.match("copy", in: "Copy"))
        let inner = try #require(FuzzyMatcher.match("copy", in: "Make a Copy"))
        #expect(prefix.score > inner.score)
    }

    @Test func consecutiveRunBeatsSpreadMatch() throws {
        let run = try #require(FuzzyMatcher.match("fold", in: "New Folder"))
        let spread = try #require(FuzzyMatcher.match("fold", in: "Find Old Documents"))
        #expect(run.score > spread.score)
    }

    @Test func wordBoundaryBeatsMidWord() throws {
        let boundary = try #require(FuzzyMatcher.match("pb", in: "Show Path Bar"))
        let mid = try #require(FuzzyMatcher.match("pb", in: "Capable"))
        #expect(boundary.score > mid.score)
    }

    @Test func handlesRepeatedLettersWithoutReusingOne() {
        #expect(FuzzyMatcher.match("aa", in: "banana") != nil)
        #expect(FuzzyMatcher.match("aaaa", in: "banana") == nil)
    }

    @Test func caseHumpsCountAsWordStarts() throws {
        let match = try #require(FuzzyMatcher.match("gc", in: "getCommand"))
        #expect(match.positions == [0, 3])
    }

    @Test func queryLongerThanCandidateFails() {
        #expect(FuzzyMatcher.match("abcdef", in: "abc") == nil)
    }
}
