import Testing

@testable import Cue

@Suite("MenuCommandMapper")
struct MenuCommandMapperTests {
    let commands = MenuCommandMapper.commands(from: Fixtures.menuBar(), bundleID: "com.apple.finder")

    private func command(_ title: String) -> Command? { commands.first { $0.title == title } }

    @Test func dropsTheAppleMenuSeparatorsAndSubmenuHeaders() {
        #expect(command("About This Mac") == nil)
        #expect(commands.allSatisfy { !$0.title.isEmpty })
        #expect(command("Open Recent") == nil)
    }

    @Test func skipsTheServicesSubmenu() {
        #expect(command("Reveal in Finder") == nil)
    }

    @Test func keepsMenuOrder() {
        let titles = commands.map(\.title)
        #expect(titles.first == "About Finder")
        #expect(titles.firstIndex(of: "New Finder Window")! < titles.firstIndex(of: "Copy")!)
    }

    @Test func recordsTheMenuTrail() {
        #expect(command("Copy")?.path == ["Edit"])
        #expect(command("Notes.md")?.path == ["File", "Open Recent"])
        #expect(command("Notes.md")?.breadcrumb == "File › Open Recent")
    }

    @Test func idsAreUnique() {
        #expect(Set(commands.map(\.id)).count == commands.count)
    }

    @Test func carriesEnabledAndCheckedState() {
        #expect(command("Move to Trash")?.isEnabled == false)
        #expect(command("Copy")?.isEnabled == true)
        #expect(command("as Icons")?.isChecked == true)
        #expect(command("as List")?.isChecked == false)
    }

    @Test func buildsShortcutsFromCharAndModifiers() {
        #expect(command("Copy")?.shortcut?.display == "⌘C")
        #expect(command("New Folder")?.shortcut?.display == "⇧⌘N")
        #expect(command("Show Path Bar")?.shortcut?.display == "⌥⌘P")
        #expect(command("Settings…")?.shortcut?.display == "⌘,")
    }

    @Test func modifierBitEightMeansNoCommandKey() {
        #expect(command("Show Preview")?.shortcut?.display == "⇧P")
    }

    @Test func usesVirtualKeysForSpecialKeys() {
        #expect(command("Move to Trash")?.shortcut?.display == "⌘⌫")
    }

    @Test func itemsWithoutAShortcutHaveNone() {
        #expect(command("About Finder")?.shortcut == nil)
    }

    @Test func shortcutCapsListModifiersThenKey() {
        #expect(command("New Folder")?.shortcut?.caps == ["⇧", "⌘", "N"])
    }

    @Test func attachesTheSourceBundle() {
        #expect(commands.allSatisfy { $0.source == .menuItem(bundleID: "com.apple.finder") })
    }

    @Test func keepsTheActionTarget() throws {
        let log = Fixtures.Log()
        let mapped = MenuCommandMapper.commands(from: Fixtures.menuBar(log: log), bundleID: nil)
        let copy = try #require(mapped.first { $0.title == "Copy" })
        try copy.target?.perform()
        #expect(log.all == ["Copy"])
    }

    @Test func emptyBarGivesNoCommands() {
        #expect(MenuCommandMapper.commands(from: [], bundleID: nil).isEmpty)
    }
}
