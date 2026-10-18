import Testing

@testable import Cue

@MainActor
@Suite("PaletteModel")
struct PaletteModelTests {
    private func makeModel(
        trusted: Bool = true, run: (@MainActor (Command) async -> Result<Void, CommandRunError>)? = nil
    )
        -> (PaletteModel, AppMenuModel)
    {
        let tracker = FrontmostAppTracker(ownBundleID: "test")
        let permission = AccessibilityPermission(probe: { trusted })
        let menus = AppMenuModel(tracker: tracker, permission: permission)
        let model = PaletteModel(menus: menus, tracker: tracker, runner: run)
        return (model, menus)
    }

    private let commands = MenuCommandMapper.commands(from: Fixtures.menuBar(), bundleID: nil)

    @Test func showsThePermissionStateWithoutAccess() {
        let (model, _) = makeModel(trusted: false)
        #expect(model.content == .needsPermission)
    }

    @Test func seededCommandsAreListedAndFirstEnabledIsSelected() {
        let (model, menus) = makeModel()
        menus.seed(commands)
        model.prepareForOpen()
        #expect(model.content == .results)
        #expect(model.results.count == commands.count)
        #expect(model.selected?.command.title == "About Finder")
    }

    @Test func typingFiltersAndSelectsTheBestMatch() {
        let (model, menus) = makeModel()
        menus.seed(commands)
        model.query = "sel"
        #expect(model.results.map(\.command.title) == ["Select All"])
        #expect(model.selected?.command.title == "Select All")
    }

    @Test func noMatchesIsItsOwnState() {
        let (model, menus) = makeModel()
        menus.seed(commands)
        model.query = "zzzzqq"
        #expect(model.content == .noMatches(query: "zzzzqq"))
        #expect(model.selected == nil)
    }

    @Test func emptyMenuReportsNoCommands() {
        let (model, menus) = makeModel()
        menus.seed([])
        #expect(model.content == .noCommands(appName: "This app"))
    }

    @Test func selectionMovesAndClampsAtTheEnds() {
        let (model, menus) = makeModel()
        menus.seed(commands)
        model.prepareForOpen()
        let first = model.selected?.id
        model.moveSelection(by: -1)
        #expect(model.selected?.id == first)
        model.moveSelection(by: 1)
        #expect(model.selected?.id == model.results[1].id)
        model.moveSelection(by: 1000)
        #expect(model.selected?.id == model.results.last?.id)
        model.selectFirst()
        #expect(model.selected?.id == first)
    }

    @Test func runningSuccessfullyAllowsClose() async {
        let log = Fixtures.Log()
        let list = MenuCommandMapper.commands(from: Fixtures.menuBar(log: log), bundleID: nil)
        let (model, menus) = makeModel()
        menus.seed(list)
        model.query = "copy"
        let close = await model.runSelected()
        #expect(close)
        #expect(log.all == ["Copy"])
        #expect(model.runError == nil)
    }

    @Test func runningADisabledCommandFailsWithAMessage() async {
        let (model, menus) = makeModel()
        menus.seed(commands)
        model.query = "trash"
        let close = await model.runSelected()
        #expect(!close)
        #expect(model.runError == CommandRunError.disabled.message)
    }

    @Test func aFailingRunnerKeepsThePaletteOpenWithTheError() async {
        let (model, menus) = makeModel(run: { _ in .failure(.unavailable) })
        menus.seed(commands)
        model.query = "copy"
        let close = await model.runSelected()
        #expect(!close)
        #expect(model.runError == CommandRunError.unavailable.message)
        model.prepareForOpen()
        #expect(model.runError == nil)
    }

    @Test func runningWithNothingSelectedDoesNothing() async {
        let (model, menus) = makeModel()
        menus.seed(commands)
        model.query = "zzzz"
        #expect(await model.runSelected() == false)
    }
}
