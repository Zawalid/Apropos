import Foundation
import Testing

@testable import Apropos

struct LegacyMigrationTests {
    private let fm = FileManager.default

    private struct Sandbox {
        let support: URL
        let defaults: UserDefaults
        let domain: String
        let legacy: UserDefaults
        let legacyDomain: String
    }

    private func sandbox() throws -> Sandbox {
        let support = fm.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        let tag = UUID().uuidString
        let domain = "test.new.\(tag)"
        let legacyDomain = "test.old.\(tag)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let legacy = try #require(UserDefaults(suiteName: legacyDomain))
        return Sandbox(support: support, defaults: defaults, domain: domain, legacy: legacy, legacyDomain: legacyDomain)
    }

    private func migration(_ box: Sandbox) -> LegacyMigration {
        LegacyMigration(
            supportDirectory: box.support, folderName: "Apropos", defaults: box.defaults, domain: box.domain,
            legacyDefaults: box.legacy, legacyDomain: box.legacyDomain)
    }

    private func write(_ text: String, to path: String, in box: Sandbox) throws {
        let url = box.support.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ path: String, in box: Sandbox) -> String? {
        try? String(contentsOf: box.support.appendingPathComponent(path), encoding: .utf8)
    }

    private func exists(_ path: String, in box: Sandbox) -> Bool {
        fm.fileExists(atPath: box.support.appendingPathComponent(path).path)
    }

    @Test func freshInstallDoesNothingAndCreatesNoFolder() throws {
        let box = try sandbox()
        #expect(migration(box).run() == .nothingToMigrate)
        #expect(!exists("Apropos", in: box))
    }

    @Test func oldDataIsCopiedWithMarkerAndOldFolderStays() throws {
        let box = try sandbox()
        try write("{\"version\":1}", to: "Cue/settings.json", in: box)
        try write("{\"runs\":[]}", to: "Cue/usage.json", in: box)
        try write("{\"name\":\"x\"}", to: "Cue/packs/mine.json", in: box)
        box.legacy.set(true, forKey: "hasSeenWelcome")
        box.legacy.set("abc", forKey: "hotKey")

        let outcome = migration(box).run()

        guard case .migrated(let files, let keys, let skipped) = outcome else {
            Issue.record("expected migrated, got \(outcome)")
            return
        }
        #expect(files == 3)
        #expect(keys == 2)
        #expect(skipped.isEmpty)
        #expect(read("Apropos/settings.json", in: box) == "{\"version\":1}")
        #expect(read("Apropos/packs/mine.json", in: box) == "{\"name\":\"x\"}")
        #expect(exists("Apropos/migrated-from-cue", in: box))
        #expect(read("Cue/settings.json", in: box) == "{\"version\":1}")
        #expect(box.defaults.bool(forKey: "hasSeenWelcome"))
        #expect(box.defaults.string(forKey: "hotKey") == "abc")
        #expect(!fm.fileExists(atPath: box.support.path + "/Apropos.migrating"))
    }

    @Test func existingNewFolderIsNeverOverwritten() throws {
        let box = try sandbox()
        try write("{\"old\":true}", to: "Cue/settings.json", in: box)
        try write("{\"new\":true}", to: "Apropos/settings.json", in: box)
        box.legacy.set(true, forKey: "hasSeenWelcome")

        #expect(migration(box).run() == .keptExistingFolder(defaultsKeys: 1))
        #expect(read("Apropos/settings.json", in: box) == "{\"new\":true}")
        #expect(!exists("Apropos/migrated-from-cue", in: box))
        #expect(read("Cue/settings.json", in: box) == "{\"old\":true}")
    }

    @Test func defaultsAlreadySetInTheNewDomainWin() throws {
        let box = try sandbox()
        box.legacy.set("old", forKey: "hotKey")
        box.legacy.set(true, forKey: "hasSeenWelcome")
        box.defaults.set("new", forKey: "hotKey")

        _ = migration(box).run()

        #expect(box.defaults.string(forKey: "hotKey") == "new")
        #expect(box.defaults.bool(forKey: "hasSeenWelcome"))
    }

    @Test func partialDataMigratesWhatExists() throws {
        let box = try sandbox()
        try write("{\"version\":1}", to: "Cue/settings.json", in: box)

        let outcome = migration(box).run()

        #expect(outcome == .migrated(files: 1, defaultsKeys: 0, skipped: []))
        #expect(exists("Apropos/settings.json", in: box))
        #expect(!exists("Apropos/usage.json", in: box))
    }

    @Test func corruptOldFileIsSkippedAndReportedWhileTheRestIsKept() throws {
        let box = try sandbox()
        try write("{\"version\":1}", to: "Cue/settings.json", in: box)
        try write("{not json", to: "Cue/usage.json", in: box)

        let outcome = migration(box).run()

        #expect(outcome == .migrated(files: 1, defaultsKeys: 0, skipped: ["usage.json"]))
        #expect(exists("Apropos/settings.json", in: box))
        #expect(!exists("Apropos/usage.json", in: box))
        #expect(read("Cue/usage.json", in: box) == "{not json")
    }

    @Test func markerPreventsASecondRun() throws {
        let box = try sandbox()
        try write("{\"version\":1}", to: "Cue/settings.json", in: box)
        #expect(migration(box).run() != .alreadyDone)

        try write("{\"version\":2}", to: "Cue/settings.json", in: box)
        box.legacy.set("late", forKey: "lateKey")
        #expect(migration(box).run() == .alreadyDone)
        #expect(read("Apropos/settings.json", in: box) == "{\"version\":1}")
        #expect(box.defaults.string(forKey: "lateKey") == nil)
    }

    @Test func doneFlagAloneAlsoPreventsARerun() throws {
        let box = try sandbox()
        box.legacy.set("x", forKey: "k")
        #expect(migration(box).run() == .migrated(files: 0, defaultsKeys: 1, skipped: []))
        #expect(migration(box).run() == .alreadyDone)
    }

    @Test func failedCopyLeavesOldDataIntactAndRetriesNextLaunch() throws {
        let box = try sandbox()
        try write("{\"version\":1}", to: "Cue/settings.json", in: box)
        try write("data", to: "Cue/locked.bin", in: box)
        let locked = box.support.appendingPathComponent("Cue/locked.bin").path
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked) }

        guard case .failed = migration(box).run() else {
            Issue.record("expected a failure")
            return
        }
        #expect(!exists("Apropos", in: box))
        let leftovers = try fm.contentsOfDirectory(atPath: box.support.path).filter { $0.contains("migrating") }
        #expect(leftovers.isEmpty)
        #expect(read("Cue/settings.json", in: box) == "{\"version\":1}")
        #expect(!box.defaults.bool(forKey: LegacyMigration.doneKey))

        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked)
        guard case .migrated = migration(box).run() else {
            Issue.record("expected the retry to migrate")
            return
        }
        #expect(exists("Apropos/settings.json", in: box))
    }
}
