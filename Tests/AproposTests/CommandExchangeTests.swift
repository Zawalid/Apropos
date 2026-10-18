import Foundation
import Testing

@testable import Apropos

private func envelope(_ commands: String, version: Int = 1, kind: String = "apropos.commands", name: String = "Pack") -> Data {
    Data(#"{"schemaVersion":\#(version),"kind":"\#(kind)","name":"\#(name)","commands":[\#(commands)]}"#.utf8)
}

private func entry(
    title: String = "Shout", id: String = "user:x", backend: String = #"{"type":"function","name":"text.upper"}"#,
    extra: String = ""
) -> String {
    #"{"command":{"id":"\#(id)","title":"\#(title)","symbol":"star","requires":["selectedText"],"backend":\#(backend)}\#(extra)}"#
}

@MainActor
@Suite("Import and export")
struct CommandExchangeTests {
    private func store() -> UserCommandStore { UserCommandStore(directory: tempCommandsDirectory()) }

    // MARK: Export

    @Test func exportLeavesOutShortcutsOutsideAccessAndApproval() throws {
        var command = shoutCommand(aliases: ["up"], hotkey: HotKeyCombo(keyCode: 40, modifiers: [.control, .option]))
        command.allowFromURL = true
        command.urlConfirmed = true
        let text = String(decoding: try CommandExchange.export([command], name: "Mine"), as: UTF8.self)
        #expect(text.contains("\"kind\" : \"apropos.commands\"") && text.contains("\"name\" : \"Mine\""))
        #expect(!text.contains("hotkey") && !text.contains("allowFromURL") && !text.contains("urlConfirmed") && !text.contains("review"))
        #expect(text.contains("\"aliases\"") && text.contains("text.upper"))
    }

    @Test func exportedFilesReviewCleanlyAndRoundTripTheDefinition() throws {
        let original = UserCommand(
            title: "Say it", symbol: "bolt", aliases: ["say"], requires: [.selectedText],
            backend: .shell(ShellBackend(executable: "/usr/bin/say", standardInput: .text)), output: .none,
            needsConfirmation: true, keywords: ["speak"], timeout: 20)
        let data = try CommandExchange.export([original])
        let review = try CommandExchange.review(data, existing: [])
        #expect(review.rejected.isEmpty && review.items.count == 1)
        let item = review.items[0]
        #expect(item.id != original.id)
        #expect(item.command.title == "Say it" && item.command.backend == original.backend && item.command.aliases == ["say"])
        #expect(item.command.needsConfirmation && item.command.keywords == ["speak"] && item.command.timeout == 20)
    }

    // MARK: Review

    @Test func reviewDescribesWhatEachCommandRunsAndFlagsScripts() throws {
        let data = envelope(
            [
                entry(title: "Plain"),
                entry(title: "Program", backend: #"{"type":"shell","executable":"/usr/bin/say","stdin":"text"}"#),
                entry(title: "Script", backend: #"{"type":"appleScript","source":"on run argv\nreturn 1\nend run","arguments":["{text}"]}"#),
                entry(title: "Shortcut", backend: #"{"type":"shortcut","name":"Do It","input":"text"}"#),
            ].joined(separator: ","))
        let review = try CommandExchange.review(data, existing: [])
        #expect(review.items.map(\.command.title) == ["Plain", "Program", "Script", "Shortcut"])
        #expect(review.items.map(\.needsApproval) == [false, true, true, false])
        #expect(review.items.map(\.command.review) == [.approved, .pending, .pending, .approved])
        #expect(review.items[1].risks.contains(.runsProgram) && review.items[2].risks.contains(.runsAppleScript))
        #expect(review.items[1].summary.first == "Runs /usr/bin/say")
        #expect(review.items[2].summary.first == "Runs an AppleScript of 3 lines:")
        #expect(review.items[3].risks == [.runsShortcut])
        #expect(review.packName == "Pack")
    }

    @Test func idsAndTrustFieldsInTheFileAreIgnored() throws {
        let forged = entry(
            title: "Forged", id: "user:../../etc/passwd",
            backend: #"{"type":"shell","executable":"/bin/cat","stdin":"text"}"#,
            extra: #","allowFromURL":true,"urlConfirmed":true,"review":"approved","hotkey":{"keyCode":40,"modifiers":["command"]}"#)
        let review = try CommandExchange.review(envelope(forged), existing: [])
        let item = try #require(review.items.first)
        #expect(item.command.id.rawValue.hasPrefix("user:") && item.command.id.rawValue != "user:../../etc/passwd")
        #expect(item.command.id.isWellFormed)
        #expect(item.command.review == .pending && !item.command.allowFromURL && !item.command.urlConfirmed)
        #expect(item.command.hotkey == nil)
    }

    @Test func hostileDefinitionsAreRejectedNotImported() throws {
        let injected = entry(title: "Inject", backend: #"{"type":"shell","executable":"/bin/sh","arguments":["-c","echo {text}"]}"#)
        let relative = entry(title: "Relative", backend: #"{"type":"shell","executable":"sh","arguments":["-c","true"]}"#)
        let env = entry(title: "Env", backend: #"{"type":"shell","executable":"/usr/bin/env","arguments":["{text}"]}"#)
        let url = entry(title: "Evil URL", backend: #"{"type":"urlScheme","url":"https://{text}.evil.com/"}"#)
        let js = entry(title: "JS", backend: #"{"type":"urlScheme","url":"javascript:alert({text})"}"#)
        let unknown = entry(title: "Unknown", backend: #"{"type":"quantum"}"#)
        let nofunc = entry(title: "NoFunc", backend: #"{"type":"function","name":"rm.everything"}"#)
        let badSymbol = #"{"command":{"id":"user:x","title":"Sym","symbol":"has space","requires":[],"backend":{"type":"function","name":"text.upper"}}}"#
        let notObject = "42"
        let review = try CommandExchange.review(
            envelope([injected, relative, env, url, js, unknown, nofunc, badSymbol, notObject, entry(title: "Fine")].joined(separator: ",")),
            existing: [])
        #expect(review.items.map(\.command.title) == ["Fine"])
        #expect(review.rejected.count == 9)
        #expect(review.rejected.allSatisfy { !$0.reason.isEmpty })
        #expect(review.rejected.first?.reason == UserCommandError.invalid(.placeholderInScript).description)
    }

    @Test func fileLevelProblemsThrow() throws {
        #expect(throws: CommandImportError.notACommandFile) { try CommandExchange.review(Data("garbage".utf8), existing: []) }
        #expect(throws: CommandImportError.notACommandFile) { try CommandExchange.review(Data("[1,2]".utf8), existing: []) }
        #expect(throws: CommandImportError.notACommandFile) { try CommandExchange.review(envelope(entry(), kind: "other"), existing: []) }
        #expect(throws: CommandImportError.newerVersion) { try CommandExchange.review(envelope(entry(), version: 2), existing: []) }
        #expect(throws: CommandImportError.empty) { try CommandExchange.review(envelope(""), existing: []) }
        #expect(throws: CommandImportError.notACommandFile) { try CommandExchange.review(Data([0xFF, 0xFE, 0x00]), existing: []) }
    }

    @Test func oversizedAndOverfullFilesAreRefused() throws {
        let huge = Data(repeating: 0x20, count: CommandExchange.maxFileBytes + 1)
        #expect(throws: CommandImportError.tooLarge) { try CommandExchange.review(huge, existing: []) }

        let many = (0...CommandExchange.maxCommands).map { entry(title: "C\($0)") }.joined(separator: ",")
        #expect(throws: CommandImportError.tooManyCommands) { try CommandExchange.review(envelope(many), existing: []) }

        let bigTitle = entry(title: String(repeating: "T", count: 5_000))
        let bigScript = entry(
            title: "Script", backend: #"{"type":"appleScript","source":"\#(String(repeating: "x", count: 30_000))"}"#)
        let bigKeywords = #"{"command":{"id":"user:x","title":"K","symbol":"star","requires":["selectedText"],"keywords":[\#((0..<30).map { "\"k\($0)\"" }.joined(separator: ","))],"backend":{"type":"function","name":"text.upper"}}}"#
        let review = try CommandExchange.review(envelope([bigTitle, bigScript, bigKeywords].joined(separator: ",")), existing: [])
        #expect(review.items.isEmpty && review.rejected.count == 3)
    }

    @Test func deeplyNestedJSONDoesNotCrash() {
        let nested = String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000)
        #expect(throws: CommandImportError.notACommandFile) { try CommandExchange.review(Data(nested.utf8), existing: []) }
        let inside = Data(#"{"schemaVersion":1,"kind":"apropos.commands","commands":[{"command":\#(nested)}]}"#.utf8)
        #expect(throws: CommandImportError.self) { try CommandExchange.review(inside, existing: []) }
    }

    @Test func duplicatesAndAliasClashesAreFlagged() throws {
        let store = store()
        let existing = try store.create(shoutCommand(title: "Shout", aliases: ["up"]))
        let data = envelope(
            [
                entry(title: "Shout", extra: #","aliases":["up","fresh"]"#),
                entry(title: "Other", extra: #","aliases":["fresh","Other"]"#),
                entry(title: "Other", extra: #","aliases":["other"]"#),
            ].joined(separator: ","))
        let review = try CommandExchange.review(data, existing: store.commands)
        #expect(review.items.count == 3)
        #expect(review.items[0].duplicateOf == existing.title && review.items[0].droppedAliases == ["up"])
        #expect(review.items[0].command.aliases == ["fresh"])
        #expect(review.items[1].duplicateOf == nil && review.items[1].droppedAliases == ["fresh"])
        #expect(review.items[1].command.aliases == ["other"])
        #expect(review.items[2].duplicateOf == "Other" && review.items[2].droppedAliases == ["other"])
        #expect(review.defaultSelection == [review.items[1].id])
    }

    // MARK: Applying

    @Test func importingStoresApprovedAndPendingAndNeverRunsPendingOnes() async throws {
        let store = store()
        let data = envelope(
            [entry(title: "Plain"), entry(title: "Program", backend: #"{"type":"shell","executable":"/bin/cat","stdin":"text"}"#)]
                .joined(separator: ","))
        let review = try CommandExchange.review(data, existing: store.commands)
        let result = store.importReviewed(review)
        #expect(result.added.count == 2 && result.failed.isEmpty, "\(result.failed) \(review.rejected) \(review.items.count)")
        #expect(store.runnable.map(\.title) == ["Plain"])
        #expect(store.pending.map(\.title) == ["Program"])
        #expect(store.runnableCommand(matching: store.pending[0].id.rawValue) == nil)

        let pending = try #require(store.pending.first)
        let recorder = ServiceRecorder()
        let center = ContextActionCenter(library: .bundled(), engine: ActionEngine(services: recorder.services))
        center.setUserCommands(store.commands)
        #expect(!center.commands.contains { $0.title == "Program" })
        let direct = await center.run(pending, values: ContextValues(selectedText: "x"), target: nil)
        #expect(direct == .failure(.notApplicable) && recorder.clipboard.isEmpty)

        // Reloading from disk keeps it pending.
        let reloaded = UserCommandStore(directory: store.directory)
        #expect(reloaded.pending.count == 1)
        try reloaded.approve(pending.id)
        #expect(reloaded.runnable.count == 2)
    }

    @Test func selectionControlsWhatIsStored() throws {
        let store = store()
        let review = try CommandExchange.review(envelope([entry(title: "A"), entry(title: "B")].joined(separator: ",")), existing: [])
        let result = store.importReviewed(review, selecting: [review.items[1].id])
        #expect(result.added.map(\.title) == ["B"] && store.commands.count == 1)
    }

    @Test func exportThenImportThroughFilesOnTwoStores() throws {
        let source = store()
        _ = try source.create(shoutCommand(title: "One", aliases: ["one"]))
        _ = try source.create(UserCommand(title: "Two", requires: [.selectedText], backend: .shell(ShellBackend(executable: "/bin/cat", standardInput: .text))))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).json")
        try source.exportCommands(nil, name: "Pair", to: file)

        let target = store()
        let review = try target.reviewFile(at: file)
        #expect(review.items.count == 2 && review.packName == "Pair")
        target.importReviewed(review)
        #expect(Set(target.commands.map(\.title)) == ["One", "Two"])
        #expect(target.command(withID: source.commands[0].id) == nil)
        #expect(target.pending.map(\.title) == ["Two"])
    }

    @Test func reviewFileRefusesLargeFilesWithoutReadingThem() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("big-\(UUID().uuidString).json")
        try Data(repeating: 0x20, count: CommandExchange.maxFileBytes + 10).write(to: file)
        #expect(throws: CommandImportError.tooLarge) { try store().reviewFile(at: file) }
    }

    @Test func summariesStayShort() {
        let long = UserCommand(
            title: "L", requires: [.selectedText],
            backend: .appleScript(AppleScriptBackend(source: (0..<50).map { "line \($0) " + String(repeating: "x", count: 400) }.joined(separator: "\n"))))
        let lines = CommandSummary.lines(for: long)
        #expect(lines.count < 20 && lines.allSatisfy { $0.count < 260 })
    }
}
