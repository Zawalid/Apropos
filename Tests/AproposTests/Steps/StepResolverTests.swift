import Foundation
import Testing

@testable import Apropos

@Suite("Step resolver")
struct StepResolverTests {
    private let resolver = StepResolver()

    private func resolve(
        _ locators: [StepLocator], in app: StepFakeNode, action: StepAction = .menu
    ) -> StepResolution {
        resolver.resolve(StepFixtures.step(locators: locators, action: action), in: app)
    }

    private func tag(_ resolution: StepResolution) -> String? { (resolution.element as? StepFakeNode)?.tag }

    @Test func anIdentifierWinsOverEverythingElse() {
        let app = FakeTree.app(menus: FakeTree.fixtureMenus())
        let resolution = resolve(
            [
                .menuPath(["File", "Export as PDF"]), .shortcut(key: "S", modifiers: [.command]),
                .identifier("menu.export"),
            ], in: app)
        #expect(tag(resolution) == "menu.export")
        #expect(resolution.matchedKind == .identifier)
        #expect(!resolution.isDegraded)
    }

    @Test func locatorsAreTriedStrongestFirstWhateverTheStoredOrder() {
        let app = FakeTree.app(menus: FakeTree.fixtureMenus())
        let resolution = resolve(
            [.position([1, 0]), .shortcut(key: "E", modifiers: [.command]), .menuPath(["File", "Save"])], in: app)
        #expect(resolution.matchedKind == .menuPath)
        #expect(tag(resolution) == "menu.save")
        #expect(resolution.attempts.map(\.kind) == [.menuPath])
    }

    @Test func fallsThroughAndReportsTheStrategyThatMatched() {
        let app = FakeTree.app(menus: FakeTree.fixtureMenus())
        let resolution = resolve(
            [
                .identifier("gone"), .roleTitle(role: "AXMenuItem", title: "Nothing"),
                .shortcut(key: "E", modifiers: [.command]),
            ],
            in: app)
        #expect(tag(resolution) == "menu.export")
        #expect(resolution.matchedKind == .shortcut)
        #expect(resolution.isDegraded)
        #expect(resolution.attempts.map(\.outcome) == [.notFound, .notFound, .matched])
    }

    @Test func roleAndTitleIgnoreCaseAccentsAndEllipsis() {
        let app = FakeTree.app(menus: [("Fichier", [FakeItem(title: "Ouvrir\u{2026}", id: "open")])])
        #expect(tag(resolve([.roleTitle(role: "AXMenuItem", title: "ouvrir...")], in: app)) == "open")
        let edit = FakeTree.app(menus: FakeTree.fixtureMenus(french: true, identifiers: false))
        #expect(resolve([.menuPath(["edition", "tout selectionner"])], in: edit).isMatch)
    }

    // MARK: Ambiguity

    @Test func ambiguousTitlesAreRefusedNotGuessed() {
        let menus: [(String, [FakeItem])] = [
            ("File", [FakeItem(title: "Export", id: "a"), FakeItem(title: "Close", id: "c1")]),
            ("Edit", [FakeItem(title: "Export", id: "b")]),
        ]
        let app = FakeTree.app(menus: menus)
        let resolution = resolve([.roleTitle(role: "AXMenuItem", title: "Export")], in: app)
        #expect(!resolution.isMatch)
        #expect(resolution.failure == .ambiguous)
        #expect(resolution.attempts == [LocatorAttempt(kind: .roleTitle, outcome: .ambiguous(count: 2))])
    }

    @Test func anAmbiguousLocatorIsSkippedWhenAStrongerOrWeakerOneIsUnique() {
        let menus: [(String, [FakeItem])] = [
            ("File", [FakeItem(title: "Export", id: "a")]), ("Edit", [FakeItem(title: "Export", id: "b")]),
        ]
        let app = FakeTree.app(menus: menus)
        let resolution = resolve(
            [.roleTitle(role: "AXMenuItem", title: "Export"), .menuPath(["Edit", "Export"])], in: app)
        #expect(tag(resolution) == "b")
        #expect(resolution.matchedKind == .menuPath)
        #expect(resolution.isDegraded)
        #expect(resolution.attempts.first?.outcome == .ambiguous(count: 2))
    }

