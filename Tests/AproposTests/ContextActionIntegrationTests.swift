import Foundation
import Testing

@testable import Apropos

@MainActor
@Suite("Context actions in the palette")
struct ContextActionIntegrationTests {
    private let app = TargetApp(pid: 100, bundleID: "com.example.editor", name: "Editor")

    private struct Rig {
        let model: PaletteModel
        let menus: AppMenuModel
        let center: ContextActionCenter
        let recorder: ServiceRecorder
        let tracker: FrontmostAppTracker
    }

    private func rig(target: TargetApp?) -> Rig {
        let tracker = FrontmostAppTracker(ownBundleID: "test")
        if let target { tracker.pin(target) }
        let menus = AppMenuModel(tracker: tracker, permission: AccessibilityPermission(probe: { true }))
        let model = PaletteModel(menus: menus, tracker: tracker)
        let recorder = ServiceRecorder()
        let library = ActionPackLibrary.bundled()
        let center = ContextActionCenter(
            library: library, engine: ActionEngine(functions: library.functions, services: recorder.services))
        center.attach(to: model)
        menus.seed(MenuCommandMapper.commands(from: Fixtures.menuBar(), bundleID: target?.bundleID))
        return Rig(model: model, menus: menus, center: center, recorder: recorder, tracker: tracker)
    }

    private func snapshot(
        _ values: ContextValues, pid: pid_t = 100, at date: Date = Date()
    ) -> ContextSnapshot {
        ContextSnapshot(appName: "Editor", bundleID: "com.example.editor", pid: pid, capturedAt: date, values: values)
    }

    @Test func actionsBecomeCommandsUnderTheirGroup() {
        let rig = rig(target: app)
        rig.center.update(with: snapshot(ContextValues(selectedText: "hello world")))
        let upper = rig.center.commands.first { $0.id == "ctx:text.upper" }
        #expect(upper?.path == ["Selected text"])
        #expect(upper?.stableID.rawValue == "ctx:text.upper")
        #expect(upper?.stableID.bundleID == nil)
        #expect(upper?.symbolName == "textformat.size.larger")
        #expect(upper?.detail == "Change the selection to capital letters")
        #expect(Set(rig.center.commands.map { $0.path.first ?? "" }) == ["Selected text"])
    }

    @Test func contextCommandsComeBeforeMenuCommandsAndOnlyForTheTargetApp() {
        let rig = rig(target: app)
        let menuCount = rig.model.results.count
        rig.center.update(with: snapshot(ContextValues(selectedText: "hello")))
        let results = rig.model.results
        #expect(results.count == menuCount + rig.center.commands.count)
        #expect(results.first?.command.id == rig.center.commands.first?.id)

        // Another app in front: the first app's selection offers nothing.
        rig.tracker.pin(TargetApp(pid: 200, bundleID: "com.example.other", name: "Other"))
        #expect(rig.model.results.count == menuCount)
    }

    @Test func clearRemovesTheActions() {
        let rig = rig(target: app)
        let menuCount = rig.model.results.count
        rig.center.update(with: snapshot(ContextValues(selectedText: "hello")))
        rig.center.clear()
        #expect(rig.center.commands.isEmpty)
        #expect(rig.model.results.count == menuCount)
    }

    @Test func openingThePanelDropsLastTimesActionsUntilAFreshSnapshotArrives() {
        let rig = rig(target: app)
        let menuCount = rig.model.results.count
        let first = Date()
        rig.center.update(with: snapshot(ContextValues(selectedText: "old"), at: first))
        #expect(rig.model.results.count > menuCount)
        rig.model.prepareForOpen()
        #expect(rig.model.results.count == menuCount)
        rig.center.update(with: snapshot(ContextValues(selectedText: "new"), at: first.addingTimeInterval(1)))
        #expect(rig.model.results.count > menuCount)
    }

    @Test func aSlowOlderSnapshotCannotBringBackGoneActions() {
        let rig = rig(target: app)
        let now = Date()
        rig.center.update(with: snapshot(ContextValues(), at: now))
        rig.center.update(with: snapshot(ContextValues(selectedText: "late"), at: now.addingTimeInterval(-5)))
        #expect(rig.center.commands.isEmpty)
    }

    @Test func searchFindsActionsByTitleAndKeyword() {
        let rig = rig(target: app)
        rig.center.update(with: snapshot(ContextValues(selectedText: "hello")))
        rig.model.query = "snake"
        #expect(rig.model.results.first?.command.id == "ctx:text.snake")
        rig.model.query = "checksum"  // a files keyword; no files selected
        #expect(rig.model.results.first?.command.id != "ctx:files.sha256")
        rig.model.query = "dedupe"
        #expect(rig.model.results.isEmpty)  // needs multiline text
        rig.center.update(with: snapshot(ContextValues(selectedText: "a\na")))
        #expect(rig.model.results.first?.command.id == "ctx:text.unique-lines")
    }

