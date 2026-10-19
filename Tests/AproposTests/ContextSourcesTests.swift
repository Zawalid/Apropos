import Foundation
import Testing

@testable import Apropos

@MainActor
struct ContextSourcesTests {
    private func full() -> ContextFields {
        ContextFields(
            windowTitle: "Doc", documentPath: "/a/b.txt", url: "https://x.test", tabTitle: "Tab", folderPath: "/a",
            workspace: "W", gitBranch: "main", selectedText: "secret", selectedItemCount: 3, fullSelection: "secret",
            selectedFilePaths: ["/a/b.txt"], repoRoot: "/a")
    }

    @Test func eachSwitchedOffKindIsDropped() {
        var fields = full()
        ContextPrivacy(disabledKinds: [.selection]).filter(&fields)
        #expect(fields.selectedText == nil && fields.fullSelection == nil && fields.url != nil)
        fields = full()
        ContextPrivacy(disabledKinds: [.url]).filter(&fields)
        #expect(fields.url == nil && fields.tabTitle == nil && fields.selectedText != nil)
        fields = full()
        ContextPrivacy(disabledKinds: [.folder]).filter(&fields)
        #expect(fields.folderPath == nil && fields.selectedFilePaths == nil && fields.selectedItemCount == nil)
        fields = full()
        ContextPrivacy(disabledKinds: [.branch]).filter(&fields)
        #expect(fields.gitBranch == nil && fields.repoRoot == nil && fields.folderPath != nil)
        fields = full()
        ContextPrivacy(disabledKinds: [.document]).filter(&fields)
        #expect(fields.documentPath == nil && fields.windowTitle == nil)
    }

    @Test func nothingDisabledChangesNothing() {
        var fields = full()
        ContextPrivacy().filter(&fields)
        #expect(fields == full())
    }

    @Test func settingsMapToPrivacy() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-\(UUID().uuidString)/s.json")
        let store = SettingsStore(url: url, historyLimit: 1, writeDelay: .zero)
        #expect(store.contextPrivacy().disabledKinds.isEmpty)
        #expect(store.set(.stringList(["document", "url"]), for: .contextSources))
        #expect(store.contextPrivacy().disabledKinds == [.folder, .branch, .selection])
        #expect(store.set(.stringList(["com.example.app"]), for: .contextSelectionBlockedApps))
        #expect(store.contextPrivacy().blocksSelection("com.example.app"))
        #expect(!store.contextPrivacy().blocksSelection("com.1password.1password"))
    }
}
