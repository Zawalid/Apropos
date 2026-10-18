import AppKit
import CryptoKit
import Foundation
import Testing

@testable import Apropos

@Suite struct TextToolsTests {
    @Test func caseConversions() {
        #expect(TextTools.camelCase("hello big_world-FOO bar") == "helloBigWorldFooBar")
        #expect(TextTools.snakeCase("helloWorld HTTPServer") == "hello_world_http_server")
        #expect(TextTools.kebabCase("Hello World_again") == "hello-world-again")
        #expect(TextTools.words(in: "parseJSON2Value") == ["parse", "JSON2", "Value"])
        #expect(TextTools.titleCase("the quick brown fox") == "The Quick Brown Fox")
    }

    @Test func lineTools() {
        #expect(TextTools.sortLines("b\na\nC\n10\n9") == "9\n10\na\nb\nC")
        #expect(TextTools.uniqueLines("a\nb\na\nc\nb\n") == "a\nb\nc")
        #expect(TextTools.joinLines(" a \n\n b\r\nc") == "a b c")
        #expect(TextTools.trim("  x \n") == "x")
        #expect(TextTools.lines("a\r\nb\n") == ["a", "b"])
    }

    @Test func wrappingAndCounts() {
        #expect(TextTools.quote(" hi ") == "\u{201C}hi\u{201D}")
        #expect(TextTools.codeBlock("let a = 1\n") == "```\nlet a = 1\n```")
        #expect(TextTools.markdownQuote("one\n\ntwo") == "> one\n>\n> two")
        #expect(TextTools.counts("one two\nthree") == "3 words, 13 characters, 2 lines")
        #expect(TextTools.counts("a") == "1 word, 1 character, 1 line")
    }

    @Test func encodings() throws {
        #expect(TextTools.urlEncode("a b&c/\u{00E9}") == "a%20b%26c%2F%C3%A9")
        #expect(try TextTools.urlDecode("a%20b%26c") == "a b&c")
        #expect(throws: TextToolError.invalidInput) { try TextTools.urlDecode("%zz") }
        #expect(TextTools.base64Encode("h\u{00E9}llo") == "aMOpbGxv")
        #expect(try TextTools.base64Decode("aMOpbGxv") == "h\u{00E9}llo")
        #expect(try TextTools.base64Decode("aGk") == "hi")
        #expect(throws: TextToolError.invalidInput) { try TextTools.base64Decode("***") }
    }

    @Test func json() throws {
        #expect(try TextTools.jsonMinify("{ \"b\": 1,\n \"a\": [1, 2] }") == "{\"a\":[1,2],\"b\":1}")
        let pretty = try TextTools.jsonPretty("{\"b\":1,\"a\":\"x/y\"}")
        #expect(pretty.contains("\"a\" : \"x/y\"") && pretty.contains("\n"))
        #expect(throws: TextToolError.invalidInput) { try TextTools.jsonPretty("{nope") }
        #expect(TextTools.isJSON("{\"a\":1}") && TextTools.isJSON(" [1] "))
        #expect(!TextTools.isJSON("12") && !TextTools.isJSON("{bad"))
    }

    @Test func webURLDetection() {
        #expect(TextTools.webURL(from: " https://example.com/a?b=1 ")?.host == "example.com")
        #expect(TextTools.webURL(from: "www.example.com")?.absoluteString == "https://www.example.com")
        #expect(TextTools.webURL(from: "two words") == nil)
        #expect(TextTools.webURL(from: "javascript:alert(1)") == nil)
        #expect(TextTools.webURL(from: "ftp://example.com") == nil)
        #expect(TextTools.webURL(from: "hello") == nil)
    }

    @Test func remoteUrlsBecomeWebAddresses() {
        let expected = "https://github.com/me/repo"
        #expect(TextTools.repositoryWebURL(fromRemote: "git@github.com:me/repo.git")?.absoluteString == expected)
        #expect(TextTools.repositoryWebURL(fromRemote: "https://github.com/me/repo.git")?.absoluteString == expected)
        #expect(TextTools.repositoryWebURL(fromRemote: "https://user:token@github.com/me/repo")?.absoluteString == expected)
        #expect(TextTools.repositoryWebURL(fromRemote: "ssh://git@github.com:22/me/repo.git")?.absoluteString == expected)
        #expect(TextTools.repositoryWebURL(fromRemote: "/local/path/repo.git") == nil)
        #expect(TextTools.repositoryWebURL(fromRemote: "") == nil)
        #expect(TextTools.repositoryWebURL(fromRemote: "file:///tmp/repo") == nil)
    }
}

@Suite struct ActionCatalogueTests {
    private let library = ActionPackLibrary.bundled()

