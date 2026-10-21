import Foundation
import Testing

@testable import Apropos

/// A fake Accessibility tree: attributes are plain dictionaries.
final class FakeAX: AXNode, @unchecked Sendable {
    var strings: [String: String] = [:]
    var ints: [String: Int] = [:]
    var singles: [String: FakeAX] = [:]
    var lists: [String: [FakeAX]] = [:]
    var counts: [String: Int] = [:]

    init(role: String? = nil, _ configure: (FakeAX) -> Void = { _ in }) {
        if let role { strings[AXAttr.role] = role }
        configure(self)
    }

    func string(_ attribute: String) -> String? { strings[attribute] }
    func int(_ attribute: String) -> Int? { ints[attribute] }
    func node(_ attribute: String) -> (any AXNode)? { singles[attribute] }
    func nodes(_ attribute: String) -> [any AXNode] { lists[attribute] ?? [] }
    func count(_ attribute: String) -> Int? { counts[attribute] ?? lists[attribute]?.count }
}

struct FixedGit: GitBranchLookup {
    var branch: String?
    func branch(forFolder path: String, timeout: TimeInterval) -> String? { branch }
}

struct SlowProvider: ContextProvider {
    let bundleIDs: Set<String> = ["slow.app"]
    let timeout: TimeInterval = 0.05
    func read(_ target: ContextTarget) -> ContextFields {
        Thread.sleep(forTimeInterval: 1.5)
        return ContextFields(url: "https://late.example")
    }
}

struct StubProvider: ContextProvider {
    var bundleIDs: Set<String> = ["stub.app"]
    var timeout: TimeInterval = 0.2
    var fields: ContextFields
    func read(_ target: ContextTarget) -> ContextFields { fields }
}

private func app(_ bundleID: String, name: String = "App") -> TargetApp {
    TargetApp(pid: 1, bundleID: bundleID, name: name)
}

private func makeService(
    root: FakeAX, providers: [any ContextProvider] = ContextProviderRegistry.defaultProviders,
    privacy: ContextPrivacy = ContextPrivacy(), branch: String? = nil, trusted: Bool = true
) -> ContextService {
    ContextService(
        registry: ContextProviderRegistry(providers: providers), privacy: privacy, git: FixedGit(branch: branch),
        isTrusted: { trusted }, makeRoot: { _ in root })
}

private func window(_ configure: (FakeAX) -> Void) -> FakeAX {
    let window = FakeAX(role: "AXWindow", configure)
    return FakeAX { $0.singles[AXAttr.focusedWindow] = window; $0.lists[AXAttr.windows] = [window] }
}

@Suite struct ContextTests {
    @Test func genericReadsTitleDocumentSelectionAndWindowCount() async {
        let focused = FakeAX(role: "AXTextArea") { $0.strings[AXAttr.selectedText] = "hello world" }
        let root = window {
            $0.strings[AXAttr.title] = "Notes"
            $0.strings[AXAttr.document] = "file:///Users/me/doc.md"
        }
        root.singles[AXAttr.focusedElement] = focused
        root.counts[AXAttr.windows] = 3
        let snapshot = await makeService(root: root, branch: "main").snapshot(for: app("some.app"))
        #expect(snapshot.fields.documentPath == "/Users/me/doc.md")
        #expect(snapshot.fields.windowCount == 3)
        #expect(snapshot.items.map(\.kind) == [.document, .branch, .selection])
        #expect(snapshot.item(.document)?.label == "doc.md")
        #expect(snapshot.item(.branch)?.label == "main")
    }

    @Test func secureFieldSelectionIsNeverRead() async {
        let focused = FakeAX(role: "AXTextField") {
            $0.strings[AXAttr.subrole] = "AXSecureTextField"
            $0.strings[AXAttr.selectedText] = "hunter2"
        }
        let root = window { $0.strings[AXAttr.title] = "Login" }
        root.singles[AXAttr.focusedElement] = focused
        let snapshot = await makeService(root: root).snapshot(for: app("some.app"))
        #expect(snapshot.fields.selectedText == nil)
        #expect(snapshot.item(.selection) == nil)
    }

    @Test func selectionIsTruncated() async {
        let long = String(repeating: "a", count: ContextLimits.maxSelectionLength + 500)
        let focused = FakeAX(role: "AXTextArea") { $0.strings[AXAttr.selectedText] = long }
        let root = window { _ in }
        root.singles[AXAttr.focusedElement] = focused
        let snapshot = await makeService(root: root).snapshot(for: app("some.app"))
        #expect(snapshot.fields.selectedText?.count == ContextLimits.maxSelectionLength)
        #expect((snapshot.item(.selection)?.label.count ?? 0) <= ContextLimits.maxLabelLength)
    }

    @Test func finderReportsFolderAndSelectedCount() async {
        let rows = [FakeAX(role: "AXRow"), FakeAX(role: "AXRow")]
        let outline = FakeAX(role: "AXOutline") { $0.lists[AXAttr.selectedRows] = rows }
        let scroll = FakeAX(role: "AXScrollArea") { $0.lists[AXAttr.children] = [outline] }
        let root = window {
            $0.strings[AXAttr.title] = "Projects"
            $0.strings[AXAttr.document] = "file:///Users/me/Projects"
            $0.lists[AXAttr.children] = [scroll]
        }
        let snapshot = await makeService(root: root, branch: "dev").snapshot(for: app("com.apple.finder"))
        #expect(snapshot.fields.folderPath == "/Users/me/Projects")
        #expect(snapshot.fields.selectedItemCount == 2)
        #expect(snapshot.items.map(\.kind) == [.folder, .branch, .selectionCount])
        #expect(snapshot.item(.selectionCount)?.label == "2 selected")
    }

