import Foundation
import Testing

@testable import Apropos

private func link(_ text: String) -> URL {
    guard let url = URL(string: text) else { fatalError("bad test url: \(text)") }
    return url
}

private func parse(_ text: String) -> Result<ExternalRequest, ExternalRouteError> { ExternalRouter.parse(link(text)) }

@Suite("apropos:// parsing")
struct ExternalRouterTests {
    @Test func theThreeActionsParse() {
        #expect(parse("apropos://open") == .success(.open))
        #expect(parse("apropos://open/") == .success(.open))
        #expect(parse("apropos://search?q=hello%20world") == .success(.search(query: "hello world")))
        #expect(parse("apropos://run?command=up") == .success(.run(reference: "up", parameters: [:])))
        #expect(
            parse("apropos://RUN?command=up&text=a%26b%3Dc&url=https%3A%2F%2Fx.com&title=T&file=%2Ftmp%2Fa&folder=%2Ftmp")
                == .success(
                    .run(
                        reference: "up",
                        parameters: [.text: "a&b=c", .url: "https://x.com", .title: "T", .file: "/tmp/a", .folder: "/tmp"])))
    }

    @Test func unknownThingsAreRejectedStrictly() {
        #expect(parse("https://example.com") == .failure(.notOurLink))
        #expect(parse("apropos://nope") == .failure(.unknownAction("nope")))
        #expect(parse("apropos://") == .failure(.unknownAction("")))
        #expect(parse("apropos://run") == .failure(.missingParameter("command")))
        #expect(parse("apropos://run?command=") == .failure(.missingParameter("command")))
        #expect(parse("apropos://run?command=a&extra=1") == .failure(.unknownParameter("extra")))
        #expect(parse("apropos://run?command=a&shell=1") == .failure(.unknownParameter("shell")))
        #expect(parse("apropos://run?command=a&command=b") == .failure(.duplicateParameter("command")))
        #expect(parse("apropos://run?command=a&text=1&text=2") == .failure(.duplicateParameter("text")))
        #expect(parse("apropos://open?x=1") == .failure(.unknownParameter("x")))
        #expect(parse("apropos://search") == .failure(.missingParameter("q")))
        #expect(parse("apropos://search?q=a&r=b") == .failure(.unknownParameter("r")))
        #expect(parse("apropos://run/extra?command=a") == .failure(.notOurLink))
        #expect(parse("apropos://user@run?command=a") == .failure(.notOurLink))
        #expect(parse("apropos://run:80?command=a") == .failure(.notOurLink))
        #expect(parse("apropos://run?command=a#frag") == .failure(.notOurLink))
    }

    @Test func valuesAreBoundedAndControlCharactersCleaned() {
        let long = String(repeating: "a", count: ExternalRouter.maxQueryLength + 1)
        #expect(parse("apropos://search?q=\(long)") == .failure(.badValue("q")))
        #expect(parse("apropos://search?q=a%0Ab%09c%00d") == .success(.search(query: "a b c d")))
        #expect(parse("apropos://run?command=a&text=x%00y") == .failure(.badValue("text")))
        let tooLongURL = String(repeating: "a", count: ExternalRouter.maxValueLength + 1)
        #expect(parse("apropos://run?command=a&url=\(tooLongURL)") == .failure(.badValue("url")))
        #expect(parse("apropos://run?command=\(String(repeating: "c", count: 101))") == .failure(.badValue("command")))
    }

    @Test func valuesComeOnlyFromTheRequestAndAreTyped() throws {
        let good = try ExternalRouter.values(from: [.text: "hi", .url: "https://swift.org/x", .file: "/tmp/a", .folder: "/tmp"]).get()
        #expect(good.selectedText == "hi" && good.pageURL?.host == "swift.org")
        #expect(good.selectedFiles.map(\.path) == ["/tmp/a"] && good.folderURL?.path == "/tmp")
        for bad in [[ActionVariable.url: "javascript:alert(1)"], [.url: "file:///etc/passwd"], [.url: "not a url"], [.file: "relative"], [.folder: "../x"]] {
            if case .success = ExternalRouter.values(from: bad) { Issue.record("accepted \(bad)") }
        }
    }
}

@MainActor
@Suite("Outside runs")
struct ExternalRunnerTests {
    private struct Rig {
        let store: UserCommandStore
        let runner: ExternalRunner
        let recorder: ServiceRecorder
    }

    private func rig() -> Rig {
        let store = UserCommandStore(directory: tempCommandsDirectory())
        let recorder = ServiceRecorder()
        let center = ContextActionCenter(library: .bundled(), engine: ActionEngine(services: recorder.services))
        return Rig(store: store, runner: ExternalRunner(store: store, center: center), recorder: recorder)
    }

    private func allowed(_ rig: Rig, _ command: UserCommand) throws -> UserCommand {
        let made = try rig.store.create(command)
        try rig.store.setAllowFromURL(true, for: made.id)
        return try #require(rig.store.command(withID: made.id))
    }

    @Test func onlyCommandsMarkedAllowFromURLAreAvailable() throws {
        let rig = rig()
        let off = try rig.store.create(shoutCommand(title: "Off", aliases: ["off"]))
        let on = try allowed(rig, shoutCommand(title: "On", aliases: ["on"]))
        #expect(rig.runner.resolve(reference: "off", parameters: [:]) == .failure(.notAvailable))
        #expect(rig.runner.resolve(reference: off.id.rawValue, parameters: [:]) == .failure(.notAvailable))
        #expect(rig.runner.resolve(reference: "missing", parameters: [:]) == .failure(.notAvailable))
        if case .failure = rig.runner.resolve(reference: "ON", parameters: [:]) { Issue.record("alias should resolve") }
        if case .failure = rig.runner.resolve(reference: on.id.rawValue, parameters: [:]) { Issue.record("id should resolve") }
        #expect(rig.runner.available.map(\.title) == ["On"])
        #expect(rig.runner.search("o").map(\.title) == ["On"])
    }

