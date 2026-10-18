import Testing

@testable import Cue

struct AlternateCommandTests {
    private func menu(_ items: [MenuItemSnapshot]) -> [MenuItemSnapshot] {
        [MenuItemSnapshot(title: "Finder"), MenuItemSnapshot(title: "File", children: items)]
    }

    private var finderFile: [MenuItemSnapshot] {
        [
            MenuItemSnapshot(title: "New Folder", cmdChar: "n", cmdModifiers: 1),
            MenuItemSnapshot(title: "Close Window", cmdChar: "w"),
            MenuItemSnapshot(title: "Close All", cmdChar: "w", cmdModifiers: 2),
            MenuItemSnapshot(title: ""),
            MenuItemSnapshot(title: "Empty Trash", cmdModifiers: 1, cmdVirtualKey: 51),
            MenuItemSnapshot(title: "Empty Trash Securely", cmdModifiers: 1 | 2, cmdVirtualKey: 51),
            MenuItemSnapshot(title: "Get Info", cmdChar: "i"),
        ]
    }

    @Test func alternatesAreFoldedIntoTheirPrimary() {
        let commands = MenuCommandMapper.commands(from: menu(finderFile), bundleID: "com.apple.finder")
        #expect(commands.map(\.title) == ["New Folder", "Close Window", "Empty Trash", "Get Info"])
        let close = commands[1]
        #expect(close.alternates.map(\.title) == ["Close All"])
        #expect(close.alternates.first?.shortcut == KeyShortcut(key: "W", modifiers: [.option, .command]))
        let trash = commands[2]
        #expect(trash.alternates.map(\.title) == ["Empty Trash Securely"])
    }

    @Test func alternatesKeepTheirOwnStableIdentity() {
        let commands = MenuCommandMapper.commands(from: menu(finderFile), bundleID: "com.apple.finder")
        let trash = commands[2]
        let alternate = trash.alternates[0]
        #expect(alternate.stableID != trash.stableID)
        #expect(alternate.stableID.rawValue == "com.apple.finder|file>empty trash securely")
    }

    @Test func showAlternatesKeepsThemAsRowsLinkedToThePrimary() {
        let commands = MenuCommandMapper.commands(
            from: menu(finderFile), bundleID: "com.apple.finder", showAlternates: true)
        #expect(commands.count == 7 - 1)
        let secure = commands.first { $0.title == "Empty Trash Securely" }
        #expect(secure?.alternateOf == commands.first { $0.title == "Empty Trash" }?.stableID)
        #expect(commands.allSatisfy { $0.alternates.isEmpty })
    }

    @Test func aRunOfAlternatesAllBelongToTheFirstItem() {
        let items = [
            MenuItemSnapshot(title: "Close", cmdChar: "w"),
            MenuItemSnapshot(title: "Close All", cmdChar: "w", cmdModifiers: 2),
            MenuItemSnapshot(title: "Close Others", cmdChar: "w", cmdModifiers: 2 | 1),
        ]
        let commands = MenuCommandMapper.commands(from: menu(items), bundleID: "x")
        #expect(commands.count == 1)
        #expect(commands[0].alternates.map(\.title) == ["Close All", "Close Others"])
    }

    @Test func sameKeyWithoutOptionIsNotAnAlternate() {
        let items = [
            MenuItemSnapshot(title: "Close Tab", cmdChar: "w"),
            MenuItemSnapshot(title: "Close Window", cmdChar: "w", cmdModifiers: 1),
        ]
        #expect(MenuCommandMapper.commands(from: menu(items), bundleID: "x").count == 2)
    }

    @Test func aSeparatorBreaksTheRun() {
        let items = [
            MenuItemSnapshot(title: "Close", cmdChar: "w"),
            MenuItemSnapshot(title: ""),
            MenuItemSnapshot(title: "Close All", cmdChar: "w", cmdModifiers: 2),
        ]
        #expect(MenuCommandMapper.commands(from: menu(items), bundleID: "x").count == 2)
    }

    @Test func primaryThatUsesOptionNeverGainsAlternates() {
        let items = [
            MenuItemSnapshot(title: "Hide Others", cmdChar: "h", cmdModifiers: 2),
            MenuItemSnapshot(title: "Hide Others Too", cmdChar: "h", cmdModifiers: 2 | 1),
        ]
        #expect(MenuCommandMapper.commands(from: menu(items), bundleID: "x").count == 2)
    }

    @Test func itemsWithoutShortcutsAreNeverFolded() {
        let items = [MenuItemSnapshot(title: "A"), MenuItemSnapshot(title: "B")]
        #expect(MenuCommandMapper.commands(from: menu(items), bundleID: "x").count == 2)
    }

    @Test func existingFixtureIsUnchanged() {
        let commands = MenuCommandMapper.commands(from: Fixtures.menuBar(), bundleID: nil)
        #expect(commands.allSatisfy { $0.alternates.isEmpty })
    }
}
