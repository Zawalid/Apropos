import Foundation
import Testing

@testable import Apropos

func tempCommandsDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("apropos-commands-\(UUID().uuidString)", isDirectory: true)
}

func shoutCommand(
    title: String = "Shout", aliases: [String] = [], requires: Set<ContextRequirement> = [.selectedText],
    backend: ActionBackend = .function("text.upper"), review: CommandReview = .approved,
    hotkey: HotKeyCombo? = nil
) -> UserCommand {
    UserCommand(
        title: title, aliases: aliases, requires: requires, backend: backend, output: .clipboard,
        hotkey: hotkey, review: review)
}

@MainActor
@Suite("UserCommandStore")
struct UserCommandStoreTests {
    private func store(_ directory: URL = tempCommandsDirectory(), limit: Int = 3) -> UserCommandStore {
        UserCommandStore(directory: directory, historyLimit: limit)
    }

    @Test func createWritesAReadableVersionedFileAndReloads() throws {
        let directory = tempCommandsDirectory()
        let first = store(directory)
        let made = try first.create(shoutCommand(aliases: ["  UP ", "up", "Shout-It"]))
        #expect(made.aliases == ["up", "shout-it"])
        let name = String(made.id.rawValue.dropFirst(5)) + ".json"
        let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 1") && text.contains("\"text.upper\""))
        #expect(text.contains(made.id.rawValue))

        let second = store(directory)
        #expect(second.commands == [made])
        #expect(second.issues.isEmpty)
    }

    @Test func everyFieldSurvivesAWriteAndRead() throws {
        let directory = tempCommandsDirectory()
        let full = UserCommand(
            title: "Everything", subtitle: "sub", symbol: "bolt", aliases: ["all"],
            apps: AppFilter(include: ["com.apple.finder"], exclude: ["x"]), requires: [.selectedFiles, .folder],
            conditions: [.selectionIsURL],
            backend: .shell(
                ShellBackend(
                    executable: "/usr/bin/open", arguments: [try ActionTemplate("-a"), try ActionTemplate("Terminal"), try ActionTemplate("{directory}")],
                    standardInput: nil, workingDirectory: .directory)),
            output: .none, needsConfirmation: true, keywords: ["k"], timeout: 30,
            hotkey: HotKeyCombo(keyCode: 40, modifiers: [.control, .option]), allowFromURL: true, urlConfirmed: true)
        let made = try store(directory).create(full)
        #expect(store(directory).command(withID: made.id) == made)
    }

    @Test func everyBackendKindRoundTrips() throws {
        let directory = tempCommandsDirectory()
        let backends: [ActionBackend] = [
            .function("text.upper"),
            .appleScript(AppleScriptBackend(source: "on run argv\nreturn 1\nend run", arguments: [try ActionTemplate("{text}")])),
            .shortcut(ShortcutBackend(name: "My Shortcut", input: .text)),
            .urlScheme(try ActionTemplate("https://example.com/?q={text}")),
            .keyPress(KeyPressBackend(keyCode: 9, modifiers: [.command, .shift])),
        ]
        let writer = store(directory)
        for (index, backend) in backends.enumerated() {
            _ = try writer.create(shoutCommand(title: "C\(index)", backend: backend))
        }
        let reader = store(directory)
        #expect(reader.commands.count == 5)
        #expect(Set(reader.commands.map(\.backend.kind)) == Set(backends.map(\.kind)))
        #expect(reader.commands == writer.commands)
    }

    @Test func updateKeepsTheIDAndArchivesTheOldVersionWithALimit() throws {
        let store = store(limit: 2)
        var command = try store.create(shoutCommand())
        for index in 1...5 {
            command.title = "Shout \(index)"
            command = try store.update(command)
        }
        #expect(store.commands.count == 1 && store.commands[0].title == "Shout 5")
        #expect(store.history(of: command.id).count == 2)
    }

    @Test func deleteRemovesTheFileButKeepsAHistoryCopy() throws {
        let store = store()
        let command = try store.create(shoutCommand())
        try store.delete(command.id)
        #expect(store.commands.isEmpty)
        #expect(store.history(of: command.id).count == 1)
        #expect(throws: UserCommandError.notFound) { try store.delete(command.id) }
    }

    @Test func duplicateGetsANewIDNoAliasesNoHotkeyNoOutsideAccess() throws {
        let store = store()
        var original = shoutCommand(aliases: ["up"], hotkey: HotKeyCombo(keyCode: 40, modifiers: [.control, .option]))
        original.allowFromURL = true
        let made = try store.create(original)
        let copy = try store.duplicate(made.id)
        #expect(copy.id != made.id && copy.title == "Shout copy")
        #expect(copy.aliases.isEmpty && copy.hotkey == nil && !copy.allowFromURL)
        #expect(store.commands.count == 2)
    }

    @Test func validationErrorsAreClear() throws {
        let store = store()
        #expect(throws: UserCommandError.titleEmpty) { try store.create(shoutCommand(title: "  ")) }
        #expect(throws: UserCommandError.badAlias("two words")) { try store.create(shoutCommand(aliases: ["two words"])) }
        #expect(throws: UserCommandError.tooManyAliases) {
            try store.create(shoutCommand(aliases: (1...9).map { "a\($0)" }))
        }
        #expect(throws: UserCommandError.invalid(.unknownFunction("nope"))) {
            try store.create(shoutCommand(backend: .function("nope")))
        }
        let injected = ShellBackend(executable: "/bin/sh", arguments: [try ActionTemplate("-c"), try ActionTemplate("echo {text}")])
        #expect(throws: UserCommandError.invalid(.placeholderInScript)) {
            try store.create(shoutCommand(backend: .shell(injected)))
        }
        #expect(throws: UserCommandError.invalid(.variableNeedsContext(.text))) {
            try store.create(shoutCommand(requires: [], backend: .shell(ShellBackend(executable: "/bin/cat", standardInput: .text))))
        }
        #expect(throws: UserCommandError.badHotkey) {
            try store.create(shoutCommand(hotkey: HotKeyCombo(keyCode: 49, modifiers: [])))
        }
        let bad = UserCommand(id: ActionID(rawValue: "ctx:text.upper"), title: "x", backend: .function("text.upper"))
        #expect(throws: UserCommandError.badID) { try store.create(bad) }
        #expect(store.commands.isEmpty)
        #expect(UserCommandError.titleEmpty.description == "Give the command a title.")
    }

    @Test func aCommandNeedingNoContextIsValid() throws {
        let open = UserCommand(title: "Open docs", backend: .urlScheme(try ActionTemplate("https://example.com/docs")), output: .none)
        #expect(try store().create(open).requires.isEmpty)
    }

    @Test func aliasesAreUniqueAcrossCommands() throws {
        let store = store()
        _ = try store.create(shoutCommand(title: "One", aliases: ["go"]))
        #expect(throws: UserCommandError.aliasTaken(alias: "go", by: "One")) {
            try store.create(shoutCommand(title: "Two", aliases: ["GO"]))
        }
        var two = try store.create(shoutCommand(title: "Two"))
        two.aliases = ["go"]
        #expect(throws: UserCommandError.aliasTaken(alias: "go", by: "One")) { try store.update(two) }
        #expect(store.runnableCommand(matching: "GO")?.title == "One")
    }

    @Test func shortcutsCannotClashWithThePanelOrEachOther() throws {
        let store = store()
        let panel = HotKeyCombo(keyCode: 49, modifiers: [.option])
        store.reservedHotKeys = { [panel] }
        let mine = HotKeyCombo(keyCode: 40, modifiers: [.control, .option])
        #expect(throws: UserCommandError.hotkeyTaken(by: "Apropos")) { try store.create(shoutCommand(hotkey: panel)) }
        _ = try store.create(shoutCommand(title: "A", hotkey: mine))
        #expect(throws: UserCommandError.hotkeyTaken(by: "A")) { try store.create(shoutCommand(title: "B", hotkey: mine)) }
        #expect(store.hotkeyConflict(mine, excluding: nil) == .command(title: "A"))
        #expect(store.hotkeyConflict(panel, excluding: nil) == .panel)
    }

    @Test func handEditedFilesLoadAndBadOnesAreReportedNotFatal() throws {
        let directory = tempCommandsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let good = """
            {"schemaVersion":1,"command":{"id":"user:hand-made","title":"By hand","symbol":"star","requires":["selectedText"],
            "backend":{"type":"function","name":"text.lower"}},"aliases":["hm"]}
            """
        try Data(good.utf8).write(to: directory.appendingPathComponent("hand.json"))
        try Data("not json".utf8).write(to: directory.appendingPathComponent("bad.json"))
        try Data(#"{"schemaVersion":9,"command":{}}"#.utf8).write(to: directory.appendingPathComponent("future.json"))
        try Data(good.utf8).write(to: directory.appendingPathComponent("copy.json"))
        let store = store(directory)
        #expect(store.commands.map(\.title) == ["By hand"])
        #expect(store.issues.count == 3 && Set(store.issues.map(\.fileName)).isSuperset(of: ["bad.json", "future.json"]))
        // Editing a hand-placed file writes back to the same file.
        var edited = store.commands[0]
        edited.title = "Renamed"
        _ = try store.update(edited)
        #expect(Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).contains("history"))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("user:hand-made.json").path))
        #expect(store.reload() == ())
        #expect(store.commands.map(\.title) == ["Renamed"])
    }

    @Test func pendingCommandsStayPendingUntilApprovedAndAreNotRunnable() throws {
        let store = store()
        let made = try store.create(shoutCommand(review: .pending))
        #expect(store.runnable.isEmpty && store.pending.count == 1)
        var edit = made
        edit.review = .approved
        #expect(try store.update(edit).review == .pending)
        #expect(throws: UserCommandError.pendingReview) { try store.setAllowFromURL(true, for: made.id) }
        #expect(try store.approve(made.id).review == .approved)
        #expect(store.runnable.count == 1)
    }

    @Test func changingTheBackendResetsTheOutsideConfirmation() throws {
        let store = store()
        var made = try store.create(shoutCommand())
        try store.setAllowFromURL(true, for: made.id)
        try store.markURLConfirmed(made.id)
        made = try #require(store.command(withID: made.id))
        #expect(made.allowFromURL && made.urlConfirmed)
        made.title = "Renamed"
        #expect(try store.update(made).urlConfirmed)
        made.backend = .function("text.lower")
        #expect(try store.update(made).urlConfirmed == false)
    }

    @Test func observersHearAboutChanges() throws {
        let store = store()
        var calls = 0
        store.onChange = { calls += 1 }
        let made = try store.create(shoutCommand())
        _ = try store.update(made)
        try store.delete(made.id)
        #expect(calls >= 2)
    }
}

