import Foundation
import Testing

@testable import Cue

struct CommandIDTests {
    private func id(_ title: String, path: [String] = ["File"], bundle: String? = "com.apple.finder") -> CommandID {
        CommandID.base(bundleID: bundle, path: path, title: title)
    }

    @Test func ellipsisSpellingsShareAnIdentity() {
        #expect(id("Save As…") == id("Save As..."))
        #expect(id("Save As…") == id("Save As"))
        #expect(id("Save As… ") == id("Save As…"))
    }

    @Test func caseAndSpacingDoNotMatter() {
        #expect(id("Show Path Bar") == id("Show path bar"))
        #expect(id("New  Folder") == id("New Folder"))
        #expect(id("Show\u{00A0}Path") == id("Show Path"))
    }

    @Test func updateCountsAreIgnored() {
        #expect(id("App Store, 3 updates", path: ["Apple"]) == id("App Store", path: ["Apple"]))
    }

    @Test func differentAppsAndPathsDiffer() {
        #expect(id("Copy") != id("Copy", bundle: "com.apple.Safari"))
        #expect(id("Copy", path: ["Edit"]) != id("Copy", path: ["File"]))
    }

    @Test func localizedTitlesKeepTheirOwnStableIdentity() {
        let french = id("Nouvelle fenêtre", path: ["Fichier"])
        #expect(french == id("Nouvelle fenetre", path: ["fichier"]))
        #expect(french != id("New Window"))
        #expect(french.rawValue.hasPrefix("com.apple.finder|"))
    }

    @Test func unnamedBundleHasNoBundleID() {
        let anonymous = id("Copy", bundle: nil)
        #expect(anonymous.bundleID == nil)
        #expect(id("Copy").bundleID == "com.apple.finder")
    }

    @Test func separatorsInTitlesCannotForgeAnotherPath() {
        #expect(id("A > B") != CommandID.base(bundleID: "com.apple.finder", path: ["File", "A"], title: "B"))
    }

    @Test func titleWithNothingUsableFallsBackToShortcutThenPosition() {
        let withKey = CommandID.base(
            bundleID: "x", path: ["View"], title: "…", shortcut: KeyShortcut(key: "K", modifiers: [.command]), position: 4)
        #expect(withKey.rawValue == "x|view>key ⌘K")
        let withoutKey = CommandID.base(bundleID: "x", path: ["View"], title: "…", shortcut: nil, position: 4)
        #expect(withoutKey.rawValue == "x|view>item 4")
    }

    @Test func codableUsesAPlainString() throws {
        let original = id("Copy")
        let data = try JSONEncoder().encode([original])
        #expect(String(decoding: data, as: UTF8.self) == "[\"com.apple.finder|file>copy\"]")
        #expect(try JSONDecoder().decode([CommandID].self, from: data) == [original])
    }

    @Test func mapperIdentitiesAreStableAcrossReadsAndIgnoreIndexShifts() {
        let first = MenuCommandMapper.commands(from: Fixtures.menuBar(), bundleID: "com.apple.finder")
        var shifted = Fixtures.menuBar()
        shifted[2].children.insert(MenuItemSnapshot(title: "Brand New Item"), at: 0)
        let second = MenuCommandMapper.commands(from: shifted, bundleID: "com.apple.finder")
        let firstByTitle = Dictionary(uniqueKeysWithValues: first.map { ($0.title, $0.stableID) })
        for command in second where command.title != "Brand New Item" {
            #expect(firstByTitle[command.title] == command.stableID, "\(command.title)")
        }
        #expect(first.map(\.id) != second.map(\.id).prefix(first.count).map { $0 })
        #expect(Set(first.map(\.stableID)).count == first.count)
    }

    @Test func collidingTitlesAreSeparatedByShortcutThenOrdinal() {
        let bar = [
            MenuItemSnapshot(
                title: "File",
                children: [
                    MenuItemSnapshot(title: "Open Recent", children: [
                        MenuItemSnapshot(title: "Untitled", cmdChar: "1", cmdModifiers: 0),
                        MenuItemSnapshot(title: "Untitled", cmdChar: "2", cmdModifiers: 0),
                        MenuItemSnapshot(title: "Untitled"),
                        MenuItemSnapshot(title: "Untitled"),
                    ])
                ])
        ]
        let ids = MenuCommandMapper.commands(from: bar, bundleID: "a").map(\.stableID.rawValue)
        #expect(ids.count == 4)
        #expect(Set(ids).count == 4)
        #expect(ids[0].hasSuffix("|⌘1"))
        #expect(ids[1].hasSuffix("|⌘2"))
        #expect(ids[3].hasSuffix("#2"))
    }

    @Test func commandInitDerivesAnIdentityFromItsSource() {
        let command = Command(id: "0.1", title: "Copy", path: ["Edit"], source: .menuItem(bundleID: "b"))
        #expect(command.stableID.rawValue == "b|edit>copy")
    }
}
