import Foundation
import Testing

@testable import Apropos

/// Records what the engine did to the outside world, and answers as configured.
final class ServiceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _clipboard: [String] = []
    private var _opened: [URL] = []
    private var _notices: [String] = []
    private var _keys: [KeyPressBackend] = []
    private var _replaced: [(String, pid_t)] = []
    var replaceAnswer: ReplaceResult = .replaced
    var openAnswer = true
    var keyAnswer = true

    var clipboard: [String] { lock.withLock { _clipboard } }
    var opened: [URL] { lock.withLock { _opened } }
    var notices: [String] { lock.withLock { _notices } }
    var keys: [KeyPressBackend] { lock.withLock { _keys } }
    var replaced: [(String, pid_t)] { lock.withLock { _replaced } }

    var services: ActionServices {
        ActionServices(
            process: { try await ProcessRunner.run($0) },
            openURL: { url in
                self.lock.withLock { self._opened.append(url) }
                return self.openAnswer
            },
            copyToClipboard: { text in self.lock.withLock { self._clipboard.append(text) } },
            notify: { text in self.lock.withLock { self._notices.append(text) } },
            postKey: { key in
                self.lock.withLock { self._keys.append(key) }
                return self.keyAnswer
            },
            replaceSelection: { text, pid in
                self.lock.withLock { self._replaced.append((text, pid)) }
                return self.replaceAnswer
            })
    }
}

let nastyText = "$(touch /tmp/apropos-pwn); `touch /tmp/apropos-pwn` \"q\" 'q' \\ ; | & > < \n second line \u{00E9}"

func textValues(_ text: String) -> ContextValues { ContextValues(selectedText: text) }

func action(
    _ id: String = "ctx:test.one", requires: Set<ContextRequirement> = [.selectedText],
    backend: ActionBackend, output: ActionOutput = .clipboard, confirm: Bool = false, timeout: TimeInterval = 5,
    apps: AppFilter = .anyApp, conditions: Set<ActionCondition> = []
) -> ContextAction {
    ContextAction(
        id: ActionID(rawValue: id), title: "Test", symbol: "star", requires: requires, conditions: conditions,
        apps: apps, backend: backend, output: output, needsConfirmation: confirm, timeout: timeout)
}

func template(_ text: String) -> ActionTemplate {
    do { return try ActionTemplate(text) } catch { fatalError("bad template in test: \(text)") }
}

private let finder = TargetApp(pid: 42, bundleID: "com.apple.finder", name: "Finder")

@Suite struct ActionEngineTests {
    private func engine(_ recorder: ServiceRecorder, functions: ActionFunctionRegistry = ActionFunctionRegistry()) -> ActionEngine {
        ActionEngine(functions: functions, services: recorder.services)
    }

    private let upper = ActionFunctionRegistry().adding("t.upper") { input, _ in input.scalar(.text)?.uppercased() }

    @Test func functionResultGoesToTheClipboardByDefault() async throws {
        let recorder = ServiceRecorder()
        let result = await engine(recorder, functions: upper).run(
            action(backend: .function("t.upper")), values: textValues("abc"), target: finder)
        #expect(try result.get() == ActionOutcome(id: "ctx:test.one", delivery: .copied))
        #expect(recorder.clipboard == ["ABC"])
    }

    @Test func replaceSelectionTargetsTheAppAndFallsBackToTheClipboard() async throws {
        let recorder = ServiceRecorder()
        let replace = action(backend: .function("t.upper"), output: .replaceSelection)
        let first = try await engine(recorder, functions: upper).run(replace, values: textValues("abc"), target: finder).get()
        #expect(first.delivery == .replaced)
        #expect(recorder.replaced.first?.0 == "ABC" && recorder.replaced.first?.1 == 42)
        #expect(recorder.clipboard.isEmpty)

        recorder.replaceAnswer = .pasted
        #expect(try await engine(recorder, functions: upper).run(replace, values: textValues("a"), target: finder).get().delivery == .pasted)

        recorder.replaceAnswer = .notEditable
        let third = try await engine(recorder, functions: upper).run(replace, values: textValues("a"), target: finder).get()
        #expect(third.delivery == .copiedInstead)
        #expect(recorder.clipboard == ["A"])
    }

    @Test func notifyCarriesTheNoticeAndNoneDiscards() async throws {
        let recorder = ServiceRecorder()
        let notify = action(backend: .function("t.upper"), output: .notify)
        let outcome = try await engine(recorder, functions: upper).run(notify, values: textValues("hi"), target: nil).get()
        #expect(outcome.delivery == .notified && outcome.notice == "HI")
        #expect(recorder.notices == ["HI"])
        let none = action(backend: .function("t.upper"), output: .none)
        #expect(try await engine(recorder, functions: upper).run(none, values: textValues("hi"), target: nil).get().delivery == .done)
        #expect(recorder.clipboard.isEmpty)
    }

