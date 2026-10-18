import AppKit
import Foundation
import Testing

@testable import Apropos

@Suite("Step authoring")
struct StepAuthoringTests {
    private let bundle = "com.example.fixture"

    private func commands() -> [Command] {
        let bar: [MenuItemSnapshot] = [
            MenuItemSnapshot(title: "Apple", children: [MenuItemSnapshot(title: "About This Mac")]),
            MenuItemSnapshot(
                title: "File",
                children: [
                    MenuItemSnapshot(title: "Save", cmdChar: "s"),
                    MenuItemSnapshot(title: "Export as PDF", cmdChar: "e", cmdModifiers: 1),
                    MenuItemSnapshot(
                        title: "Open Recent", children: [MenuItemSnapshot(title: "Quarterly-Report.numbers")]),
                ]),
        ]
        return MenuCommandMapper.commands(from: bar, bundleID: bundle)
    }

    private func command(_ title: String) throws -> Command {
        try #require(commands().first { $0.title == title })
    }

    @Test func aMenuCommandBecomesAStepWithPathShortcutAndTitle() throws {
        var sequence = StepSequenceBuilder()
        let step = try sequence.addMenuCommand(command("Export as PDF"), appName: "Fixture", identifier: "menu.export")
        #expect(step.app == bundle && step.action == .menu && step.id == "s1")
        #expect(step.description == "Choose File > Export as PDF in Fixture")
        #expect(
            step.locators == [
                .identifier("menu.export"), .roleTitle(role: "AXMenuItem", title: "Export as PDF"),
                .menuPath(["File", "Export as PDF"]), .shortcut(key: "E", modifiers: [.command, .shift]),
            ])
        #expect(step.fragility == .sturdy)
    }

    @Test func withoutAnIdentifierOrShortcutTheStepIsFair() throws {
        var sequence = StepSequenceBuilder()
        let step = try sequence.addMenuCommand(command("Export as PDF").withoutShortcut())
        #expect(step.fragility == .fair)
    }

    @Test func positionIsOnlyAddedOnRequest() throws {
        var sequence = StepSequenceBuilder()
        let plain = try sequence.addMenuCommand(command("Save"))
        #expect(!plain.locators.contains { $0.kind == .position })
        let with = try sequence.addMenuCommand(command("Save"), includePosition: true)
        #expect(with.locators.last == .position([1, 0]))
        #expect(with.id == "s2")
    }

    @Test func recentItemsAreRefusedWhenAdding() throws {
        var sequence = StepSequenceBuilder()
        let recent = try #require(commands().first { $0.title == "Quarterly-Report.numbers" })
        #expect(throws: StepAuthoringError.refused(.recentItems(step: 1))) { try sequence.addMenuCommand(recent) }
        #expect(sequence.steps.isEmpty)
    }

    @Test func theAppOnThePrivacyListIsRefusedWhenAdding() throws {
        var sequence = StepSequenceBuilder()
        let privacy = ContextPrivacy(disabledBundleIDs: [bundle])
        #expect(throws: StepAuthoringError.refused(.appNotAllowed(step: 1))) {
            try sequence.addMenuCommand(command("Save"), privacy: privacy)
        }
    }

    @Test func contextActionsAreNotMenuCommands() {
        var sequence = StepSequenceBuilder()
        let other = Command(id: "x", title: "Upper", path: [], source: .contextAction("ctx:text.upper"))
        #expect(throws: StepAuthoringError.notAMenuCommand) { try sequence.addMenuCommand(other) }
        let noApp = Command(id: "1.0", title: "Save", path: ["File"], source: .menuItem(bundleID: nil))
        #expect(throws: StepAuthoringError.notAMenuCommand) { try sequence.addMenuCommand(noApp) }
    }

    @Test func assemblingEditingAndTheFragilityOfTheWhole() throws {
        var sequence = StepSequenceBuilder()
        try sequence.addMenuCommand(command("Save"))
        try sequence.addMenuCommand(command("Export as PDF"))
        try sequence.move(from: 1, to: 0)
        #expect(sequence.steps.map(\.id) == ["s2", "s1"])
        try sequence.setWait(8, at: 0)
        #expect(sequence.steps[0].waitTimeout == 8)
        try sequence.remove(at: 1)
        #expect(sequence.steps.count == 1)
        #expect(throws: StepAuthoringError.noSuchStep) { try sequence.remove(at: 5) }
        sequence.append(StepFixtures.step("s2", locators: [.position([1, 1])]))
        #expect(sequence.steps.last?.id != "s2" || sequence.steps.filter { $0.id == "s2" }.count == 1)
        #expect(sequence.fragility == .fragile)
    }

    @Test func anEmptySequenceCannotBecomeACommand() {
        #expect(throws: StepAuthoringError.noSteps) { try StepSequenceBuilder().makeCommand(title: "Nothing") }
    }

    @Test func theCommandIsBoundToItsAppsAndNeedsNoContext() throws {
        var sequence = StepSequenceBuilder()
        try sequence.addMenuCommand(command("Save"))
        let made = try sequence.makeCommand(title: "Save it", aliases: ["sv"])
        #expect(made.apps == AppFilter(include: [bundle]))
        #expect(made.requires.isEmpty && made.output == .none)
        #expect(made.timeout == StepSequenceBuilder.suggestedTimeout(forSteps: 1))
        #expect(made.stepFragility == .sturdy)
        #expect(made.action.stepFragility == .sturdy)
    }

    @MainActor
    @Test func savingGoesThroughTheStoreAndSurvivesReload() throws {
        let directory = tempCommandsDirectory()
        let store = UserCommandStore(directory: directory)
        var sequence = StepSequenceBuilder()
        try sequence.addMenuCommand(command("Save"))
        try sequence.addMenuCommand(command("Export as PDF"), identifier: "menu.export")
        let saved = try sequence.save(title: "Save and export", in: store)
        let reloaded = UserCommandStore(directory: directory)
        #expect(reloaded.issues.isEmpty)
        #expect(reloaded.command(withID: saved.id)?.backend.steps?.steps.count == 2)
        #expect(reloaded.runnable.map(\.id).contains(saved.id))
        #expect(reloaded.command(withID: saved.id)?.stepFragility == .sturdy)
    }

    @MainActor
    @Test func savingARefusedSequenceStoresNothing() throws {
        let directory = tempCommandsDirectory()
        let store = UserCommandStore(directory: directory)
        var sequence = StepSequenceBuilder()
        sequence.append(StepFixtures.step(locators: [.menuPath(["Apple", "Log Out"])]))
        #expect(throws: StepAuthoringError.refused(.appleMenu(step: 1))) {
            try sequence.save(title: "Bad", in: store)
        }
        #expect(store.commands.isEmpty)
    }

    @Test func theSymbolExists() {
        #expect(NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: nil) != nil)
    }

    @Test func theHandEditingJSONRoundTripsAndLoadsFromEveryFileShape() throws {
        var sequence = StepSequenceBuilder()
        try sequence.addMenuCommand(command("Export as PDF"), identifier: "menu.export")
        let json = try sequence.json()
        #expect(json.contains("\"by\" : \"identifier\"") && json.contains("\"action\" : \"menu\""))
        #expect(try UIStepsFile.load(Data(json.utf8)) == sequence.backend)

        let commandFile =
            #"{"schemaVersion":1,"command":{"id":"user:x","backend":{"type":"uiSteps","steps":"# + stepsArray(json)
            + "}}}"
        #expect(try UIStepsFile.load(Data(commandFile.utf8)) == sequence.backend)
        let pack =
            #"{"schemaVersion":1,"actions":[{"id":"user:y","backend":{"type":"function","name":"t"}},{"id":"user:x","backend":{"type":"uiSteps","steps":"#
            + stepsArray(json) + "}}]}"
        #expect(try UIStepsFile.load(Data(pack.utf8)) == sequence.backend)
        #expect(throws: UIStepsFile.LoadError.noSteps) { try UIStepsFile.load(Data(#"{"command":{"id":"a"}}"#.utf8)) }
        #expect(throws: UIStepsFile.LoadError.notJSON) { try UIStepsFile.load(Data("nope".utf8)) }
    }

    private func stepsArray(_ backendJSON: String) -> String {
        guard let data = backendJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let steps = object["steps"], let out = try? JSONSerialization.data(withJSONObject: steps)
        else { return "[]" }
        return String(decoding: out, as: UTF8.self)
    }

    @Test func theSummaryComesFromTheLocatorsNotTheDescription() throws {
        let lying = UIStep(
            id: "s1", app: bundle, locators: [.menuPath(["File", "Delete Everything"])], description: "Choose Copy")
        let command = UserCommand(
            title: "x", apps: AppFilter(include: [bundle]), backend: .uiSteps(UIStepsBackend(steps: [lying])),
            output: .none)
        let text = CommandSummary.lines(for: command).joined(separator: "\n")
        #expect(text.contains("File > Delete Everything") && !text.contains("Choose Copy"))
    }
}

extension Command {
    fileprivate func withoutShortcut() -> Command {
        Command(id: id, title: title, path: path, shortcut: nil, source: source)
    }
}
