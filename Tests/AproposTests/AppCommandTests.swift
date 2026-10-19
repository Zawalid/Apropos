import Foundation
import Testing

@testable import Apropos

@MainActor
@Suite("Apropos rows and your commands in the panel")
struct AppCommandTests {
    private let app = TargetApp(pid: 100, bundleID: "com.example.editor", name: "Editor")

    private struct Rig {
        let model: PaletteModel
        let center: ContextActionCenter
        var opened: [AppCommand] = []
    }

    private final class Log: @unchecked Sendable {
        var opened: [AppCommand] = []
        var actions: [UserCommandAction] = []
    }

    private func rig(log: Log, outcome: UserCommandOutcome = .done(note: nil)) -> Rig {
        let tracker = FrontmostAppTracker(ownBundleID: "test")
        tracker.pin(app)
        let menus = AppMenuModel(tracker: tracker, permission: AccessibilityPermission(probe: { true }))
        let model = PaletteModel(menus: menus, tracker: tracker)
        let library = ActionPackLibrary.bundled()
        let center = ContextActionCenter(
            library: library, engine: ActionEngine(functions: library.functions, services: ServiceRecorder().services))
        center.attach(to: model)
        menus.seed(MenuCommandMapper.commands(from: Fixtures.menuBar(), bundleID: app.bundleID))
        model.setAppCommandHandler { log.opened.append($0) }
        model.setUserCommandHandler { action in
            log.actions.append(action)
            return outcome
        }
        let mine = UserCommand(id: "user:shout", title: "Shout", backend: .function("text.upper"))
        center.setUserCommands([mine])
        center.update(
            with: ContextSnapshot(
                appName: "Editor", bundleID: app.bundleID, pid: 100, capturedAt: Date(),
                values: ContextValues(selectedText: "hello")))
        return Rig(model: model, center: center)
    }

    // MARK: Rows of Apropos

    @Test func theRowsAreNeverInTheEmptyList() {
        let rig = rig(log: Log())
        #expect(!rig.model.results.contains { if case .app = $0.command.source { true } else { false } })
    }

    @Test func theyAreFoundByNameAndByKeyword() {
        let rig = rig(log: Log())
        for query in ["new comm", "create", "your comm", "manage"] {
            rig.model.query = query
            let found = rig.model.results.compactMap { row -> AppCommand? in
                if case .app(let app) = row.command.source { app } else { nil }
            }
            #expect(!found.isEmpty, "nothing for \(query)")
        }
        rig.model.query = "new command"
        #expect(rig.model.results.first?.command.title == "New command")
        #expect(rig.model.results.first?.command.path == ["Apropos"])
    }

    @Test func aQueryThatDoesNotMatchThemShowsNone() {
        let rig = rig(log: Log())
        rig.model.query = "select all"
        #expect(!rig.model.results.contains { if case .app = $0.command.source { true } else { false } })
    }

    @Test func runningARowAsksTheAppToOpenItAndClosesThePanel() async throws {
        let log = Log()
        let rig = rig(log: log)
        rig.model.query = "new command"
        let row = try #require(rig.model.results.first?.command)
        #expect(await rig.model.run(row))
        #expect(log.opened == [.newCommand])
        rig.model.query = "your commands"
        let list = try #require(rig.model.results.first { $0.command.title == "Your commands" }?.command)
        #expect(await rig.model.run(list))
        #expect(log.opened == [.newCommand, .yourCommands])
    }

    @Test func theRowsCannotBecomeSequenceSteps() async throws {
        let rig = rig(log: Log())
        rig.model.query = "new command"
        let row = try #require(rig.model.results.first?.command)
        guard case .refused = rig.model.addToSequence(row) else {
            Issue.record("expected a refusal")
            return
        }
    }

    // MARK: Your own commands

    private func mine(_ rig: Rig) throws -> Command {
        try #require(rig.center.commands.first { $0.id == "user:shout" })
    }

    @Test func onlyYourOwnCommandsHaveCommandActions() throws {
        let rig = rig(log: Log())
        #expect(PaletteModel.userCommandID(of: try mine(rig)) == "user:shout")
        let builtIn = try #require(rig.center.commands.first { $0.id == "ctx:text.lower" })
        #expect(PaletteModel.userCommandID(of: builtIn) == nil)
    }

    @Test func editClosesThePanelAndDuplicateKeepsItOpenWithANote() throws {
        let log = Log()
        let rig = rig(log: log, outcome: .done(note: "Duplicated as Shout copy"))
        let id = try #require(PaletteModel.userCommandID(of: try mine(rig)))
        #expect(rig.model.perform(.edit(id)))
        #expect(!rig.model.perform(.duplicate(id)))
        #expect(log.actions == [.edit(id), .duplicate(id)])
        #expect(rig.model.note == "Duplicated as Shout copy")
        #expect(rig.model.notice == PaletteNotice(text: "Duplicated as Shout copy", isFailure: false))
    }

    @Test func aFailedActionSaysWhy() throws {
        let rig = rig(log: Log(), outcome: .failed("That command could not be duplicated."))
        let id = try #require(PaletteModel.userCommandID(of: try mine(rig)))
        #expect(!rig.model.perform(.duplicate(id)))
        #expect(rig.model.runError == "That command could not be duplicated.")
    }

    @Test func deleteAsksFirstAndOnlyDeletesOnTheConfirmingReturn() async throws {
        let log = Log()
        let rig = rig(log: log, outcome: .done(note: "Deleted Shout"))
        let command = try mine(rig)
        rig.model.requestDeletion(of: command)
        let pending = try #require(rig.model.pendingDeletion)
        #expect(pending.id == "user:shout" && pending.heading.contains("Shout"))
        #expect(rig.model.hasPendingConfirmation && log.actions.isEmpty)
        // Return confirms.
        #expect(await rig.model.runSelected() == false)
        #expect(log.actions == [.delete("user:shout")])
        #expect(rig.model.pendingDeletion == nil && rig.model.note == "Deleted Shout")
    }

    @Test func escapeOrTypingCancelsTheDelete() throws {
        let log = Log()
        let rig = rig(log: log)
        rig.model.requestDeletion(of: try mine(rig))
        #expect(rig.model.goBack() && rig.model.pendingDeletion == nil)
        rig.model.requestDeletion(of: try mine(rig))
        rig.model.query = "s"
        #expect(rig.model.pendingDeletion == nil && log.actions.isEmpty)
    }

    @Test func aBuiltInActionCannotBeDeleted() throws {
        let rig = rig(log: Log())
        let builtIn = try #require(rig.center.commands.first { $0.id == "ctx:text.lower" })
        rig.model.requestDeletion(of: builtIn)
        #expect(rig.model.pendingDeletion == nil)
    }
}