extension ActionBackend {
    var kind: String {
        switch self {
        case .function: "function"
        case .shell: "shell"
        case .appleScript: "appleScript"
        case .shortcut: "shortcut"
        case .urlScheme: "urlScheme"
        case .keyPress: "keyPress"
        case .uiSteps: "uiSteps"
        case .sequence: "sequence"
        }
    }
}

@MainActor
@Suite("User commands in the palette")
struct UserCommandPaletteTests {
    private let app = TargetApp(pid: 100, bundleID: "com.example.editor", name: "Editor")

    private func rig() -> (PaletteModel, ContextActionCenter, ServiceRecorder, AppMenuModel) {
        let tracker = FrontmostAppTracker(ownBundleID: "test")
        tracker.pin(app)
        let menus = AppMenuModel(tracker: tracker, permission: AccessibilityPermission(probe: { true }))
        menus.seed(MenuCommandMapper.commands(from: Fixtures.menuBar(), bundleID: app.bundleID))
        let model = PaletteModel(menus: menus, tracker: tracker)
        let recorder = ServiceRecorder()
        let library = ActionPackLibrary.bundled()
        let center = ContextActionCenter(
            library: library, engine: ActionEngine(functions: library.functions, services: recorder.services))
        center.attach(to: model)
        return (model, center, recorder, menus)
    }