    @Test func missingContextAppFilterConditionsAndConfirmation() async {
        let recorder = ServiceRecorder()
        let engine = engine(recorder, functions: upper)
        let plain = action(backend: .function("t.upper"))
        #expect(await engine.run(plain, values: ContextValues(), target: nil) == .failure(.missingContext(.selectedText)))

        let onlySafari = action(backend: .function("t.upper"), apps: AppFilter(include: ["com.apple.Safari"]))
        #expect(await engine.run(onlySafari, values: textValues("a"), target: finder) == .failure(.notApplicable))

        let json = action(backend: .function("t.upper"), conditions: [.selectionIsJSON])
        #expect(await engine.run(json, values: textValues("not json"), target: nil) == .failure(.notApplicable))
        if case .failure = await engine.run(json, values: textValues("{\"a\":1}"), target: nil) { Issue.record("should run") }

        let destructive = action(backend: .function("t.upper"), confirm: true)
        let before = recorder.clipboard.count
        #expect(await engine.run(destructive, values: textValues("a"), target: nil) == .failure(.confirmationRequired))
        #expect(recorder.clipboard.count == before)
        if case .failure = await engine.run(destructive, values: textValues("a"), target: nil, confirmed: true) {
            Issue.record("confirmed run should succeed")
        }
    }

    @Test func unknownFunctionAndBadInputAreReported() async {
        let recorder = ServiceRecorder()
        let engine = engine(
            recorder, functions: ActionFunctionRegistry().adding("t.bad") { _, _ in throw TextToolError.invalidInput })
        #expect(await engine.run(action(backend: .function("nope")), values: textValues("a"), target: nil) == .failure(.unknownFunction("nope")))
        #expect(await engine.run(action(backend: .function("t.bad")), values: textValues("a"), target: nil) == .failure(.invalidInput))
    }

    @Test func slowActionsTimeOutAndCancelledOnesStop() async {
        let recorder = ServiceRecorder()
        let slow = ActionFunctionRegistry().adding("t.slow") { _, _ in
            try await Task.sleep(for: .seconds(30))
            return "late"
        }
        let engine = engine(recorder, functions: slow)
        let started = Date()
        let timed = await engine.run(action(backend: .function("t.slow"), timeout: 0.5), values: textValues("a"), target: nil)
        #expect(timed == .failure(.timedOut))
        #expect(Date().timeIntervalSince(started) < 5)

        let task = Task { await engine.run(action(backend: .function("t.slow"), timeout: 30), values: textValues("a"), target: nil) }
        try? await Task.sleep(for: .milliseconds(150))
        task.cancel()
        let result = await task.value
        #expect(result == .failure(.cancelled))
        #expect(recorder.clipboard.isEmpty)
    }

    // MARK: Injection

    @Test func shellStdinCarriesTextVerbatim() async throws {
        let recorder = ServiceRecorder()
        let cat = action(
            backend: .shell(ShellBackend(executable: "/bin/cat", standardInput: .text)))
        _ = try await engine(recorder).run(cat, values: textValues(nastyText), target: nil).get()
        #expect(recorder.clipboard == [nastyText])
        #expect(!FileManager.default.fileExists(atPath: "/tmp/apropos-pwn"))
    }

    @Test func shellArgumentsCarryTextVerbatimAsOneArgument() async throws {
        let recorder = ServiceRecorder()
        let printf = action(
            backend: .shell(ShellBackend(executable: "/usr/bin/printf", arguments: [template("[%s]"), template("<{text}>")])))
        _ = try await engine(recorder).run(printf, values: textValues(nastyText), target: nil).get()
        #expect(recorder.clipboard == ["[<\(nastyText)>]"])
        #expect(!FileManager.default.fileExists(atPath: "/tmp/apropos-pwn"))
    }

    @Test func positionalParametersOfAShellScriptAreSafe() async throws {
        let recorder = ServiceRecorder()
        let script = action(
            backend: .shell(
                ShellBackend(
                    executable: "/bin/sh",
                    arguments: [template("-c"), template("printf '%s' \"$1\""), template("sh"), template("{text}")])))
        _ = try await engine(recorder).run(script, values: textValues(nastyText), target: nil).get()
        #expect(recorder.clipboard == [nastyText])
        #expect(!FileManager.default.fileExists(atPath: "/tmp/apropos-pwn"))
    }

