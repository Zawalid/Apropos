import Foundation
import Testing

@testable import Apropos

private let fixtureApp = TargetApp(pid: 100, bundleID: StepFixtures.app, name: "Fixture")

private func stepsAction(
    _ backend: UIStepsBackend, apps: AppFilter = AppFilter(include: [StepFixtures.app]), timeout: TimeInterval = 20
) -> ContextAction {
    ContextAction(
        id: "user:steps.test", title: "Export", symbol: "doc", requires: [], apps: apps, backend: .uiSteps(backend),
        output: .none, timeout: timeout)
}

@Suite("uiSteps in the action engine")
struct StepEngineTests {
    let environment = StepFakeEnvironment()

    private func engine(trusted: Bool = true) -> ActionEngine {
        environment.trusted = trusted
        environment.install(FakeTree.app(menus: FakeTree.fixtureMenus()), bundleID: StepFixtures.app)
        var services = ServiceRecorder().services
        services.uiSteps = .replaying(
            with: StepReplayer(environment: environment, warm: WarmApps(), log: .silent))
        return ActionEngine(functions: ActionFunctionRegistry(), services: services)
    }

    @Test func runsTheStepsAndReportsDone() async throws {
        let engine = engine()
        let action = stepsAction(StepFixtures.backend(StepFixtures.exportPDF))
        let outcome = try await engine.run(action, values: ContextValues(), target: fixtureApp).get()
        #expect(outcome.delivery == .done)
        #expect(environment.pressed == ["menu.export"])
    }

    @Test func aFailedStepSurfacesAsAStructuredError() async {
        let engine = engine()
        let step = StepFixtures.step(locators: [.identifier("missing")], wait: StepWait(timeout: 0.5))
        let action = stepsAction(StepFixtures.backend(StepFixtures.exportPDF, step))
        let result = await engine.run(action, values: ContextValues(), target: fixtureApp)
        guard case .failure(let error) = result else {
            Issue.record("expected a failure")
            return
        }
        #expect(error == .uiStepFailed(StepFailure(step: 2, reason: .notFound)))
        #expect(error.message == "Step 2 stopped: the item was not found.")
        #expect(environment.pressed == ["menu.export"])
    }

    @Test func permissionMissingIsReported() async {
        let engine = engine(trusted: false)
        let action = stepsAction(StepFixtures.backend(StepFixtures.exportPDF))
        let result = await engine.run(action, values: ContextValues(), target: fixtureApp)
        #expect(result == .failure(.uiStepFailed(StepFailure(step: 1, reason: .permissionMissing))))
        #expect(environment.pressed.isEmpty)
    }

    @Test func theAppFilterStillApplies() async {
        let engine = engine()
        let other = TargetApp(pid: 5, bundleID: "com.example.other", name: "Other")
        let action = stepsAction(StepFixtures.backend(StepFixtures.exportPDF))
        let result = await engine.run(action, values: ContextValues(), target: other)
        #expect(result == .failure(.notApplicable))
        #expect(environment.pressed.isEmpty)
    }
}

@Suite("uiSteps in packs and user commands")
struct StepPackTests {
    private let json = """
        {"schemaVersion": 1, "name": "t", "actions": [{
          "id": "user:export", "title": "Export", "symbol": "doc", "requires": [],
          "apps": {"include": ["com.example.fixture"], "exclude": []},
          "backend": {"type": "uiSteps", "version": 1, "steps": [
            {"action": "menu", "app": "com.example.fixture", "description": "Choose Export as PDF",
             "locators": [{"by": "identifier", "value": "menu.export"},
                          {"by": "shortcut", "key": "E", "modifiers": ["command"]}]}]},
          "output": "none", "timeout": 20}]}
        """

    @Test func aPackWithUIStepsLoadsAndRoundTrips() throws {
        var library = ActionPackLibrary()
        library.add(packData: Data(json.utf8), source: "t.json")
        #expect(library.issues.isEmpty)
        let action = try #require(library.action(for: "user:export"))
        guard case .uiSteps(let backend) = action.backend else {
            Issue.record("expected uiSteps")
            return
        }
        #expect(backend.steps.count == 1 && backend.steps[0].id == "s1")
        #expect(backend.fragility == .sturdy)

        let encoded = try JSONEncoder().encode(ActionDefinition(action))
        let again = try JSONDecoder().decode(ActionDefinition.self, from: encoded).makeAction()
        #expect(again == action)
    }

