import Foundation
import Testing

@testable import Apropos

private struct FakeFinderSelection: FinderSelectionReading {
    var paths: [String]
    func selectedPaths(timeout: TimeInterval) -> [String] { paths }
}

private struct RootGit: GitBranchLookup {
    func branch(forFolder path: String, timeout: TimeInterval) -> String? { "main" }
    func repoRoot(forFolder path: String, timeout: TimeInterval) -> String? { "/Users/me/repo" }
}

private func windowRoot(_ configure: (FakeAX) -> Void) -> FakeAX {
    let window = FakeAX(role: "AXWindow", configure)
    return FakeAX { $0.singles[AXAttr.focusedWindow] = window; $0.lists[AXAttr.windows] = [window] }
}

private func service(
    _ root: FakeAX, providers: [any ContextProvider] = ContextProviderRegistry.defaultProviders,
    privacy: ContextPrivacy = ContextPrivacy()
) -> ContextService {
    ContextService(
        registry: ContextProviderRegistry(providers: providers), privacy: privacy, git: RootGit(),
        isTrusted: { true }, makeRoot: { _ in root })
}

private func target(_ id: String) -> TargetApp { TargetApp(pid: 1, bundleID: id, name: "App") }

@Suite struct ContextValuesTests {
    @Test func fullSelectionIsKeptBeyondTheChipLimitButCapped() async {
        let huge = String(repeating: "a", count: ContextLimits.maxValueTextLength + 50)
        let focused = FakeAX(role: "AXTextArea") { $0.strings[AXAttr.selectedText] = huge }
        let root = windowRoot { _ in }
        root.singles[AXAttr.focusedElement] = focused
        let snapshot = await service(root).snapshot(for: target("some.app"))
        #expect(snapshot.fields.selectedText?.count == ContextLimits.maxSelectionLength)
        #expect(snapshot.values.selectedText?.count == ContextLimits.maxValueTextLength)
        #expect(snapshot.values.has(.selectedText))
    }

    @Test func secureFieldsLeaveNoValues() async {
        let focused = FakeAX(role: "AXTextField") {
            $0.strings[AXAttr.subrole] = "AXSecureTextField"
            $0.strings[AXAttr.selectedText] = "hunter2"
        }
        let root = windowRoot { _ in }
        root.singles[AXAttr.focusedElement] = focused
        let snapshot = await service(root).snapshot(for: target("some.app"))
        #expect(snapshot.values.selectedText == nil)
        #expect(snapshot.values.isEmpty)
    }

    @Test func blockedSelectionAppsLeaveNoSelectionValue() async {
        let focused = FakeAX(role: "AXTextArea") { $0.strings[AXAttr.selectedText] = "secret note" }
        let root = windowRoot { $0.strings[AXAttr.title] = "Vault" }
        root.singles[AXAttr.focusedElement] = focused
        let snapshot = await service(root).snapshot(for: target("com.1password.1password"))
        #expect(snapshot.values.selectedText == nil)
    }

    @Test func disabledAppsHaveNoValuesAtAll() async {
        let focused = FakeAX(role: "AXTextArea") { $0.strings[AXAttr.selectedText] = "anything" }
        let root = windowRoot { $0.strings[AXAttr.document] = "file:///Users/me/a.txt" }
        root.singles[AXAttr.focusedElement] = focused
        let privacy = ContextPrivacy(disabledBundleIDs: ["some.app"])
        let snapshot = await service(root, privacy: privacy).snapshot(for: target("some.app"))
        #expect(snapshot.values.isEmpty)
        #expect(snapshot.gaps == [.disabledForApp])
    }

    @Test func browserValuesCarryPageURLAndTitleButOnlyWebSchemes() async {
        let root = windowRoot {
            $0.strings[AXAttr.title] = "Swift Forums"
            $0.strings[AXAttr.document] = "https://www.swift.org/forums/t/1?x=1"
        }
        let snapshot = await service(root).snapshot(for: target("com.apple.Safari"))
        #expect(snapshot.values.pageURL?.absoluteString == "https://www.swift.org/forums/t/1?x=1")
        #expect(snapshot.values.pageTitle == "Swift Forums")
        #expect(ContextValues(fields: ContextFields(url: "javascript:alert(1)")).pageURL == nil)
        #expect(ContextValues(fields: ContextFields(url: "file:///etc/passwd")).pageURL == nil)
    }

    @Test func folderAndRepoComeFromTheDocumentWhenThereIsNoFolder() async {
        let root = windowRoot {
            $0.strings[AXAttr.title] = "P - File.swift"
            $0.strings[AXAttr.document] = "file:///Users/me/repo/Sources/File.swift"
        }
        let snapshot = await service(root).snapshot(for: target("com.apple.dt.Xcode"))
        #expect(snapshot.values.folderURL?.path == "/Users/me/repo/Sources")
        #expect(snapshot.values.documentURL?.path == "/Users/me/repo/Sources/File.swift")
        #expect(snapshot.values.repoRoot?.path == "/Users/me/repo")
        #expect(snapshot.values.gitBranch == "main")
        #expect(snapshot.values.has(.gitRepo) && snapshot.values.has(.folder))
    }