    @Test func environmentVariablesCarryTextVerbatim() async throws {
        let recorder = ServiceRecorder()
        let script = action(
            backend: .shell(
                ShellBackend(executable: "/bin/sh", arguments: [template("-c"), template("printf '%s' \"$APROPOS_TEXT\"")])))
        _ = try await engine(recorder).run(script, values: textValues(nastyText), target: nil).get()
        #expect(recorder.clipboard == [nastyText])
        #expect(!FileManager.default.fileExists(atPath: "/tmp/apropos-pwn"))
    }

    @Test func appleScriptParametersCarryTextVerbatim() async throws {
        let recorder = ServiceRecorder()
        let source = "on run argv\nreturn item 1 of argv\nend run"
        let text = "\"; do shell script \"touch /tmp/apropos-pwn2\"; \" \\ ' \n x \u{00E9}"
        let script = action(backend: .appleScript(AppleScriptBackend(source: source, arguments: [template("{text}")])))
        _ = try await engine(recorder).run(script, values: textValues(text), target: nil).get()
        #expect(recorder.clipboard == [text])
        #expect(!FileManager.default.fileExists(atPath: "/tmp/apropos-pwn2"))
    }

    @Test func urlValuesAreFullyPercentEncoded() async throws {
        let recorder = ServiceRecorder()
        let search = action(backend: .urlScheme(template("https://example.com/search?q={text}&x=1")), output: .none)
        _ = try await engine(recorder).run(search, values: textValues("a&b=c#d \u{00E9}/../?"), target: nil).get()
        #expect(recorder.opened.map(\.absoluteString) == ["https://example.com/search?q=a%26b%3Dc%23d%20%C3%A9%2F..%2F%3F&x=1"])
    }

    @Test func failingOpenAndKeyPressSurfaceAsUnavailable() async {
        let recorder = ServiceRecorder()
        recorder.openAnswer = false
        recorder.keyAnswer = false
        let open = action(backend: .urlScheme(template("https://example.com/{text}")))
        if case .failure(.unavailable) = await engine(recorder).run(open, values: textValues("a"), target: nil) {} else {
            Issue.record("expected unavailable")
        }
        let key = action(requires: [.selectedText], backend: .keyPress(KeyPressBackend(keyCode: 8, modifiers: [.command])))
        if case .failure(.unavailable) = await engine(recorder).run(key, values: textValues("a"), target: nil) {} else {
            Issue.record("expected unavailable")
        }
        #expect(recorder.keys.count == 1)
    }

    @Test func nonZeroExitIsAFailureWithoutOutput() async {
        let recorder = ServiceRecorder()
        let fail = action(backend: .shell(ShellBackend(executable: "/usr/bin/false")))
        #expect(await engine(recorder).run(fail, values: textValues("a"), target: nil) == .failure(.backendFailed(status: 1)))
        #expect(recorder.clipboard.isEmpty)
    }
}

@Suite struct ActionValidatorTests {
    private let functions = ActionFunctionRegistry().adding("t.ok") { _, _ in nil }

    private func problem(_ action: ContextAction) -> ActionValidationError? {
        do {
            try ActionValidator.validate(action, functions: functions)
            return nil
        } catch let error as ActionValidationError {
            return error
        } catch {
            return nil
        }
    }

    @Test func aGoodActionPasses() {
        #expect(problem(action(backend: .function("t.ok"))) == nil)
    }

    @Test func idsMustLookLikePrefixedLowercaseNames() {
        #expect(problem(action("noprefix", backend: .function("t.ok"))) == .badID)
        #expect(problem(action("ctx:Upper", backend: .function("t.ok"))) == .badID)
        #expect(problem(action("ctx:has space", backend: .function("t.ok"))) == .badID)
    }

    @Test func placeholdersCannotReachProgramText() {
        let interpreterScript = ShellBackend(executable: "/bin/sh", arguments: [template("-c"), template("echo {text}")])
        #expect(problem(action(backend: .shell(interpreterScript))) == .placeholderInScript)
        let noFlag = ShellBackend(executable: "/bin/sh", arguments: [template("{text}")])
        #expect(problem(action(backend: .shell(noFlag))) == .placeholderInScript)
        let python = ShellBackend(executable: "/usr/bin/python3", arguments: [template("-c"), template("print('{text}')")])
        #expect(problem(action(backend: .shell(python))) == .placeholderInScript)
        let env = ShellBackend(executable: "/usr/bin/env", arguments: [template("{text}")])
        #expect(problem(action(backend: .shell(env))) == .placeholderInScript)
        let executable = ShellBackend(executable: "/bin/{text}")
        #expect(problem(action(backend: .shell(executable))) == .placeholderInExecutable)
        let relative = ShellBackend(executable: "echo")
        #expect(problem(action(backend: .shell(relative))) == .executableNotAbsolute)
    }