    @Test func duplicateIdentifiersAreAmbiguousToo() {
        let menus: [(String, [FakeItem])] = [
            ("File", [FakeItem(title: "A", id: "dup"), FakeItem(title: "B", id: "dup")])
        ]
        let resolution = resolve([.identifier("dup")], in: FakeTree.app(menus: menus))
        #expect(resolution.failure == .ambiguous)
    }

    // MARK: Languages

    @Test func identifiersAndShortcutsSurviveAFrenchUI() {
        let french = FakeTree.app(menus: FakeTree.fixtureMenus(french: true))
        let byID = resolve(
            [.roleTitle(role: "AXMenuItem", title: "Export as PDF"), .identifier("menu.export")], in: french)
        #expect(tag(byID) == "menu.export")
        #expect(byID.matchedKind == .identifier)

        let noIDs = FakeTree.app(menus: FakeTree.fixtureMenus(french: true, identifiers: false))
        let byShortcut = resolve(
            [.menuPath(["File", "Export as PDF"]), .shortcut(key: "E", modifiers: [.command])], in: noIDs)
        #expect(byShortcut.matchedKind == .shortcut)
        #expect(byShortcut.isMatch)
    }

    @Test func titleOnlyLocatorsFailInAnotherLanguage() {
        let french = FakeTree.app(menus: FakeTree.fixtureMenus(french: true, identifiers: false))
        let resolution = resolve(
            [.roleTitle(role: "AXMenuItem", title: "Export as PDF"), .menuPath(["File", "Export as PDF"])], in: french)
        #expect(resolution.failure == .notFound)
    }

    // MARK: Drift

    @Test func itemsAppKitAppendsDoNotBreakTitlesIdentifiersOrShortcuts() {
        let drifted = FakeTree.app(menus: FakeTree.fixtureMenus(appended: true))
        for locator in [
            StepLocator.identifier("menu.selectAll"), .menuPath(["Edit", "Select All"]),
            .shortcut(key: "A", modifiers: [.command]), .roleTitle(role: "AXMenuItem", title: "Select All"),
        ] {
            #expect(tag(resolve([locator], in: drifted)) == "menu.selectAll")
        }
    }

    @Test func aPositionDriftsWhenItemsAreAppended() {
        let original = FakeTree.app(menus: FakeTree.fixtureMenus())
        let drifted = FakeTree.app(menus: FakeTree.fixtureMenus(appended: true))
        // Edit is the second menu after Apple: [2], Select All was third: [2, 2].
        #expect(tag(resolve([.position([2, 2])], in: original)) == "menu.selectAll")
        #expect(tag(resolve([.position([2, 2])], in: drifted)) != "menu.selectAll")
    }

    @Test func positionNeverMatchesAMenuHeaderOrSeparator() {
        let app = FakeTree.app(menus: FakeTree.fixtureMenus(appended: true))
        // [2, 2] is a separator and [2, 3] is the Writing Tools submenu header.
        #expect(resolve([.position([2, 2])], in: app).failure != nil)
        #expect(resolve([.position([2, 3])], in: app).failure != nil)
    }

    // MARK: Privacy of the menu bar

    @Test func theAppleMenuIsNeverSearched() {
        let app = FakeTree.app(menus: FakeTree.fixtureMenus())
        for locator in [
            StepLocator.identifier("apple.logout"), .roleTitle(role: "AXMenuItem", title: "About This Mac"),
            .menuPath(["Apple", "About This Mac"]), .shortcut(key: "Q", modifiers: [.shift, .command]),
            .position([0, 0]),
        ] {
            #expect(!resolve([locator], in: app).isMatch)
        }
    }

    @Test func recentItemsMenusAreNeverSearched() {
        let app = FakeTree.app(menus: FakeTree.fixtureMenus())
        #expect(!resolve([.roleTitle(role: "AXMenuItem", title: "Quarterly-Report.numbers")], in: app).isMatch)
        let french = FakeTree.app(menus: FakeTree.fixtureMenus(french: true))
        #expect(!resolve([.roleTitle(role: "AXMenuItem", title: "Quarterly-Report.numbers")], in: french).isMatch)
    }

