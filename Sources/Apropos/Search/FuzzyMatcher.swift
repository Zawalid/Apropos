import Foundation

/// The result of matching a query against one string.
public struct FuzzyMatch: Sendable, Equatable {
    /// How the query sits in the candidate. A person who types the start of a name means it more than one who types
    /// letters that happen to be in it.
    public enum Kind: Int, Sendable, Comparable {
        case scattered, initials, wordPrefix, prefix, exact
        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let score: Int
    /// Offsets (in `Character`s) of the candidate characters that matched, ascending.
    public let positions: [Int]
    public let kind: Kind

    public init(score: Int, positions: [Int], kind: Kind = .scattered) {
        self.score = score
        self.positions = positions
        self.kind = kind
    }
}

/// Subsequence matching with scoring in the spirit of fzf: every query character must appear in order, matches at
/// word starts and in unbroken runs score higher, gaps cost a little. The best alignment is found with a small
/// dynamic program, so "nw" finds "New Window" at the two word starts rather than at the first "n" and "w".
public enum FuzzyMatcher {
    static let matchScore = 16
    static let consecutiveBonus = 12
    static let boundaryBonus = 10
    static let startBonus = 14
    static let camelBonus = 7
    static let gapStart = 4
    static let gapExtension = 1
    static let leadingGapPenalty = 1
    static let maxLeadingGap = 6
    static let impossible = Int.min / 2

    public static func match(_ query: String, in candidate: String) -> FuzzyMatch? {
        let needle = Array(query.filter { !$0.isWhitespace }).map { fold($0) }
        guard !needle.isEmpty else { return FuzzyMatch(score: 0, positions: []) }
        let original = Array(candidate)
        let hay = original.map { fold($0) }
        guard needle.count <= hay.count else { return nil }

        let rows = needle.count
        let cols = hay.count
        let bonus = boundaryBonuses(original)

        // score[i][j]: best score with needle[i] matched at hay[j]. parent[i][j]: where needle[i - 1] matched.
        var score = [[Int]](repeating: [Int](repeating: impossible, count: cols), count: rows)
        var parent = [[Int]](repeating: [Int](repeating: -1, count: cols), count: rows)

        for j in 0..<cols where hay[j] == needle[0] {
            score[0][j] = matchScore + bonus[j] - min(j, maxLeadingGap) * leadingGapPenalty
        }
        if rows > 1 {
            for i in 1..<rows {
                var runningBest = impossible
                var runningFrom = -1
                for j in 0..<cols {
                    // Candidates that leave a gap: any earlier match at k <= j - 2, penalised by the gap length.
                    if j >= 2 {
                        let k = j - 2
                        if runningBest > impossible { runningBest -= gapExtension }
                        let viaK = score[i - 1][k] > impossible ? score[i - 1][k] - gapStart : impossible
                        if viaK >= runningBest {
                            runningBest = viaK
                            runningFrom = k
                        }
                    }
                    guard hay[j] == needle[i] else { continue }
                    var best = impossible
                    var from = -1
                    if j >= 1, score[i - 1][j - 1] > impossible {
                        let run = score[i - 1][j - 1] + matchScore + max(consecutiveBonus, bonus[j])
                        best = run
                        from = j - 1
                    }
                    if runningBest > impossible {
                        let gapped = runningBest + matchScore + bonus[j]
                        if gapped > best {
                            best = gapped
                            from = runningFrom
                        }
                    }
                    if best > impossible {
                        score[i][j] = best
                        parent[i][j] = from
                    }
                }
            }
        }

        var bestScore = impossible
        var bestEnd = -1
        for j in 0..<cols where score[rows - 1][j] > bestScore {
            bestScore = score[rows - 1][j]
            bestEnd = j
        }
        guard bestEnd >= 0 else { return nil }

        var positions = [Int](repeating: 0, count: rows)
        var j = bestEnd
        for i in stride(from: rows - 1, through: 0, by: -1) {
            positions[i] = j
            j = parent[i][j]
        }
        return FuzzyMatch(score: bestScore, positions: positions, kind: kind(of: positions, original: original, bonus: bonus))
    }

    /// Lowercase and without accents, one character to one character, so positions still point into the original.
    static func fold(_ character: Character) -> Character {
        let folded = String(character).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return folded.count == 1 ? folded[folded.startIndex] : Character(character.lowercased())
    }

    /// Whether the matched characters form the start of the text, the start of a word, the first letters of words, or
    /// are spread about. Separators between matched characters do not break a run: "newfolder" is all of "New Folder".
    static func kind(of positions: [Int], original: [Character], bonus: [Int]) -> FuzzyMatch.Kind {
        guard let first = positions.first, let last = positions.last else { return .scattered }
        let contiguous = zip(positions, positions.dropFirst()).allSatisfy { pair in
            pair.1 == pair.0 + 1 || original[(pair.0 + 1)..<pair.1].allSatisfy(isSeparator)
        }
        if contiguous, first == 0 {
            let rest = original[(last + 1)...]
            return rest.allSatisfy(isSeparator) ? .exact : .prefix
        }
        if contiguous, bonus[first] > 0 { return .wordPrefix }
        if positions.count >= 2, positions.allSatisfy({ bonus[$0] > 0 }) { return .initials }
        return .scattered
    }

    /// The bonus for matching at each position: highest at the start, high after a separator, some at a camelCase hump.
    static func boundaryBonuses(_ text: [Character]) -> [Int] {
        var result = [Int](repeating: 0, count: text.count)
        for index in text.indices {
            guard index > 0 else {
                result[index] = startBonus
                continue
            }
            let previous = text[index - 1]
            let current = text[index]
            if isSeparator(previous) {
                result[index] = boundaryBonus
            } else if previous.isLowercase && current.isUppercase {
                result[index] = camelBonus
            }
        }
        return result
    }

    static func isSeparator(_ character: Character) -> Bool {
        character.isWhitespace || "-_./›>:()[]".contains(character)
    }
}