    private func snapshot(_ values: ContextValues) -> ContextSnapshot {
        ContextSnapshot(appName: "Editor", bundleID: app.bundleID, pid: app.pid, capturedAt: Date(), values: values)
    }

    @Test func commandsListUnderYourCommandsAndNeedingNoContextAppearAtOnce() throws {
        let (model, center, _, _) = rig()
        let open = UserCommand(title: "Open docs", aliases: ["docs"], backend: .urlScheme(try ActionTemplate("https://example.com")), output: .none)
        let needsText = shoutCommand(title: "Shout")
        center.setUserCommands([open, needsText])
        model.prepareForOpen()
        let first = model.results.first?.command
        #expect(first?.title == "Open docs")
        #expect(first?.path == ["Your commands"])
        #expect(!model.results.contains { $0.command.title == "Shout" })

        center.update(with: snapshot(ContextValues(selectedText: "hi")))
        let titles = model.results.map(\.command.title)
        #expect(titles.prefix(2) == ["Open docs", "Shout"])
    }

    @Test func anAliasRanksItsCommandFirst() throws {
        let (model, center, _, _) = rig()
        let mine = UserCommand(title: "Zzz open the documentation", aliases: ["d"], backend: .urlScheme(try ActionTemplate("https://example.com")), output: .none)
        center.setUserCommands([mine])
        model.prepareForOpen()
        model.query = "d"
        #expect(model.results.first?.command.title == "Zzz open the documentation")
    }

    @Test func pendingCommandsAreNeverListedAndAppFiltersApply() throws {
        let (model, center, _, _) = rig()
        let pending = UserCommand(title: "Pending", backend: .urlScheme(try ActionTemplate("https://example.com")), output: .none, review: .pending)
        var elsewhere = UserCommand(title: "Elsewhere", backend: .urlScheme(try ActionTemplate("https://example.com")), output: .none)
        elsewhere.apps = AppFilter(include: ["com.apple.finder"])
        center.setUserCommands([pending, elsewhere])
        model.prepareForOpen()
        #expect(!model.results.contains { $0.command.path == ["Your commands"] })
    }

    @Test func runningGoesThroughTheEngineAndRecordsOnlyTheID() async throws {
        let (model, center, recorder, _) = rig()
        center.setUserCommands([shoutCommand(title: "Shout")])
        model.prepareForOpen()
        center.update(with: snapshot(ContextValues(selectedText: "quiet")))
        model.query = "shout"
        #expect(await model.runSelected())
        #expect(recorder.clipboard == ["QUIET"])

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("u-\(UUID().uuidString)/usage.json")
        let usage = UsageStore(url: url, writeDelay: .zero)
        if let command = model.selected?.command { usage.recordRun(of: command) }
        let stored = try String(contentsOf: url, encoding: .utf8)
        #expect(stored.contains("user:") && !stored.contains("quiet"))
    }
}