    @Test func theAppleMenuIsSkippedByPositionNotByTitleAlone() {
        // In some language the first menu bar item could carry another title; index 0 is still skipped.
        let app = FakeTree.app(menus: FakeTree.fixtureMenus(), apple: [FakeItem(title: "Hello", id: "first")])
        #expect(!resolve([.identifier("first")], in: app).isMatch)
    }

    // MARK: Enabled, empty, budget

    @Test func aDisabledItemIsFoundAndReportedDisabled() {
        let app = FakeTree.app(menus: FakeTree.fixtureMenus())
        let resolution = resolve([.identifier("menu.delete")], in: app)
        #expect(resolution.isMatch)
        #expect(!resolution.isEnabled)
    }

    @Test func anAppWithoutAMenuBarReportsIt() {
        let empty = StepFakeNode(tag: "app")
        #expect(resolve([.identifier("x")], in: empty).failure == .noMenuBar)
    }

    @Test func aBudgetStopsTheSearch() {
        let app = FakeTree.app(menus: FakeTree.fixtureMenus())
        let tight = StepResolver(budget: ResolveBudget(maxNodes: 3))
        #expect(
            tight.resolve(StepFixtures.step(locators: [.identifier("menu.paste")]), in: app).failure == .budgetExceeded)
        let expired = StepResolver(budget: ResolveBudget(isExpired: { true }))
        #expect(
            expired.resolve(StepFixtures.step(locators: [.identifier("menu.paste")]), in: app).failure
                == .budgetExceeded)
    }

    // MARK: Secure fields

    @Test func aLocatorThatPointsAtAPasswordFieldIsRefused() {
        let log = AttributeLog()
        let secure = FakeTree.element(role: "AXTextField", id: "pw", subrole: StepText.secureRole, log: log)
        let app = FakeTree.app(menus: [], windows: [FakeTree.window([secure], log: log)], log: log)
        let step = StepFixtures.step(locators: [.identifier("pw")], action: .press)
        let resolution = resolver.resolve(step, in: app)
        #expect(resolution.failure == .secureField)
        #expect(!resolution.isMatch)
    }

    @Test func noValueAttributeIsEverRead() {
        let log = AttributeLog()
        let field = FakeTree.element(role: "AXTextField", title: "Name", id: "name", log: log)
        let secure = FakeTree.element(role: "AXTextField", id: "pw", subrole: StepText.secureRole, log: log)
        let app = FakeTree.app(
            menus: FakeTree.fixtureMenus(), windows: [FakeTree.window([field, secure], log: log)], log: log)
        _ = resolver.resolve(StepFixtures.step(locators: [.identifier("name")], action: .press), in: app)
        _ = resolver.resolve(StepFixtures.step(locators: [.identifier("pw")], action: .press), in: app)
        _ = resolver.resolve(StepFixtures.exportPDF, in: app)
        let forbidden: Set<String> = ["AXValue", "AXSelectedText", "AXSelectedTextRange", "AXDocument", "AXURL"]
        #expect(log.all.intersection(forbidden).isEmpty)
        #expect(log.count > 0)
    }

    @Test func aSecureFieldGetsOnlyItsIdentityTitleAndIdentifierRead() {
        let secureLog = AttributeLog()
        let secure = FakeTree.element(role: "AXTextField", id: "pw", subrole: StepText.secureRole, log: secureLog)
        let app = FakeTree.app(menus: [], windows: [FakeTree.window([secure])])
        _ = resolver.find(.identifier("nothing"), inWindowsOf: app)
        #expect(secureLog.count > 0)
        #expect(secureLog.all.isSubset(of: ["AXRole", "AXSubrole", "AXTitle", "AXIdentifier"]))
    }

    // MARK: Expectations

    @Test func findLooksAmongTheWindows() {
        let sheet = FakeTree.element(role: "AXSheet", id: "export.sheet")
        let app = FakeTree.app(menus: [], windows: [FakeTree.window([sheet])])
        #expect(resolver.find(.identifier("export.sheet"), inWindowsOf: app).isMatch)
        #expect(!resolver.find(.identifier("other"), inWindowsOf: app).isMatch)
        #expect(resolver.find(.roleTitle(role: "AXSheet", title: "Nope"), inWindowsOf: app).failure == .notFound)
    }
}
