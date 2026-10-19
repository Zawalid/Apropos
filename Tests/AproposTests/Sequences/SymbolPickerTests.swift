import AppKit
import Testing

@testable import Apropos

@Suite("Symbol picker")
struct SymbolPickerTests {
    private func names(_ sections: [SymbolSection]) -> [String] { sections.flatMap(\.symbols).map(\.name) }

    // MARK: The list

    @Test func theListIsCuratedInGroupsOfAUsefulSize() {
        #expect((150...260).contains(SymbolPicker.all.count))
        #expect(
            SymbolPicker.groups.map(\.title)
                == ["Actions", "Files", "Web", "Text", "Dev", "Media", "Communication", "Symbols"])
        #expect(SymbolPicker.groups.allSatisfy { $0.symbols.count >= 20 })
    }

    @Test func noSymbolIsListedTwice() {
        let all = SymbolPicker.all.map(\.name)
        #expect(Set(all).count == all.count)
    }

    @Test func everyNameIsARealSymbol() {
        let missing = SymbolPicker.all.map(\.name).filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil
        }
        #expect(missing.isEmpty, "not symbols: \(missing)")
        #expect(NSImage(systemSymbolName: SymbolPicker.defaultSymbol, accessibilityDescription: nil) != nil)
    }

    // MARK: Finding

    @Test func withoutAQueryTheSuggestionsComeFirstAndAreNotRepeated() {
        let sections = SymbolPicker.sections(query: "", suggested: ["envelope", "square.stack.3d.up", "envelope"])
        #expect(sections.first?.title == "Suggested")
        #expect(sections.first?.symbols.map(\.name) == ["envelope", "square.stack.3d.up"])
        let all = names(sections)
        #expect(Set(all).count == all.count)
        #expect(sections.dropFirst().map(\.title).first == "Actions")
    }

    @Test func withoutSuggestionsThereIsNoSuggestedGroup() {
        #expect(SymbolPicker.sections(query: "  ").first?.title == "Actions")
    }

    @Test func searchFindsByNameAndByKeyword() {
        #expect(names(SymbolPicker.sections(query: "folder")).prefix(3).contains("folder"))
        let mail = names(SymbolPicker.sections(query: "mail"))
        #expect(mail.contains("envelope") && mail.contains("paperplane"))
        #expect(names(SymbolPicker.sections(query: "bug")).first == "ladybug")
        #expect(names(SymbolPicker.sections(query: "trash")).first == "trash")
    }

    @Test func everyWordTypedHasToMatch() {
        let both = names(SymbolPicker.sections(query: "folder plus"))
        #expect(both.contains("folder.badge.plus"))
        #expect(!both.contains("trash"))
        #expect(SymbolPicker.sections(query: "folder zzzz").isEmpty)
    }

    @Test func searchIgnoresCaseAndDots() {
        #expect(names(SymbolPicker.sections(query: "FOLDER.badge")).contains("folder.badge.plus"))
    }

    @Test func aCustomNameComesAfterTheMatchesUnlessTheListHasIt() {
        let alone = SymbolPicker.sections(query: "folder.badge.gearshape", custom: "folder.badge.gearshape")
        #expect(alone.map(\.title) == ["Custom"] && alone.first?.symbols.map(\.name) == ["folder.badge.gearshape"])
        let after = SymbolPicker.sections(query: "mail", custom: "mail")
        #expect(after.map(\.title) == ["Matches", "Custom"])
        let known = SymbolPicker.sections(query: "trash", custom: "trash")
        #expect(known.map(\.title) == ["Matches"])
    }

    // MARK: Walking

    private func grid(_ rows: [[String]]) -> [SymbolSection] {
        rows.enumerated().map { number, names in
            SymbolSection(title: "S\(number)", symbols: names.map { PickerSymbol(name: $0, keywords: []) })
        }
    }

    private func go(_ from: String, _ move: SymbolMove, in sections: [SymbolSection]) -> String? {
        SymbolPicker.neighbour(of: from, move: move, in: sections, columns: 3)
    }

    @Test func leftAndRightWalkTheOrderAcrossSections() {
        let sections = grid([["a", "b", "c", "d"], ["e", "f"]])
        #expect(go("b", .right, in: sections) == "c")
        #expect(go("d", .right, in: sections) == "e")
        #expect(go("e", .left, in: sections) == "d")
        #expect(go("a", .left, in: sections) == nil)
        #expect(go("f", .right, in: sections) == nil)
    }

    @Test func upAndDownKeepTheColumnInsideASection() {
        let sections = grid([["a", "b", "c", "d", "e", "f", "g"]])
        #expect(go("b", .down, in: sections) == "e")
        #expect(go("e", .up, in: sections) == "b")
        // The last row is shorter: land on its last symbol.
        #expect(go("f", .down, in: sections) == "g")
        #expect(go("c", .up, in: sections) == nil)
    }

    @Test func upAndDownCrossTheBorderBetweenSections() {
        let sections = grid([["a", "b", "c", "d", "e"], ["f", "g", "h", "i"]])
        // From the last row of the first section into the first row of the next.
        #expect(go("e", .down, in: sections) == "g")
        #expect(go("d", .down, in: sections) == "f")
        // And back up into the last row of the section above, same column when it has one.
        #expect(go("g", .up, in: sections) == "e")
        #expect(go("h", .up, in: sections) == "e")
        #expect(go("f", .up, in: sections) == "d")
        #expect(go("i", .down, in: sections) == nil)
    }

    @Test func aSymbolThatIsNotShownLandsOnTheFirstOne() {
        let sections = grid([["a", "b"]])
        #expect(go("zzz", .down, in: sections) == "a")
        #expect(go("a", .down, in: []) == nil)
    }

    @Test func theRealGridCanBeWalkedFromEndToEnd() {
        let sections = SymbolPicker.sections(query: "", suggested: ["bolt"])
        var current = names(sections)[0]
        var seen = [current]
        while let next = SymbolPicker.neighbour(of: current, move: .right, in: sections) {
            seen.append(next)
            current = next
        }
        #expect(seen == names(sections))
        // Going down from the top never gets stuck before the end.
        current = seen[0]
        var steps = 0
        while let next = SymbolPicker.neighbour(of: current, move: .down, in: sections), steps < 200 {
            #expect(next != current)
            current = next
            steps += 1
        }
        #expect(steps > 10)
    }
}
