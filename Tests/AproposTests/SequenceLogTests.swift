import Foundation
import Testing

@testable import Apropos

@MainActor
struct SequenceLogTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("apropos-seq-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("sequence.json")
    }

    private func log(_ url: URL, at date: Date? = nil) -> SequenceLog {
        SequenceLog(url: url, writeDelay: .zero, now: date ?? now)
    }

    private func id(_ name: String, bundle: String = "app.test", menu: String = "Product") -> CommandID {
        CommandID.base(bundleID: bundle, path: [menu], title: name)
    }

    @Test func recordsAndReloadsWithPreviousCommandInsideTheWindow() {
        let url = tempURL()
        let first = log(url)
        first.recordRun(id("Run Tests"), app: "com.apple.dt.Xcode", contextKinds: [.branch, .document], at: now)
        first.recordRun(id("Commit"), app: "com.apple.Terminal", at: now + 60)
        first.recordRun(id("Archive"), app: "com.apple.dt.Xcode", at: now + 60 + SequenceLog.sessionWindow + 1)
        let reloaded = log(url, at: now + 3_000)
        #expect(reloaded.events.count == 3)
        #expect(reloaded.events[0].previous == nil)
        #expect(reloaded.events[1].previous == id("Run Tests"))
        #expect(reloaded.events[2].previous == nil)
        #expect(reloaded.events[0].contextKinds == ["branch", "document"])
        #expect(reloaded.events[1].app == "com.apple.Terminal")
    }

    @Test func recentCommandsFormAChainOfTwoWithinTheWindow() {
        let store = log(tempURL())
        store.recordRun(id("A"), app: nil, at: now)
        store.recordRun(id("B"), app: nil, at: now + 100)
        store.recordRun(id("C"), app: nil, at: now + 200)
        #expect(store.recentCommands(at: now + 250) == [id("C"), id("B")])
        #expect(store.recentCommands(at: now + 200 + SequenceLog.sessionWindow + 5).isEmpty)
    }

    @Test func dismissalsAreLoggedButNeverBecomeThePreviousCommand() {
        let store = log(tempURL())
        store.recordRun(id("A"), app: "app.test", at: now)
        store.recordDismissal(of: id("B"), app: "app.test", at: now + 10)
        store.recordRun(id("C"), app: "app.test", at: now + 20)
        #expect(store.events.map(\.kind) == [.run, .dismiss, .run])
        #expect(store.events[2].previous == id("A"))
    }

    @Test func fileIsVersionedCompactAndOwnerOnly() throws {
        let url = tempURL()
        let store = log(url)
        store.recordRun(id("Run"), app: "app.test", at: now)
        let data = try Data(contentsOf: url)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["schemaVersion"] as? Int == 1)
        #expect((root["events"] as? [Any])?.count == 1)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    // MARK: Privacy

    @Test func onlyTheDocumentedKeysCanAppearInTheFile() throws {
        let url = tempURL()
        let store = log(url)
        store.recordRun(
            id("Run"), app: "app.test", contextKinds: ContextKind.allCases, offered: id("Other"), at: now)
        store.recordRun(id("Next"), app: "app.test", at: now + 5)
        store.recordDismissal(of: id("Next"), app: "app.test", at: now + 9)
        let root = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let events = try #require(root["events"] as? [[String: Any]])
        let allowed = Set(RunEvent.CodingKeys.allCases.map(\.rawValue))
        for event in events { #expect(Set(event.keys).isSubset(of: allowed)) }
        #expect(Set(root.keys) == ["schemaVersion", "events"])
    }

    @Test func runEventHasNoFieldForContent() throws {
        let event = try #require(RunEvent(at: now, command: id("X"), app: nil))
        let names = Set(Mirror(reflecting: event).children.compactMap(\.label))
        #expect(names == ["kind", "time", "command", "app", "previous", "contextKinds", "offered"])
    }

    @Test func contextKindsKeepOnlyKnownKindNames() {
        let event = RunEvent(
            kind: .run, time: 1_800_000_000, command: id("X"), app: "app.test", previous: nil,
            kindNames: ["selection", "https://example.com/secret", "document", "selection", "My Report.docx"],
            offered: nil)
        #expect(event?.contextKinds == ["document", "selection"])
    }

    @Test func appMustBeABundleIdentifier() {
        for bad in [
            "My Document.pdf", "/Users/me/file", "title with space", "", String(repeating: "a", count: 200), "café.app",
        ] {
            #expect(RunEvent(at: now, command: id("X"), app: bad)?.app == PredictionPrivacy.unknownApp)
        }
        #expect(RunEvent(at: now, command: id("X"), app: "com.apple.dt.Xcode")?.app == "com.apple.dt.Xcode")
    }

    @Test func commandsUnderContentMenusAreNotLogged() {
        let store = log(tempURL())
        for menu in ["Window", "History", "Bookmarks", "Open Recent", "Fenêtre", "Historique", "Recent Folders"] {
            let command = Command(
                id: "x", title: "Quarterly report.docx", path: [menu], source: .menuItem(bundleID: "app.test"))
            #expect(!SequenceLog.isRecordable(command))
            #expect(store.recordRun(command.stableID, app: "app.test", at: now) == nil)
        }
        let nested = Command(
            id: "y", title: "Page about my bank", path: ["File", "Open Recent"], source: .menuItem(bundleID: "app.test")
        )
        #expect(!SequenceLog.isRecordable(nested))
        let fine = Command(id: "z", title: "Save", path: ["File"], source: .menuItem(bundleID: "app.test"))
        #expect(SequenceLog.isRecordable(fine))
        #expect(store.events.isEmpty)
    }

    @Test func overlongOrMultilineIdentitiesAreRejected() {
        #expect(!PredictionPrivacy.isLoggable(CommandID(rawValue: "app|" + String(repeating: "x", count: 300))))
        #expect(!PredictionPrivacy.isLoggable(CommandID(rawValue: "app|file>one\ntwo")))
        #expect(PredictionPrivacy.isLoggable(CommandID(rawValue: "ctx:text.upper")))
    }

    @Test func aTamperedFileCannotSmuggleContentInThroughKnownKeys() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
            {"schemaVersion":1,"events":[
            {"t":1799999000,"c":"app.test|window>secret.docx","a":"app.test"},
            {"t":1799999100,"c":"app.test|file>save","a":"Some Window Title","x":["url","/Users/me/notes.txt"]}
            ]}
            """
        try Data(json.utf8).write(to: url)
        let store = log(url)
        #expect(store.events.count == 1)
        #expect(store.events[0].app == PredictionPrivacy.unknownApp)
        #expect(store.events[0].contextKinds == ["url"])
    }

    // MARK: Rotation and recovery

    @Test func eventsOlderThanTheAgeLimitAreDroppedAtLaunch() {
        let url = tempURL()
        let store = log(url)
        store.recordRun(id("Old"), app: nil, at: now - SequenceLog.maxAge - day)
        store.recordRun(id("Edge"), app: nil, at: now - SequenceLog.maxAge + day)
        store.recordRun(id("New"), app: nil, at: now - day)
        let reloaded = log(url)
        #expect(reloaded.events.map(\.command) == [id("Edge"), id("New")])
    }

    @Test func eventsBeyondTheCountLimitAreRotatedOldestFirst() {
        let store = SequenceLog(url: tempURL(), writeDelay: .seconds(3600), now: now)
        let total = SequenceLog.maxEvents + SequenceLog.rotationSlack + 5
        for index in 0..<total { store.recordRun(id("C\(index % 7)"), app: nil, at: now - Double(total - index)) }
        #expect(store.events.count <= SequenceLog.maxEvents + SequenceLog.rotationSlack)
        #expect(store.events.count >= SequenceLog.maxEvents)
        #expect(store.events.last?.time == (now - 1).timeIntervalSince1970)
        let times = store.events.map(\.time)
        #expect(times == times.sorted())
    }

    @Test func corruptFileIsCopiedAsideAndTheLogStartsEmpty() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"schemaVersion\":1,\"events\":[{\"t\":17".utf8).write(to: url)
        let store = log(url)
        #expect(store.events.isEmpty)
        #expect(store.recoveredFromCorruption)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(siblings.contains { $0.hasPrefix("sequence.json.broken-") })
        store.recordRun(id("After"), app: nil, at: now)
        #expect(log(url).events.count == 1)
    }

    @Test func oneBadLineIsSkippedAndTheRestKept() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
            {"schemaVersion":1,"events":[
            {"t":1799999000,"c":"app.test|file>save"},
            {"t":"yesterday","c":5},
            {"t":1799999100,"c":"app.test|file>close","p":"app.test|file>save"}]}
            """
        try Data(json.utf8).write(to: url)
        let store = log(url)
        #expect(store.events.count == 2)
        #expect(!store.recoveredFromCorruption)
    }

    @Test func fileFromANewerVersionIsNeverOverwritten() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("{\"schemaVersion\":99,\"events\":[]}".utf8)
        try original.write(to: url)
        let store = log(url)
        store.recordRun(id("A"), app: nil, at: now)
        store.flush()
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func clearRemovesEverythingOnDisk() {
        let url = tempURL()
        let store = log(url)
        store.recordRun(id("A"), app: nil, at: now)
        store.clear()
        #expect(store.events.isEmpty)
        #expect(log(url).events.isEmpty)
    }

    @Test func fileSitsNextToTheUsageFileButIsSeparate() {
        let usage = URL(fileURLWithPath: "/tmp/x/Apropos/usage.json")
        #expect(SequenceLog.url(besides: usage).lastPathComponent == "sequence.json")
        #expect(SequenceLog.url(besides: usage).deletingLastPathComponent() == usage.deletingLastPathComponent())
    }
}
