import Foundation
import Testing

@testable import Cue

@MainActor
struct SettingsTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-settings-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private func store(_ url: URL, limit: Int = 3) -> SettingsStore {
        SettingsStore(url: url, historyLimit: limit, writeDelay: .zero)
    }

    @Test func registryIdsAreUniqueAndDefaultsAreLegal() {
        let ids = SettingsRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for definition in SettingsRegistry.all {
            #expect(definition.normalized(definition.defaultValue) == definition.defaultValue, "\(definition.id)")
        }
        for page in SettingPage.allCases where page != .about {
            #expect(!SettingsRegistry.definitions(on: page).isEmpty, "\(page)")
        }
    }

    @Test func defaultsMatchTheSpec() {
        let store = store(tempURL())
        #expect(store.hotkey(.openHotKey) == .default)
        #expect(store.string(.theme) == "system")
        #expect(store.bool(.checkForUpdates) == false)
        #expect(store.bool(.contextSensing))
        #expect(store.stringList(.contextIgnoreList).contains("com.1password.1password"))
        #expect(store.loadOutcome == .created)
    }

    @Test func setPersistsAndReloads() {
        let url = tempURL()
        let first = store(url)
        #expect(first.set(.string("dark"), for: .theme))
        #expect(first.set(.number(5), for: .resetQueryAfterSeconds))
        let second = store(url)
        #expect(second.string(.theme) == "dark")
        #expect(second.number(.resetQueryAfterSeconds) == 5)
        #expect(second.loadOutcome == .loaded)
    }

    @Test func onlyNonDefaultsAreWritten() throws {
        let url = tempURL()
        let store = store(url)
        store.set(.string("dark"), for: .theme)
        store.set(.string("system"), for: .theme)
        store.set(.bool(true), for: .openAtLogin)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("openAtLogin"))
        #expect(!text.contains("theme"))
        #expect(text.contains("\"schemaVersion\" : 1"))
    }

    @Test func illegalValuesAreRejectedOrClamped() {
        let store = store(tempURL())
        #expect(!store.set(.string("neon"), for: .theme))
        #expect(!store.set(.bool(true), for: .theme))
        #expect(!store.set(.hotkey(HotKeyCombo(keyCode: 49, modifiers: [])), for: .openHotKey))
        store.set(.number(99_999), for: .resetQueryAfterSeconds)
        #expect(store.number(.resetQueryAfterSeconds) == 3600)
        store.set(.stringList(["selection", "bogus", "url"]), for: .contextChips)
        #expect(store.stringList(.contextChips) == ["url", "selection"])
        store.set(.stringList([" a ", "a", "", "b"]), for: .contextDisabledApps)
        #expect(store.stringList(.contextDisabledApps) == ["a", "b"])
    }

    @Test func hotkeyRoundTripsThroughTheFile() {
        let url = tempURL()
        let combo = HotKeyCombo(keyCode: 40, modifiers: [.command, .shift])
        store(url).set(.hotkey(combo), for: .openHotKey)
        #expect(store(url).hotkey(.openHotKey) == combo)
    }

    @Test func hotkeyIsReadableInTheFile() throws {
        let url = tempURL()
        store(url).set(.hotkey(HotKeyCombo(keyCode: 40, modifiers: [.command, .shift])), for: .openHotKey)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"command\""))
        #expect(text.contains("\"shift\""))
    }

    @Test func corruptFileIsBackedUpAndDefaultsUsed() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        let store = store(url)
        guard case .recoveredFromCorruption(let backup) = store.loadOutcome else {
            Issue.record("expected recovery, got \(store.loadOutcome)")
            return
        }
        #expect(try String(contentsOf: backup, encoding: .utf8) == "{ not json")
        #expect(store.string(.theme) == "system")
    }

    @Test func illegalStoredValueFallsBackToDefault() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":1,"settings":{"theme":"neon","openAtLogin":true}}"#.utf8).write(to: url)
        let store = store(url)
        #expect(store.string(.theme) == "system")
        #expect(store.bool(.openAtLogin))
    }

    @Test func newerFileKeepsUnknownKeysOnSave() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":7,"future":{"a":1},"settings":{"mystery":[1,2],"theme":"dark"}}"#.utf8).write(to: url)
        let store = store(url)
        guard case .newerVersion(let backup) = store.loadOutcome else {
            Issue.record("expected newerVersion")
            return
        }
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(store.string(.theme) == "dark")
        store.set(.bool(true), for: .openAtLogin)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("mystery"))
        #expect(text.contains("future"))
        #expect(text.contains("\"schemaVersion\" : 7"))
    }

    @Test func historyKeepsTheLastNVersions() {
        let url = tempURL()
        let store = store(url, limit: 3)
        for seconds in 1...8 { store.set(.number(seconds), for: .resetQueryAfterSeconds) }
        #expect(store.history().count == 3)
        #expect(store.history().first?.date ?? .distantPast >= store.history().last?.date ?? .distantFuture)
    }

    @Test func restoreBringsBackAnOlderVersionAndIsUndoable() throws {
        let url = tempURL()
        let store = store(url, limit: 5)
        store.set(.string("dark"), for: .theme)
        store.set(.string("light"), for: .theme)
        let older = try #require(store.history().last)
        try store.restore(older)
        #expect(store.string(.theme) == "dark")
        store.set(.bool(true), for: .openAtLogin)
        #expect(store.history().count >= 3)
    }

    @Test func exportAndImportRoundTrip() throws {
        let source = store(tempURL())
        source.set(.string("light"), for: .theme)
        source.set(.stringList(["com.example.bank"]), for: .contextDisabledApps)
        let exported = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).json")
        try source.exportSettings(to: exported)

        let target = store(tempURL())
        target.set(.bool(true), for: .openAtLogin)
        let report = try target.importSettings(from: exported)
        #expect(report.unknown.isEmpty)
        #expect(target.string(.theme) == "light")
        #expect(target.stringList(.contextDisabledApps) == ["com.example.bank"])
        #expect(!target.bool(.openAtLogin))
    }

    @Test func importRejectsGarbage() throws {
        let garbage = FileManager.default.temporaryDirectory.appendingPathComponent("garbage-\(UUID().uuidString).json")
        try Data("[1,2,3]".utf8).write(to: garbage)
        let store = store(tempURL())
        #expect(throws: SettingsImportError.notASettingsFile) { try store.importSettings(from: garbage) }
    }

    @Test func debouncedWritesCoalesceAndFlushWrites() {
        let url = tempURL()
        let store = SettingsStore(url: url, historyLimit: 5, writeDelay: .seconds(60))
        store.set(.string("dark"), for: .theme)
        store.set(.string("light"), for: .theme)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        store.flush()
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(store.history().isEmpty)
    }

    @Test func searchMatchesTitleAndKeywords() {
        #expect(SettingsRegistry.search("dark mode").map(\.id).contains(.theme))
        #expect(SettingsRegistry.search("PASSWORD").map(\.id).contains(.contextIgnoreList))
        #expect(SettingsRegistry.search("").isEmpty)
    }

    @Test func bridgesMapToContextTypes() {
        let store = store(tempURL())
        store.set(.stringList(["com.example.app"]), for: .contextDisabledApps)
        let privacy = store.contextPrivacy()
        #expect(privacy.isDisabled("com.example.app"))
        #expect(privacy.isDisabled("com.bitwarden.desktop"))
        store.set(.stringList(["url", "document"]), for: .contextChips)
        #expect(store.visibleContextKinds() == [.document, .url])
    }
}