    @Test func pendingCommandsAreNeverAvailableEvenIfTheFlagIsSet() throws {
        let rig = rig()
        var command = shoutCommand(title: "Pending", aliases: ["p"], review: .pending)
        command.allowFromURL = true
        _ = try rig.store.create(command)
        #expect(rig.runner.resolve(reference: "p", parameters: [:]) == .failure(.notAvailable))
        #expect(rig.runner.available.isEmpty)
    }

    @Test func theFirstRunNeedsConfirmationAndLaterOnesDoNot() async throws {
        let rig = rig()
        let command = try allowed(rig, shoutCommand(title: "Up", aliases: ["up"]))
        let first = try rig.runner.resolve(reference: "up", parameters: [.text: "hi"]).get()
        #expect(first.needsConfirmation && first.isFirstUse)
        #expect(await rig.runner.perform(first, confirmed: false, target: nil) == .failure(.confirmationRequired))
        #expect(rig.recorder.clipboard.isEmpty)
        #expect(try await rig.runner.perform(first, confirmed: true, target: nil).get().delivery == .copied)
        #expect(rig.recorder.clipboard == ["HI"])
        #expect(rig.store.command(withID: command.id)?.urlConfirmed == true)

        let second = try rig.runner.resolve(reference: "up", parameters: [.text: "again"]).get()
        #expect(!second.needsConfirmation)
        _ = try await rig.runner.perform(second, confirmed: false, target: nil).get()
        #expect(rig.recorder.clipboard == ["HI", "AGAIN"])
    }

    @Test func commandsThatAskForConfirmationAskEveryTime() async throws {
        let rig = rig()
        var command = shoutCommand(title: "Sure", aliases: ["sure"])
        command.needsConfirmation = true
        let made = try allowed(rig, command)
        try rig.store.markURLConfirmed(made.id)
        let run = try rig.runner.resolve(reference: "sure", parameters: [.text: "x"]).get()
        #expect(run.needsConfirmation && !run.isFirstUse)
    }

    @Test func replacingTheSelectionIsDowngradedToTheClipboard() async throws {
        let rig = rig()
        var command = shoutCommand(title: "Rep", aliases: ["rep"])
        command.output = .replaceSelection
        _ = try allowed(rig, command)
        let run = try rig.runner.resolve(reference: "rep", parameters: [.text: "x"]).get()
        #expect(run.command.output == .clipboard)
        _ = try await rig.runner.perform(run, confirmed: true, target: TargetApp(pid: 9, bundleID: "x", name: "X")).get()
        #expect(rig.recorder.replaced.isEmpty && rig.recorder.clipboard == ["X"])
        #expect(rig.store.command(withID: command.id)?.output == .replaceSelection)
    }

    @Test func urlSuppliedValuesCannotBecomeCode() async throws {
        let rig = rig()
        let nasty = "$(touch /tmp/apropos-url-pwn); `touch /tmp/apropos-url-pwn` \"q\" ' ; | & > \n \u{00E9}"
        let viaStdin = UserCommand(
            title: "Cat", aliases: ["cat"], requires: [.selectedText],
            backend: .shell(ShellBackend(executable: "/bin/cat", standardInput: .text)))
        let viaScript = UserCommand(
            title: "Script", aliases: ["scr"], requires: [.selectedText],
            backend: .appleScript(AppleScriptBackend(source: "on run argv\nreturn item 1 of argv\nend run", arguments: [try ActionTemplate("{text}")])))
        let viaEnv = UserCommand(
            title: "Env", aliases: ["env"], requires: [.selectedText],
            backend: .shell(ShellBackend(executable: "/bin/sh", arguments: [try ActionTemplate("-c"), try ActionTemplate("printf '%s' \"$APROPOS_TEXT\"")])))
        for command in [viaStdin, viaScript, viaEnv] { _ = try allowed(rig, command) }
        for alias in ["cat", "scr", "env"] {
            let run = try rig.runner.resolve(reference: alias, parameters: [.text: nasty]).get()
            _ = try await rig.runner.perform(run, confirmed: true, target: nil).get()
        }
        #expect(rig.recorder.clipboard == [nasty, nasty, nasty])
        #expect(!FileManager.default.fileExists(atPath: "/tmp/apropos-url-pwn"))
    }

    @Test func aRequestCannotUseLiveContextOrSupplyMissingRequirements() async throws {
        let rig = rig()
        _ = try allowed(rig, shoutCommand(title: "Up", aliases: ["up"]))
        let run = try rig.runner.resolve(reference: "up", parameters: [:]).get()
        #expect(run.values.isEmpty)
        #expect(await rig.runner.perform(run, confirmed: true, target: nil) == .failure(.missingContext(.selectedText)))
    }

    @Test func badParameterValuesAreRejectedBeforeAnythingRuns() throws {
        let rig = rig()
        _ = try allowed(rig, shoutCommand(title: "Up", aliases: ["up"]))
        #expect(rig.runner.resolve(reference: "up", parameters: [.url: "javascript:alert(1)"]) == .failure(.badParameter("url")))
        #expect(rig.runner.resolve(reference: "up", parameters: [.file: "../etc"]) == .failure(.badParameter("file")))
    }
}