    @Test func finderSelectedFilesAreReadOnlyWhenSomethingIsSelected() async {
        let rows = [FakeAX(role: "AXRow")]
        let outline = FakeAX(role: "AXOutline") { $0.lists[AXAttr.selectedRows] = rows }
        let root = windowRoot {
            $0.strings[AXAttr.document] = "file:///Users/me/Projects"
            $0.lists[AXAttr.children] = [outline]
        }
        let provider = FinderProvider(selection: FakeFinderSelection(paths: ["/Users/me/Projects/a.txt", "relative.txt"]))
        let snapshot = await service(root, providers: [provider]).snapshot(for: target("com.apple.finder"))
        #expect(snapshot.values.selectedFiles.map(\.path) == ["/Users/me/Projects/a.txt"])

        let empty = windowRoot { $0.strings[AXAttr.document] = "file:///Users/me/Projects" }
        let none = await service(empty, providers: [provider]).snapshot(for: target("com.apple.finder"))
        #expect(none.values.selectedFiles.isEmpty)
    }

    @Test func appleScriptOutputParsing() {
        #expect(AppleScriptFinderSelection.parse("/a/b.txt\u{1F}/c/d e.txt\n") == ["/a/b.txt", "/c/d e.txt"])
        #expect(AppleScriptFinderSelection.parse("") == [])
        #expect(AppleScriptFinderSelection.parse("not a path") == [])
    }

    @Test func valuesNeverPrintTheirContents() {
        let values = ContextValues(
            selectedText: "TOPSECRET", selectedFiles: [URL(fileURLWithPath: "/private/TOPSECRET.txt")],
            pageURL: URL(string: "https://example.com/TOPSECRET"))
        #expect(!"\(values)".contains("TOPSECRET"))
        #expect(!String(reflecting: values).contains("TOPSECRET"))
        var dumped = ""
        dump(values, to: &dumped)
        #expect(!dumped.contains("TOPSECRET"))
        let snapshot = ContextSnapshot(appName: "A", bundleID: nil, values: values)
        #expect(!"\(snapshot.values)".contains("TOPSECRET"))
    }
}

@Suite struct ProcessRunnerTests {
    @Test func passesArgumentsAndStdinWithoutAShell() async throws {
        let nasty = "$(touch /tmp/apropos-pwn); `id` \"q\" 'q' ; | & \n -n"
        let echoed = try await ProcessRunner.run(ProcessRequest(executable: "/bin/echo", arguments: ["--", nasty]))
        #expect(echoed.text.contains("$(touch /tmp/apropos-pwn)"))
        let cat = try await ProcessRunner.run(
            ProcessRequest(executable: "/bin/cat", standardInput: Data(nasty.utf8)))
        #expect(cat.text == nasty)
        #expect(!FileManager.default.fileExists(atPath: "/tmp/apropos-pwn"))
    }

    @Test func timesOutAndKills() async {
        let started = Date()
        await #expect(throws: ProcessRunError.timedOut) {
            try await ProcessRunner.run(ProcessRequest(executable: "/bin/sleep", arguments: ["30"], timeout: 0.3))
        }
        #expect(Date().timeIntervalSince(started) < 20)  // the work would take 30 s; a busy machine needs slack
    }

    @Test func cancellationStopsTheProcess() async {
        let task = Task {
            try await ProcessRunner.run(ProcessRequest(executable: "/bin/sleep", arguments: ["30"], timeout: 30))
        }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = await task.result
        #expect(throws: ProcessRunError.cancelled) { try result.get() }
    }

    @Test func outputIsCapped() async {
        await #expect(throws: ProcessRunError.outputTooLarge) {
            try await ProcessRunner.run(
                ProcessRequest(executable: "/usr/bin/yes", timeout: 5, outputLimit: 10_000))
        }
    }

    @Test func missingExecutableIsALaunchFailure() async {
        await #expect(throws: ProcessRunError.launchFailed) {
            try await ProcessRunner.run(ProcessRequest(executable: "/nonexistent/tool"))
        }
    }

    @Test func nonZeroStatusIsReportedNotThrown() async throws {
        let output = try await ProcessRunner.run(ProcessRequest(executable: "/usr/bin/false"))
        #expect(output.status == 1)
    }

    @Test func environmentIsMinimalPlusRequested() async throws {
        let output = try await ProcessRunner.run(
            ProcessRequest(executable: "/usr/bin/env", environment: ["APROPOS_TEXT": "hi"]))
        #expect(output.text.contains("APROPOS_TEXT=hi"))
        #expect(!output.text.contains("SSH_AUTH_SOCK"))
    }
}
