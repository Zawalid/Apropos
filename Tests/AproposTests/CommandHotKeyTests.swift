import Foundation
import Testing

@testable import Apropos

@MainActor
final class FakeBinding: HotKeyBinding {
    static var refusing: Set<HotKeyCombo> = []
    static var live: [ObjectIdentifier: HotKeyCombo] = [:]
    let handler: @MainActor () -> Void
    init(handler: @escaping @MainActor () -> Void) { self.handler = handler }
    func register(_ combo: HotKeyCombo) -> Bool {
        if Self.refusing.contains(combo) { return false }
        Self.live[ObjectIdentifier(self)] = combo
        return true
    }
    func unregister() { Self.live[ObjectIdentifier(self)] = nil }
}

private let keyA = HotKeyCombo(keyCode: 0, modifiers: [.control, .option])
private let keyB = HotKeyCombo(keyCode: 11, modifiers: [.control, .option])
private let panelKey = HotKeyCombo(keyCode: 49, modifiers: [.option])

@MainActor
@Suite("CommandHotKeyManager", .serialized)
struct CommandHotKeyTests {
    private func manager() -> CommandHotKeyManager {
        FakeBinding.live = [:]
        FakeBinding.refusing = []
        return CommandHotKeyManager { FakeBinding(handler: $0) }
    }

    private var registered: Set<HotKeyCombo> { Set(FakeBinding.live.values) }

    @Test func registersApprovedCommandsWithAShortcutOnly() {
        let manager = manager()
        let a = shoutCommand(title: "A", hotkey: keyA)
        let none = shoutCommand(title: "None")
        let pending = shoutCommand(title: "Pending", review: .pending, hotkey: keyB)
        manager.sync([a, none, pending], reserved: [panelKey]) { _ in }
        #expect(registered == [keyA])
        #expect(manager.registeredIDs == [a.id])
        #expect(manager.failures.isEmpty)
    }

    @Test func deletingEditingOrApprovingChangesTheRegistrations() {
        let manager = manager()
        var a = shoutCommand(title: "A", hotkey: keyA)
        manager.sync([a], reserved: []) { _ in }
        #expect(registered == [keyA])

        a.hotkey = keyB
        manager.sync([a], reserved: []) { _ in }
        #expect(registered == [keyB])

        manager.sync([], reserved: []) { _ in }
        #expect(registered.isEmpty && manager.registeredIDs.isEmpty)

        var pending = shoutCommand(title: "P", review: .pending, hotkey: keyA)
        manager.sync([pending], reserved: []) { _ in }
        #expect(registered.isEmpty)
        pending.review = .approved
        manager.sync([pending], reserved: []) { _ in }
        #expect(registered == [keyA])
    }

    @Test func conflictsAreReportedNotRegistered() {
        let manager = manager()
        let onPanel = shoutCommand(title: "OnPanel", hotkey: panelKey)
        let first = shoutCommand(title: "First", hotkey: keyA)
        let second = shoutCommand(title: "Second", hotkey: keyA)
        manager.sync([onPanel, first, second], reserved: [panelKey]) { _ in }
        #expect(manager.failures[onPanel.id] == .panel)
        #expect(manager.failures.count == 2)
        #expect(registered == [keyA])
        #expect(manager.registeredIDs.count == 1)
    }

    @Test func systemRefusalIsReportedAndRetriedOnTheNextSync() {
        let manager = manager()
        let a = shoutCommand(title: "A", hotkey: keyA)
        FakeBinding.refusing = [keyA]
        manager.sync([a], reserved: []) { _ in }
        #expect(manager.failures[a.id] == .refusedBySystem && registered.isEmpty)
        FakeBinding.refusing = []
        manager.sync([a], reserved: []) { _ in }
        #expect(manager.failures.isEmpty && registered == [keyA])
    }

    @Test func panelShortcutChangingFreesTheCommandThatNowClashes() {
        let manager = manager()
        let a = shoutCommand(title: "A", hotkey: keyA)
        manager.sync([a], reserved: [panelKey]) { _ in }
        #expect(registered == [keyA])
        manager.sync([a], reserved: [keyA]) { _ in }
        #expect(manager.failures[a.id] == .panel)
    }

    @Test func pausingReleasesEverythingAndResumingBringsItBack() {
        let manager = manager()
        manager.sync([shoutCommand(hotkey: keyA)], reserved: []) { _ in }
        manager.setPaused(true)
        #expect(registered.isEmpty)
        manager.setPaused(false)
        #expect(registered == [keyA])
        manager.unregisterAll()
        #expect(registered.isEmpty)
    }

    @Test func pressingTheKeyRunsTheCurrentCommand() {
        FakeBinding.live = [:]
        var made: [FakeBinding] = []
        let manager = CommandHotKeyManager {
            let binding = FakeBinding(handler: $0)
            made.append(binding)
            return binding
        }
        var ran: [String] = []
        var command = shoutCommand(title: "Old", hotkey: keyA)
        manager.sync([command], reserved: []) { ran.append($0.title) }
        command.title = "New"
        manager.sync([command], reserved: []) { ran.append($0.title) }
        made.first?.handler()
        #expect(ran == ["New"])
        manager.sync([], reserved: []) { ran.append($0.title) }
        made.first?.handler()
        #expect(ran == ["New"])
    }

    @Test func runningWithoutThePanelUsesLiveContextAndNotifiesOnFailure() async {
        let recorder = ServiceRecorder()
        let library = ActionPackLibrary.bundled()
        let center = ContextActionCenter(
            library: library, engine: ActionEngine(functions: library.functions, services: recorder.services))
        // Not trusted: no context is read, so a command that needs a selection fails with a notification.
        let sensing = ContextService(isTrusted: { false }, makeRoot: { _ in nil })
        let app = TargetApp(pid: 5, bundleID: "x", name: "X")
        let result = await center.runWithLiveContext(shoutCommand(), target: app, sensing: sensing)
        #expect(result == .failure(.missingContext(.selectedText)))
        #expect(recorder.notices == [ActionError.missingContext(.selectedText).message])

        let open = UserCommand(title: "Open", backend: .urlScheme(try! ActionTemplate("https://example.com")), output: .none)
        let opened = await center.runWithLiveContext(open, target: app, sensing: sensing)
        #expect((try? opened.get().delivery) == ActionDelivery.done)
        #expect(recorder.opened.count == 1)

        var wipe = shoutCommand(requires: [])
        wipe.needsConfirmation = true
        wipe.backend = .urlScheme(try! ActionTemplate("https://example.com"))
        wipe.output = .none
        #expect(await center.runWithLiveContext(wipe, target: app, sensing: sensing) == .failure(.confirmationRequired))
        #expect(recorder.opened.count == 1)
        let confirmed = await center.runWithLiveContext(wipe, target: app, sensing: sensing, confirm: { _ in true })
        #expect((try? confirmed.get().delivery) == ActionDelivery.done)
        #expect(recorder.opened.count == 2)
    }

    @Test func pendingCommandsNeverRunEvenIfAskedDirectly() async {
        let recorder = ServiceRecorder()
        let center = ContextActionCenter(
            library: .bundled(), engine: ActionEngine(services: recorder.services))
        let result = await center.run(
            shoutCommand(review: .pending), values: ContextValues(selectedText: "x"), target: nil)
        #expect(result == .failure(.notApplicable))
        #expect(recorder.clipboard.isEmpty)
    }
}