    @Test func positionalValuesAfterALiteralScriptAreFine() {
        let ok = ShellBackend(
            executable: "/bin/sh", arguments: [template("-c"), template("printf %s \"$1\""), template("sh"), template("{text}")])
        #expect(problem(action(backend: .shell(ok))) == nil)
    }

    @Test func textValuesAsWholeArgumentsNeedADoubleDash() {
        let bare = ShellBackend(executable: "/usr/bin/say", arguments: [template("{text}")])
        #expect(problem(action(backend: .shell(bare))) == .optionInjection)
        let guarded = ShellBackend(executable: "/usr/bin/say", arguments: [template("--"), template("{text}")])
        #expect(problem(action(backend: .shell(guarded))) == nil)
        let embedded = ShellBackend(executable: "/usr/bin/say", arguments: [template("v={text}")])
        #expect(problem(action(backend: .shell(embedded))) == nil)
    }

    @Test func listVariablesStandAlone() {
        let embedded = ShellBackend(executable: "/usr/bin/open", arguments: [template("x{files}")])
        #expect(problem(action(requires: [.selectedFiles], backend: .shell(embedded))) == .listVariableNotAlone)
        let alone = ShellBackend(executable: "/usr/bin/open", arguments: [template("-R"), template("{files}")])
        #expect(problem(action(requires: [.selectedFiles], backend: .shell(alone))) == nil)
    }

    @Test func variablesNeedTheirContextDeclared() {
        let shell = ShellBackend(executable: "/bin/cat", standardInput: .text)
        #expect(problem(action(requires: [.pageURL], backend: .shell(shell))) == .variableNeedsContext(.text))
        let dir = ShellBackend(executable: "/usr/bin/open", arguments: [template("{directory}")])
        #expect(problem(action(requires: [.folder], backend: .shell(dir))) == nil)
        #expect(problem(action(requires: [.selectedFiles], backend: .shell(dir))) == nil)
        #expect(problem(action(requires: [.pageURL], backend: .shell(dir))) == .variableNeedsContext(.directory))
    }

    @Test func urlTemplatesKeepPlaceholdersOutOfTheDestination() {
        #expect(problem(action(backend: .urlScheme(template("https://{text}.evil.com/")))) == .urlPlaceholderBeforePath)
        #expect(problem(action(backend: .urlScheme(template("https://example.com{text}")))) == .urlPlaceholderBeforePath)
        #expect(problem(action(backend: .urlScheme(template("javascript:alert({text})")))) == .urlSchemeNotAllowed("javascript"))
        #expect(problem(action(backend: .urlScheme(template("file:///{text}")))) == .urlSchemeNotAllowed("file"))
        #expect(problem(action(backend: .urlScheme(template("{text}")))) == .badURLTemplate)
        #expect(problem(action(backend: .urlScheme(template("https://example.com/?q={text}")))) == nil)
        #expect(problem(action(backend: .urlScheme(template("x-web-search://?{text}")))) == nil)
    }

    @Test func otherRules() {
        #expect(problem(action(backend: .function("missing"))) == .unknownFunction("missing"))
        #expect(problem(action(requires: [.pageURL], backend: .function("t.ok"), output: .replaceSelection)) == .replaceNeedsSelection)
        #expect(problem(action(requires: [], backend: .function("t.ok"))) == .noRequirements)
        #expect(problem(action(backend: .function("t.ok"), timeout: 0)) == .badTimeout)
        #expect(problem(action(backend: .shortcut(ShortcutBackend(name: "-x")))) == .badShortcutName)
        #expect(problem(action(backend: .appleScript(AppleScriptBackend(source: "  ")))) == .emptyScript)
    }

    @Test func templatesParseBracesAndRejectUnknownNames() throws {
        #expect(try ActionTemplate("a {{b}} {text}").parts == [.literal("a {b} "), .variable(.text)])
        #expect(throws: ActionTemplate.ParseError.unknownVariable("nope")) { try ActionTemplate("{nope}") }
        #expect(throws: ActionTemplate.ParseError.unbalancedBrace) { try ActionTemplate("{text") }
        #expect(throws: ActionTemplate.ParseError.unbalancedBrace) { try ActionTemplate("a}") }
    }
}
