import Foundation
import Testing

@testable import Apropos

@MainActor
@Suite("Send to: palette flow")
struct SendToFlowTests {
    private let app = TargetApp(pid: 100, bundleID: "com.example.editor", name: "Editor")

    private struct Rig {
        let model: PaletteModel
        let center: SendToCenter
        let context: ContextActionCenter
        let recorder: SendRecorder
        let tracker: FrontmostAppTracker
        let usage: UsageStore
        let directory: URL
    }

    private func rig(
        installed: Set<String> = ["com.apple.Notes", "com.apple.mail", "com.culturedcode.ThingsMac"],
        target: TargetApp? = nil
    ) -> Rig {
        let target = target ?? app
        let tracker = FrontmostAppTracker(ownBundleID: "test")
        tracker.pin(target)
        let menus = AppMenuModel(tracker: tracker, permission: AccessibilityPermission(probe: { true }))
        let model = PaletteModel(menus: menus, tracker: tracker)
        let recorder = SendRecorder()
        recorder.installed = installed
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "apropos-flow-\(UUID().uuidString)")
        let usage = UsageStore(url: directory.appendingPathComponent("usage.json"), writeDelay: .zero)
        let center = SendToCenter(
            library: .bundled(), services: recorder.services,
            folders: SendFolderStore(url: directory.appendingPathComponent("f.json")))
        center.frecency = { usage.frecency($0) }
        model.attachSend(center)
        let library = ActionPackLibrary.bundled()
        let context = ContextActionCenter(
            library: library, engine: ActionEngine(functions: library.functions, services: ServiceRecorder().services))
        context.attach(to: model)
        menus.seed(MenuCommandMapper.commands(from: Fixtures.menuBar(), bundleID: target.bundleID))
        return Rig(
            model: model, center: center, context: context, recorder: recorder, tracker: tracker, usage: usage,
            directory: directory)
    }

    private func feed(_ rig: Rig, _ values: ContextValues, pid: pid_t = 100) {
        let snapshot = ContextSnapshot(
            appName: "Editor", bundleID: "com.example.editor", pid: pid, capturedAt: Date(), values: values)
        rig.context.update(with: snapshot)
        rig.center.update(with: snapshot)
    }

    private func titles(_ rig: Rig) -> [String] { rig.model.results.map(\.command.title) }

    // MARK: Rows

    @Test func aSelectionOffersAGenericRowInItsGroup() {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "hello world"))
        let results = rig.model.results.map(\.command)
        let generic = results.first { $0.id == "send:text" }
        #expect(generic?.title == "Send selection to...")
        #expect(generic?.path == ["Selected text"])
        #expect(generic?.stableID.rawValue == "send:text")
        // It sits with the other Selected text rows, after the context actions and before the menus.
        let lastContext = results.lastIndex { $0.id.hasPrefix("ctx:") }
        let genericIndex = results.firstIndex { $0.id == "send:text" }
        #expect(genericIndex == (lastContext ?? -1) + 1)
        // Nothing has been used yet, so there are no direct rows.
        #expect(!titles(rig).contains("Send selection to Notes"))
    }

    @Test func noPayloadMeansNoRows() {
        let rig = rig()
        feed(rig, ContextValues())
        #expect(!rig.model.results.contains { $0.command.id.hasPrefix("send:") })
    }

    @Test func eachPayloadKindGetsItsOwnRowInTheMatchingGroup() throws {
        let rig = rig()
        feed(
            rig,
            ContextValues(
                selectedText: "quote",
                selectedFiles: [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")],
                pageURL: URL(string: "https://swift.org"), pageTitle: "Swift"))
        let rows = rig.model.results.map(\.command).filter { $0.id.hasPrefix("send:") }
        let groups = Dictionary(uniqueKeysWithValues: rows.map { ($0.title, $0.path.first ?? "") })
        #expect(
            groups == [
                "Send 2 files to...": "Selected files", "Send selection to...": "Selected text",
                "Send page to...": "This page",
            ])
        // Each row follows the context actions of its own group.
        let all = rig.model.results.map(\.command)
        for row in rows {
            let index = try #require(all.firstIndex { $0.id == row.id })
            #expect(all[index - 1].path == row.path)
        }
    }

    @Test func anotherAppsSelectionOffersNoRows() {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "hello"))
        rig.tracker.pin(TargetApp(pid: 200, bundleID: "com.example.other", name: "Other"))
        #expect(!rig.model.results.contains { $0.command.id.hasPrefix("send:") })
    }

    @Test func rowsComeBackOnlyWithAFreshSnapshotWhenThePanelOpensAgain() {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "hello"))
        rig.model.prepareForOpen()
        #expect(!rig.model.results.contains { $0.command.id.hasPrefix("send:") })
        feed(rig, ContextValues(selectedText: "fresh"))
        #expect(rig.model.results.contains { $0.command.id == "send:text" })
    }

    // MARK: Destination list

    @Test func theGenericRowOpensTheDestinationListInTheSamePanel() async throws {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "hello"))
        rig.model.query = "sel"
        let generic = try #require(rig.model.results.first { $0.command.id == "send:text" }).command
        let closes = await rig.model.run(generic)
        #expect(!closes)
        #expect(rig.model.sendLevel?.title == "Send selection to")
        #expect(rig.model.query == "")
        #expect(rig.model.content == .results)
        // Only destinations whose app is installed, plus the Share menu, in the library's order when none is used.
        #expect(titles(rig) == ["Notes", "Things", "Mail draft", "Share..."])
        #expect(rig.model.results.allSatisfy { $0.command.path == ["Send selection to"] })
        #expect(rig.recorder.processes.isEmpty && rig.recorder.opened.isEmpty)
    }

    @Test func escapeGoesBackOneLevelAndRestoresTheQuery() async throws {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "hello"))
        rig.model.query = "sel"
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:text" }).command)
        #expect(rig.model.sendLevel != nil)
        #expect(rig.model.goBack())
        #expect(rig.model.sendLevel == nil)
        #expect(rig.model.query == "sel")
        // At the top level there is nothing to go back to: the caller closes the panel.
        #expect(!rig.model.goBack())
    }

    @Test func theListIsSearchable() async throws {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "hello"))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:text" }).command)
        rig.model.query = "mai"
        #expect(titles(rig).first == "Mail draft")
        rig.model.query = "zzzz"
        #expect(rig.model.content == .noMatches(query: "zzzz"))
    }

    @Test func notInstalledAppsAreNotListed() async throws {
        let rig = rig(installed: [])
        feed(rig, ContextValues(selectedText: "hello"))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:text" }).command)
        #expect(titles(rig) == ["Share..."])
    }

    @Test func aDestinationThatCannotTakeTheSizeIsListedButDisabled() async throws {
        let rig = rig()
        feed(rig, ContextValues(selectedText: String(repeating: "x", count: 9_000)))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:text" }).command)
        let things = try #require(rig.model.results.first { $0.command.title == "Things" })
        #expect(!things.command.isEnabled)
        #expect(things.command.detail?.contains("Too long") == true)
        #expect(rig.model.results.last?.command.title == "Things")
    }

    // MARK: Ranking by use

    @Test func destinationsAreRankedByUsePerKindAndTheTopOnesGetDirectRows() async throws {
        let rig = rig()
        let notes = CommandID(rawValue: "send:text>dest:notes")
        let mail = CommandID(rawValue: "send:text>dest:mail")
        let things = CommandID(rawValue: "send:text>dest:things")
        for _ in 0..<5 { rig.usage.recordRun(id: mail) }
        for _ in 0..<2 { rig.usage.recordRun(id: notes) }
        rig.usage.recordRun(id: things)
        rig.usage.recordRun(id: CommandID(rawValue: "send:page>dest:things"))
        feed(rig, ContextValues(selectedText: "hello"))
        let direct = rig.model.results.map(\.command).filter { $0.id.hasPrefix("send:text>") }
        #expect(direct.map(\.title) == ["Send selection to Mail draft", "Send selection to Notes"])
        #expect(direct.allSatisfy { $0.path == ["Selected text"] })
        // The list is ordered by use, then the rest in the library's order.
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:text" }).command)
        #expect(titles(rig) == ["Mail draft", "Notes", "Things", "Share..."])
    }

    @Test func useOfOneKindDoesNotRankAnotherKind() {
        let rig = rig()
        for _ in 0..<5 { rig.usage.recordRun(id: CommandID(rawValue: "send:page>dest:mail")) }
        feed(rig, ContextValues(selectedText: "hello"))
        #expect(!rig.model.results.contains { $0.command.id.hasPrefix("send:text>") })
        feed(rig, ContextValues(pageURL: URL(string: "https://swift.org"), pageTitle: "Swift"))
        #expect(rig.model.results.contains { $0.command.id == "send:page>dest:mail" })
    }

    // MARK: Sending

    @Test func choosingADestinationSendsAndTheLoggedRowIsIdsOnly() async throws {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "Buy milk"))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:text" }).command)
        let notes = try #require(rig.model.results.first { $0.command.title == "Notes" }).command
        let closes = await rig.model.run(notes)
        #expect(closes)
        #expect(rig.model.lastSend?.notice == "Sent to Notes")
        #expect(rig.model.sendFailure == nil)
        #expect(rig.recorder.processes.count == 1)
        let recorded = try #require(rig.model.lastSentCommand)
        #expect(recorded.stableID.rawValue == "send:text>dest:notes")
        #expect(PredictionPrivacy.isLoggable(recorded.stableID))
        // Recording it makes the destination a direct row next time.
        rig.usage.recordRun(of: recorded)
        rig.center.refresh()
        rig.model.prepareForOpen()
        feed(rig, ContextValues(selectedText: "again"))
        #expect(titles(rig).contains("Send selection to Notes"))
    }

    @Test func aDirectRowSendsWithoutOpeningTheList() async throws {
        let rig = rig()
        rig.usage.recordRun(id: CommandID(rawValue: "send:text>dest:notes"))
        feed(rig, ContextValues(selectedText: "hello"))
        let direct = try #require(rig.model.results.first { $0.command.title == "Send selection to Notes" }).command
        #expect(await rig.model.run(direct))
        #expect(rig.model.sendLevel == nil)
        #expect(rig.recorder.processes.count == 1)
    }

    @Test func mailShowsAPreviewAndNeedsAConfirmingReturn() async throws {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "Quarterly numbers"))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:text" }).command)
        let mail = try #require(rig.model.results.first { $0.command.title == "Mail draft" }).command
        #expect(mail.needsConfirmation)
        let closes = await rig.model.run(mail)
        #expect(!closes)
        #expect(rig.recorder.processes.isEmpty)
        let pending = try #require(rig.model.sendPending)
        #expect(pending.line == "Open a draft in Mail: \"Quarterly numbers\" (17 characters)")
        #expect(rig.model.hasPendingConfirmation)

        // Escape cancels the confirmation and stays in the list; nothing was sent.
        #expect(rig.model.goBack())
        #expect(rig.model.sendPending == nil)
        #expect(rig.model.sendLevel != nil)
        #expect(rig.recorder.processes.isEmpty)

        // Ask again and confirm.
        #expect(await rig.model.run(mail) == false)
        #expect(await rig.model.confirmPending())
        #expect(rig.recorder.processes.count == 1)
        #expect(rig.model.lastSend?.notice == "Sent to Mail draft")
        #expect(rig.model.sendPending == nil)
    }

    @Test func theShareMenuAlsoNeedsAConfirmingReturn() async throws {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "hello"))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:text" }).command)
        let share = try #require(rig.model.results.first { $0.command.title == "Share..." }).command
        #expect(await rig.model.run(share) == false)
        #expect(rig.recorder.shared.isEmpty)
        #expect(rig.model.sendPending?.line.hasPrefix("Open the Share menu with:") == true)
        #expect(await rig.model.confirmPending())
        #expect(rig.recorder.shared.count == 1)
    }

    @Test func aFailureShowsAMessageAndKeepsThePayloadForARetry() async throws {
        let rig = rig()
        rig.recorder.processStatus = 1
        feed(rig, ContextValues(selectedText: "do not lose me"))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:text" }).command)
        let notes = try #require(rig.model.results.first { $0.command.title == "Notes" }).command
        #expect(await rig.model.run(notes) == false)
        let message = try #require(rig.model.sendFailure)
        #expect(message.hasPrefix("Could not send to Notes."))
        #expect(!message.contains("do not lose me"))
        #expect(rig.model.sendLevel != nil)
        #expect(rig.model.lastSend == nil)
        #expect(rig.model.lastSentCommand == nil)

        rig.recorder.processStatus = 0
        #expect(await rig.model.run(notes))
        #expect(rig.recorder.processes.count == 2)
        let args = try #require(rig.recorder.processes.last).arguments
        #expect(args.contains("do not lose me"))
    }

    @Test func aLinkThatCannotOpenIsAFailureWithTheDestinationName() async throws {
        let rig = rig()
        rig.recorder.openAnswer = false
        feed(rig, ContextValues(selectedText: "hello"))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:text" }).command)
        let things = try #require(rig.model.results.first { $0.command.title == "Things" }).command
        #expect(await rig.model.run(things) == false)
        #expect(rig.model.sendFailure == "Could not send to Things. Things could not open the link.")
    }

    @Test func openingThePanelAgainLeavesTheListAndForgetsThePayload() async throws {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "hello"))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:text" }).command)
        #expect(rig.model.sendLevel != nil)
        rig.model.prepareForOpen()
        #expect(rig.model.sendLevel == nil)
        #expect(rig.model.sendPending == nil)
        #expect(!rig.model.results.contains { $0.command.id.hasPrefix("send:") })
    }

    @Test func nothingIsSentWithoutARunCommand() async throws {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "hello"))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:text" }).command)
        rig.model.moveSelection(by: 1)
        rig.model.query = "notes"
        rig.model.query = ""
        #expect(rig.recorder.processes.isEmpty && rig.recorder.opened.isEmpty && rig.recorder.shared.isEmpty)
    }

    // MARK: Files and folders

    @Test func filesOfferCopyAndMoveIntoRememberedFoldersAfterTheFirstChoice() async throws {
        let rig = rig()
        let target = rig.directory.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.center.chooseFolder = { _ in target }
        feed(rig, ContextValues(selectedFiles: [URL(fileURLWithPath: "/tmp/a.txt")]))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:files" }).command)
        // The first time there is only the chooser, plus the mail draft and the Share menu.
        #expect(titles(rig).contains("Copy to a folder..."))
        #expect(!titles(rig).contains("Copy to Archive"))
        let choose = try #require(rig.model.results.first { $0.command.title == "Copy to a folder..." }).command
        #expect(await rig.model.run(choose))
        let request = try #require(rig.recorder.processes.first)
        #expect(request.executable == "/bin/cp")
        #expect(request.arguments.last == target.standardizedFileURL.path + "/")
        #expect(rig.model.lastSentCommand?.title == "Copy to Archive")

        // Remembered now: both rows exist the next time.
        rig.model.prepareForOpen()
        feed(rig, ContextValues(selectedFiles: [URL(fileURLWithPath: "/tmp/a.txt")]))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:files" }).command)
        #expect(titles(rig).contains("Copy to Archive"))
        #expect(titles(rig).contains("Move to Archive"))
    }

    @Test func cancellingTheFolderChooserSendsNothingAndStaysInTheList() async throws {
        let rig = rig()
        rig.center.chooseFolder = { _ in nil }
        feed(rig, ContextValues(selectedFiles: [URL(fileURLWithPath: "/tmp/a.txt")]))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:files" }).command)
        let choose = try #require(rig.model.results.first { $0.command.title == "Copy to a folder..." }).command
        #expect(await rig.model.run(choose) == false)
        #expect(rig.model.sendFailure == nil)
        #expect(rig.model.sendLevel != nil)
        #expect(rig.recorder.processes.isEmpty)
    }

    @Test func movingFilesAsksForConfirmationAfterTheChoice() async throws {
        let rig = rig()
        let target = rig.directory.appendingPathComponent("Done", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.center.chooseFolder = { _ in target }
        feed(rig, ContextValues(selectedFiles: [URL(fileURLWithPath: "/tmp/a.txt")]))
        _ = await rig.model.run(try #require(rig.model.results.first { $0.command.id == "send:files" }).command)
        let choose = try #require(rig.model.results.first { $0.command.title == "Move to a folder..." }).command
        #expect(await rig.model.run(choose) == false)
        #expect(rig.recorder.processes.isEmpty)
        #expect(rig.model.sendPending?.line.hasPrefix("Move into Done:") == true)
        #expect(await rig.model.confirmPending())
        #expect(try #require(rig.recorder.processes.first).executable == "/bin/mv")
    }
}