    @Test func browserReadsURLFromDocumentAndHidesQuery() async {
        let focused = FakeAX(role: "AXStaticText") { $0.strings[AXAttr.selectedText] = "some quote" }
        let root = window {
            $0.strings[AXAttr.title] = "Swift Forums"
            $0.strings[AXAttr.document] = "https://www.swift.org/forums/t/1?token=secret"
        }
        root.singles[AXAttr.focusedElement] = focused
        let snapshot = await makeService(root: root).snapshot(for: app("com.apple.Safari"))
        #expect(snapshot.fields.url == "https://www.swift.org/forums/t/1?token=secret")
        #expect(snapshot.item(.url)?.label == "swift.org/forums/t/1")
        #expect(snapshot.item(.document)?.label == "Swift Forums")
        #expect(snapshot.fields.documentPath == nil)
    }

    @Test func chromiumURLComesFromTheWebArea() async {
        let area = FakeAX(role: "AXWebArea") { $0.strings[AXAttr.url] = "https://example.com/" }
        let group = FakeAX(role: "AXGroup") { $0.lists[AXAttr.children] = [area] }
        let root = window {
            $0.strings[AXAttr.title] = "Example"
            $0.lists[AXAttr.children] = [group]
        }
        let snapshot = await makeService(root: root).snapshot(for: app("com.google.Chrome"))
        #expect(snapshot.item(.url)?.label == "example.com")
    }

    @Test func xcodeUsesDocumentAndTitleWorkspace() async {
        let root = window {
            $0.strings[AXAttr.title] = "Apropos \u{2014} AXMenuReader.swift"
            $0.strings[AXAttr.document] = "file:///Users/me/Apropos/Sources/AXMenuReader.swift"
        }
        let snapshot = await makeService(root: root, branch: "feat/x").snapshot(for: app("com.apple.dt.Xcode"))
        #expect(snapshot.fields.workspace == "Apropos")
        #expect(snapshot.item(.document)?.label == "AXMenuReader.swift")
        #expect(snapshot.item(.branch)?.label == "feat/x")
    }

    @Test func xcodeFallsBackToTitleWhenNoDocument() async {
        let root = window { $0.strings[AXAttr.title] = "Apropos - Package.swift" }
        let snapshot = await makeService(root: root).snapshot(for: app("com.apple.dt.Xcode"))
        #expect(snapshot.item(.document)?.label == "Package.swift")
        #expect(snapshot.fields.workspace == "Apropos")
    }

    @Test func slowProviderTimesOutWithPartialSnapshot() async {
        let root = window { $0.strings[AXAttr.title] = "Doc" }
        let service = makeService(root: root, providers: [SlowProvider()])
        // No clock check: how long the call takes depends on how busy the machine is. A timed out gap and no URL show the
        // service gave up on the provider and did not wait for its late answer.
        let snapshot = await service.snapshot(for: app("slow.app"))
        #expect(snapshot.gaps.contains(.timedOut))
        #expect(snapshot.fields.url == nil)
        #expect(snapshot.fields.windowTitle == "Doc")
    }

    @Test func specificFieldsWinOverGeneric() async {
        let root = window { $0.strings[AXAttr.title] = "generic title" }
        let stub = StubProvider(fields: ContextFields(windowTitle: "specific title"))
        let snapshot = await makeService(root: root, providers: [stub]).snapshot(for: app("stub.app"))
        #expect(snapshot.fields.windowTitle == "specific title")
    }

    @Test func disabledAppReadsNothing() async {
        let root = window { $0.strings[AXAttr.title] = "Secret" }
        let privacy = ContextPrivacy(disabledBundleIDs: ["some.app"])
        let snapshot = await makeService(root: root, privacy: privacy).snapshot(for: app("some.app"))
        #expect(snapshot.items.isEmpty)
        #expect(snapshot.gaps == [.disabledForApp])
        #expect(snapshot.appName == "App")
    }

    @Test func untrustedYieldsEmptySnapshotNotAnError() async {
        let snapshot = await makeService(root: FakeAX(), trusted: false).snapshot(for: app("some.app"))
        #expect(snapshot.items.isEmpty)
        #expect(snapshot.gaps == [.notTrusted])
    }

    @Test func passwordManagerSelectionIsBlocked() async {
        let focused = FakeAX(role: "AXTextArea") { $0.strings[AXAttr.selectedText] = "secret note" }
        let root = window { $0.strings[AXAttr.title] = "Vault" }
        root.singles[AXAttr.focusedElement] = focused
        let snapshot = await makeService(root: root).snapshot(for: app("com.1password.1password"))
        #expect(snapshot.fields.selectedText == nil)
        #expect(snapshot.fields.windowTitle == "Vault")
    }

    @Test func privacyRoundTripsThroughDefaults() {
        let suite = "apropos.test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        ContextPrivacy(disabledBundleIDs: ["a.b", "c.d"]).save(to: defaults)
        #expect(ContextPrivacy.load(from: defaults).disabledBundleIDs == ["a.b", "c.d"])
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func gitReaderFindsBranchOfARepoAndIgnoresNonRepos() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apropos-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(GitBranchReader().branch(forFolder: dir.path, timeout: 1) == nil)
        let setup = Process()
        setup.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        setup.arguments = ["-C", dir.path, "init", "-q", "-b", "trunk"]
        try setup.run()
        setup.waitUntilExit()
        #expect(GitBranchReader().branch(forFolder: dir.path, timeout: 2) == "trunk")
        #expect(GitBranchReader().branch(forFolder: "relative/path", timeout: 1) == nil)
    }
}