    @Test func theBundledCatalogueLoadsCleanly() {
        #expect(library.issues.isEmpty, "\(library.issues)")
        #expect(library.actions.count >= 30)
        #expect(Set(library.actions.map(\.id)).count == library.actions.count)
        #expect(library.actions.allSatisfy { $0.id.rawValue.hasPrefix("ctx:") })
    }

    @Test func everySymbolExists() {
        let missing = library.actions.map(\.symbol).filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "\(missing)")
    }

    @Test func everyBuiltInFunctionIsReferencedAndExists() {
        var referenced = Set<String>()
        for action in library.actions { if case .function(let name) = action.backend { referenced.insert(name) } }
        #expect(referenced.isSubset(of: ActionFunctionRegistry.builtin.names))
        #expect(ActionFunctionRegistry.builtin.names.subtracting(referenced).isEmpty)
    }

    private func ids(_ values: ContextValues, bundle: String? = "x") -> Set<String> {
        Set(library.applicable(to: values, bundleID: bundle).map(\.id.rawValue))
    }

    @Test func actionsAppearOnlyWhenTheirContextExists() {
        #expect(ids(ContextValues()).isEmpty)

        let text = ids(ContextValues(selectedText: "hello world"))
        #expect(text.contains("ctx:text.upper") && text.contains("ctx:text.search-web"))
        #expect(!text.contains("ctx:text.sort-lines"))  // single line
        #expect(!text.contains("ctx:text.json-pretty"))  // not JSON
        #expect(!text.contains("ctx:text.open-link"))  // not a URL
        #expect(!text.contains { $0.hasPrefix("ctx:files.") || $0.hasPrefix("ctx:page.") || $0.hasPrefix("ctx:git.") })

        #expect(ids(ContextValues(selectedText: "b\na")).contains("ctx:text.sort-lines"))
        #expect(ids(ContextValues(selectedText: "{\"a\":1}")).contains("ctx:text.json-pretty"))
        #expect(ids(ContextValues(selectedText: "https://example.com")).contains("ctx:text.open-link"))

        let files = ids(ContextValues(selectedFiles: [URL(fileURLWithPath: "/tmp/a.txt")]))
        #expect(files == ["ctx:files.copy-path", "ctx:files.copy-name", "ctx:files.reveal", "ctx:files.terminal", "ctx:files.zip", "ctx:files.sha256"])

        let page = ids(ContextValues(pageURL: URL(string: "https://example.com")))
        #expect(page == ["ctx:page.copy-url", "ctx:page.copy-markdown-link", "ctx:page.copy-title"])

        let repo = ids(
            ContextValues(
                folderURL: URL(fileURLWithPath: "/r"), gitBranch: "main", repoRoot: URL(fileURLWithPath: "/r")))
        #expect(repo == ["ctx:folder.terminal", "ctx:git.copy-branch", "ctx:git.copy-hash", "ctx:git.open-remote"])
    }

    @Test func groupsFollowTheContext() {
        func group(_ id: String) -> ActionGroup? { library.action(for: ActionID(rawValue: id))?.group }
        #expect(group("ctx:text.upper") == .selectedText)
        #expect(group("ctx:files.zip") == .selectedFiles)
        #expect(group("ctx:page.copy-url") == .page)
        #expect(group("ctx:git.copy-branch") == .folder)
        #expect(group("ctx:folder.terminal") == .folder)
    }

    @Test func textTransformsReplaceAndInformationalOnesDoNot() {
        func output(_ id: String) -> ActionOutput? { library.action(for: ActionID(rawValue: id))?.output }
        #expect(output("ctx:text.upper") == .replaceSelection)
        #expect(output("ctx:text.count") == .notify)
        #expect(output("ctx:files.copy-path") == .clipboard)
        #expect(output("ctx:files.reveal") == ActionOutput.none)
    }

    // MARK: Running the catalogue

    private func run(
        _ id: String, _ values: ContextValues, recorder: ServiceRecorder = ServiceRecorder()
    ) async -> (Result<ActionOutcome, ActionError>, ServiceRecorder) {
        guard let action = library.action(for: ActionID(rawValue: id)) else {
            Issue.record("no action \(id)")
            return (.failure(.notApplicable), recorder)
        }
        let engine = ActionEngine(functions: library.functions, services: recorder.services)
        return (await engine.run(action, values: values, target: TargetApp(pid: 7, bundleID: "x", name: "X")), recorder)
    }

    @Test func textActionsProduceTheExpectedText() async {
        let (result, recorder) = await run("ctx:text.snake", ContextValues(selectedText: "Hello Big World"))
        #expect((try? result.get().delivery) == .replaced)
        #expect(recorder.replaced.first?.0 == "hello_big_world")

        let (count, countRecorder) = await run("ctx:text.count", ContextValues(selectedText: "a b c"))
        #expect((try? count.get().notice) == "3 words, 5 characters, 1 line")
        #expect(countRecorder.notices.count == 1)

        let (bad, _) = await run("ctx:text.base64-decode", ContextValues(selectedText: "***"))
        #expect(bad == .failure(.invalidInput))
    }

    @Test func pageActions() async {
        let values = ContextValues(pageURL: URL(string: "https://swift.org/blog"), pageTitle: "Swift [Blog]")
        let (link, recorder) = await run("ctx:page.copy-markdown-link", values)
        #expect((try? link.get().delivery) == .copied)
        #expect(recorder.clipboard == ["[Swift \\[Blog\\]](https://swift.org/blog)"])
        let (url, urlRecorder) = await run("ctx:page.copy-url", values)
        _ = url
        #expect(urlRecorder.clipboard == ["https://swift.org/blog"])
    }

    @Test func fileActions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("apropos-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("hello world.txt")
        try Data("hello\n".utf8).write(to: file)
        let values = ContextValues(selectedFiles: [file])

        let (_, hashed) = await run("ctx:files.sha256", values)
        let expected = SHA256.hash(data: Data("hello\n".utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(hashed.clipboard == [expected])

        let (_, paths) = await run("ctx:files.copy-path", values)
        #expect(paths.clipboard == [file.path])
        let (_, names) = await run("ctx:files.copy-name", values)
        #expect(names.clipboard == ["hello world.txt"])

        let (zipped, zipRecorder) = await run("ctx:files.zip", values)
        #expect((try? zipped.get().notice) == "Created hello world.zip")
        #expect(zipRecorder.notices == ["Created hello world.zip"])
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("hello world.zip").path))
        let (again, _) = await run("ctx:files.zip", values)
        #expect((try? again.get().notice) == "Created hello world 2.zip")
    }

    @Test func zipRefusesFilesFromDifferentFolders() async {
        let values = ContextValues(selectedFiles: [URL(fileURLWithPath: "/tmp/a/x.txt"), URL(fileURLWithPath: "/tmp/b/y.txt")])
        let (result, _) = await run("ctx:files.zip", values)
        if case .failure(.unavailable) = result {} else { Issue.record("expected unavailable") }
    }

    @Test func gitHashRunsGitInTheRepository() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("apropos-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func git(_ arguments: [String]) async throws {
            _ = try await ProcessRunner.run(
                ProcessRequest(
                    executable: "/usr/bin/git", arguments: ["-C", directory.path] + arguments,
                    environment: ["GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"]))
        }
        try await git(["init", "-q"])
        try await git(["commit", "-q", "--allow-empty", "-m", "first"])
        let values = ContextValues(folderURL: directory, gitBranch: "main", repoRoot: directory)
        let (result, recorder) = await run("ctx:git.copy-hash", values)
        #expect((try? result.get().delivery) == .copied)
        let hash = recorder.clipboard.first ?? ""
        #expect(hash.count >= 7 && hash.allSatisfy(\.isHexDigit))
    }

    @Test func openRemoteUsesOriginThenTheFirstRemote() async throws {
        final class Calls: @unchecked Sendable {
            var arguments: [[String]] = []
        }
        let calls = Calls()
        let recorder = ServiceRecorder()
        var services = recorder.services
        services.process = { request in
            calls.arguments.append(request.arguments)
            let joined = request.arguments.joined(separator: " ")
            if joined.hasSuffix("remote.origin.url") { return ProcessOutput(status: 1, standardOutput: Data(), standardErrorByteCount: 0) }
            if joined.hasSuffix("remote") { return ProcessOutput(status: 0, standardOutput: Data("upstream\n".utf8), standardErrorByteCount: 0) }
            return ProcessOutput(status: 0, standardOutput: Data("git@github.com:me/repo.git\n".utf8), standardErrorByteCount: 0)
        }
        guard let action = library.action(for: "ctx:git.open-remote") else { return }
        let engine = ActionEngine(functions: library.functions, services: services)
        let values = ContextValues(folderURL: URL(fileURLWithPath: "/r"), gitBranch: "main", repoRoot: URL(fileURLWithPath: "/r"))
        let result = await engine.run(action, values: values, target: nil)
        #expect((try? result.get().delivery) == ActionDelivery.done)
        #expect(recorder.opened.map(\.absoluteString) == ["https://github.com/me/repo"])
    }
}