    @Test func aPackWithARefusedStepIsSkippedWithAReason() {
        let bad = json.replacingOccurrences(
            of: #"{"by": "identifier", "value": "menu.export"}"#,
            with: #"{"by": "menuPath", "titles": ["Apple", "Log Out"]}"#)
        var library = ActionPackLibrary()
        library.add(packData: Data(bad.utf8), source: "t.json")
        #expect(library.actions.isEmpty)
        #expect(library.issues.first?.reason.contains("Apple menu") == true)
    }

    @Test func aCoordinateLocatorMakesThePackEntryRefused() {
        let bad = json.replacingOccurrences(
            of: #"{"by": "identifier", "value": "menu.export"}"#, with: #"{"by": "click", "x": 10, "y": 20}"#)
        var library = ActionPackLibrary()
        library.add(packData: Data(bad.utf8), source: "t.json")
        #expect(library.actions.isEmpty)
        #expect(library.issues.first?.reason.contains("position on the screen") == true)
    }

    @MainActor
    @Test func aUserCommandWithStepsIsStoredAndListedLikeAnyOther() throws {
        let directory = tempCommandsDirectory()
        let store = UserCommandStore(directory: directory)
        let draft = UserCommand(
            title: "Export as PDF", symbol: "doc", apps: AppFilter(include: [StepFixtures.app]), requires: [],
            backend: .uiSteps(StepFixtures.backend(StepFixtures.exportPDF)), output: .none, timeout: 20)
        let made = try store.create(draft)
        #expect(UserCommandStore(directory: directory).command(withID: made.id) == made)
        #expect(made.action.group == .yourCommands)
        #expect(made.action.applies(to: ContextValues(), bundleID: StepFixtures.app))
        #expect(!made.action.applies(to: ContextValues(), bundleID: "com.example.other"))
    }

    @MainActor
    @Test func theStoreRefusesInvalidSteps() {
        let store = UserCommandStore(directory: tempCommandsDirectory())
        let apple = StepFixtures.step(locators: [.menuPath(["Apple", "Log Out"])])
        let draft = UserCommand(
            title: "Bad", apps: AppFilter(include: [StepFixtures.app]), backend: .uiSteps(StepFixtures.backend(apple)),
            output: .none, timeout: 20)
        #expect(throws: UserCommandError.invalid(.invalidSteps(.appleMenu(step: 1)))) { try store.create(draft) }
    }

    @Test func anImportedStepCommandWaitsForApprovalAndIsDescribedFromItsLocators() throws {
        let original = UserCommand(
            title: "Export", apps: AppFilter(include: [StepFixtures.app]),
            backend: .uiSteps(StepFixtures.backend(StepFixtures.exportPDF)), output: .none, timeout: 20)
        let data = try CommandExchange.export([original])
        let review = try CommandExchange.review(data, existing: [])
        let item = try #require(review.items.first)
        #expect(item.needsApproval && item.command.review == .pending)
        #expect(item.risks == [.controlsApps])
        #expect(item.summary.joined(separator: "\n").contains("File > Export as PDF"))
        #expect(item.command.backend == original.backend)
    }

    @Test func theSummaryDescribesTheStepsAndTheirReliability() {
        let command = UserCommand(
            title: "Export", apps: AppFilter(include: [StepFixtures.app]),
            backend: .uiSteps(StepFixtures.backend(StepFixtures.exportPDF)), output: .none)
        #expect(CommandSummary.risks(for: command) == [.controlsApps])
        let lines = CommandSummary.lines(for: command).joined(separator: "\n")
        #expect(lines.contains("Runs 1 step") && lines.contains("Reliability: Sturdy"))
        #expect(CommandRisk.controlsApps.needsApproval)
    }
}