    @Test func runningAContextActionUsesTheEngineAndKeepsTheOutcome() async {
        let rig = rig(target: app)
        rig.model.prepareForOpen()
        rig.center.update(with: snapshot(ContextValues(selectedText: "hello world")))
        rig.model.query = "uppercase"
        let closed = await rig.model.runSelected()
        #expect(closed)
        #expect(rig.recorder.replaced.first?.0 == "HELLO WORLD")
        #expect(rig.recorder.replaced.first?.1 == 100)
        #expect(rig.model.lastOutcome?.delivery == .replaced)
        #expect(rig.model.runError == nil)
    }

    @Test func failuresShowAMessageWithoutTheInput() async {
        let rig = rig(target: app)
        rig.center.update(with: snapshot(ContextValues(selectedText: "***")))
        rig.model.query = "base64 decode"
        let closed = await rig.model.runSelected()
        #expect(!closed)
        #expect(rig.model.runError == ActionError.invalidInput.message)
        #expect(!(rig.model.runError ?? "").contains("***"))
    }

    @Test func menuCommandsStillRunThroughTheMenuRunner() async {
        let rig = rig(target: app)
        rig.center.update(with: snapshot(ContextValues(selectedText: "x")))
        let menuCommand = rig.model.results.first { $0.command.source != .contextAction("ctx:text.upper") && !$0.command.id.hasPrefix("ctx:") }
        #expect(menuCommand != nil)
        rig.model.setRunner { _ in .success(()) }
        if let command = menuCommand?.command { #expect(await rig.model.run(command)) }
    }

    @Test func confirmationIsAskedBeforeADestructiveActionRuns() async {
        let json = """
            {"schemaVersion":1,"actions":[{"id":"user:wipe","title":"Wipe","symbol":"trash","requires":["selectedText"],
            "backend":{"type":"function","name":"text.upper"},"output":"clipboard","confirm":true}]}
            """
        var library = ActionPackLibrary.bundled()
        library.add(packData: Data(json.utf8), source: "t.json")
        let rig = rig(target: app)
        let center = ContextActionCenter(
            library: library, engine: ActionEngine(functions: library.functions, services: rig.recorder.services))
        center.attach(to: rig.model)
        center.update(with: snapshot(ContextValues(selectedText: "abc")))
        guard let wipe = center.commands.first(where: { $0.id == "user:wipe" }) else {
            Issue.record("missing action")
            return
        }
        #expect(wipe.needsConfirmation)
        #expect(await rig.model.run(wipe) == false)
        #expect(rig.model.pendingConfirmation?.id == "user:wipe")
        #expect(rig.recorder.clipboard.isEmpty)
        #expect(await rig.model.confirmPending())
        #expect(rig.recorder.clipboard == ["ABC"])
        #expect(rig.model.pendingConfirmation == nil)

        #expect(await rig.model.run(wipe) == false)
        rig.model.cancelPending()
        #expect(rig.model.pendingConfirmation == nil)
    }

    @Test func suggestionsRankContextActionsThroughUsageAndNeverStoreInputs() throws {
        let rig = rig(target: app)
        rig.center.update(with: snapshot(ContextValues(selectedText: "TOPSECRET text")))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("u-\(UUID().uuidString)/usage.json")
        let store = UsageStore(url: url, writeDelay: .zero)
        guard let upper = rig.center.commands.first(where: { $0.id == "ctx:text.upper" }) else { return }
        for _ in 0..<5 { store.recordRun(of: upper) }
        rig.model.setRanker(CommandRanker(signal: store.rankingSignal()))
        let groups = rig.model.leadingGroups
        #expect(groups.suggested == 1)
        #expect(rig.model.results[groups.pinned].command.id == "ctx:text.upper")

        let stored = try String(contentsOf: url, encoding: .utf8)
        #expect(stored.contains("ctx:text.upper"))
        #expect(!stored.contains("TOPSECRET"))
    }

    @Test func rowSymbolsComeFromTheActionAndStayDistinct() {
        let rig = rig(target: app)
        rig.center.update(with: snapshot(ContextValues(selectedText: "a\nb")))
        let resolver = SymbolResolver()
        let symbols = resolver.symbols(for: rig.center.commands)
        #expect(symbols.first == "textformat.size.larger")
        for pair in zip(symbols, symbols.dropFirst()) { #expect(pair.0 != pair.1) }
    }

    @Test func serviceHookReceivesTheSnapshotAndUnreadableAppsGetNone() async {
        final class Box: @unchecked Sendable {
            var snapshots: [ContextSnapshot] = []
        }
        let box = Box()
        var service = ContextService(isTrusted: { false }, makeRoot: { _ in nil })
        service.onSnapshot = { box.snapshots.append($0) }
        let result = await service.snapshot(for: app)
        #expect(box.snapshots.count == 1)
        #expect(result.values.isEmpty && result.gaps == [.notTrusted])
    }
}