@Suite struct ActionPackLoaderTests {
    private func library(_ json: String) -> ActionPackLibrary {
        var library = ActionPackLibrary()
        library.add(packData: Data(json.utf8), source: "test.json")
        return library
    }

    private let upperDefinition =
        #"{"id":"user:shout","title":"Shout","symbol":"star","requires":["selectedText"],"backend":{"type":"function","name":"text.upper"},"output":"replaceSelection"}"#

    @Test func aMinimalDefinitionLoadsWithDefaults() throws {
        let loaded = library(#"{"schemaVersion":1,"actions":[\#(upperDefinition)]}"#)
        #expect(loaded.issues.isEmpty)
        let action = try #require(loaded.action(for: "user:shout"))
        #expect(action.group == .selectedText && action.timeout == 10 && !action.needsConfirmation)
        #expect(action.apps == .anyApp)
    }

    @Test func everyBackendTypeParses() {
        let json = """
            {"schemaVersion":1,"actions":[
            {"id":"user:a","title":"A","symbol":"star","requires":["selectedText"],"backend":{"type":"shell","executable":"/bin/cat","stdin":"text"}},
            {"id":"user:b","title":"B","symbol":"star","requires":["selectedText"],"backend":{"type":"appleScript","source":"on run argv\\nreturn item 1 of argv\\nend run","arguments":["{text}"]}},
            {"id":"user:c","title":"C","symbol":"star","requires":["selectedText"],"backend":{"type":"shortcut","name":"My Shortcut","input":"text"}},
            {"id":"user:d","title":"D","symbol":"star","requires":["selectedText"],"backend":{"type":"urlScheme","url":"https://example.com/?q={text}"}},
            {"id":"user:e","title":"E","symbol":"star","requires":["selectedText"],"backend":{"type":"keyPress","keyCode":9,"modifiers":["command","shift"]}}
            ]}
            """
        let loaded = library(json)
        #expect(loaded.issues.isEmpty, "\(loaded.issues)")
        #expect(loaded.actions.count == 5)
    }

    @Test func badEntriesAreSkippedAndReportedWithoutBlockingTheRest() {
        let json = """
            {"schemaVersion":1,"actions":[
            \(upperDefinition),
            {"id":"user:inject","title":"X","symbol":"star","requires":["selectedText"],"backend":{"type":"shell","executable":"/bin/sh","arguments":["-c","echo {text}"]}},
            {"id":"user:nofunc","title":"X","symbol":"star","requires":["selectedText"],"backend":{"type":"function","name":"nope"}},
            {"id":"BAD ID","title":"X","symbol":"star","requires":["selectedText"],"backend":{"type":"function","name":"text.upper"}},
            {"id":"user:weird","title":"X","symbol":"star","requires":["selectedText"],"backend":{"type":"quantum"}},
            {"id":"user:broken"}
            ]}
            """
        let loaded = library(json)
        #expect(loaded.actions.map(\.id.rawValue) == ["user:shout"])
        #expect(loaded.issues.count == 5)
        #expect(loaded.issues.contains { $0.actionID == "user:inject" })
        #expect(loaded.issues.allSatisfy { !$0.reason.contains("echo") })
    }

    @Test func wholeFileProblemsAreReported() {
        #expect(library("not json").issues.first?.reason == "not a valid pack file")
        #expect(library(#"{"schemaVersion":99,"actions":[]}"#).issues.first?.reason == "written by a newer version")
        #expect(library(#"{"actions":[]}"#).issues.count == 1)
    }

    @Test func laterPacksOverrideEarlierActionsWithTheSameID() throws {
        var loaded = library(#"{"schemaVersion":1,"actions":[\#(upperDefinition)]}"#)
        loaded.add(packData: Data(upperDefinition.replacingOccurrences(of: "Shout", with: "Yell").utf8).withWrapper, source: "two.json")
        #expect(loaded.actions.count == 1)
        #expect(loaded.action(for: "user:shout")?.title == "Yell")
    }

    @Test func userDirectoryIsLoadedAfterTheBuiltIns() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("apropos-actions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"schemaVersion":1,"actions":[\#(upperDefinition)]}"#.utf8).write(to: directory.appendingPathComponent("mine.json"))
        try Data("garbage".utf8).write(to: directory.appendingPathComponent("bad.json"))
        let loaded = ActionPackLibrary.bundled(plus: directory)
        #expect(loaded.action(for: "user:shout") != nil && loaded.action(for: "ctx:text.upper") != nil)
        #expect(loaded.issues.map(\.source) == ["bad.json"])
    }
}

private extension Data {
    /// Wraps a single action definition in a pack envelope.
    var withWrapper: Data {
        Data(#"{"schemaVersion":1,"actions":["#.utf8) + self + Data("]}".utf8)
    }
}
