import Foundation
import Observation

/// What happened when the settings file was read at startup.
public enum SettingsLoadOutcome: Sendable, Equatable {
    /// There was no file; defaults are in use and nothing is written until something changes.
    case created
    case loaded
    /// The file was not valid JSON. `backup` holds its bytes; defaults are in use.
    case recoveredFromCorruption(backup: URL)
    /// The file was written by a newer build. Known settings are used, unknown ones are kept, `backup` is a copy.
    case newerVersion(backup: URL)
    /// The file exists but could not be read (permissions, a transient error). Defaults are in use and nothing is
    /// saved over it, because the real settings may be fine.
    case unreadable
}

/// One saved earlier version of the file.
public struct SettingsVersion: Sendable, Equatable, Identifiable {
    public let url: URL
    public let date: Date
    public var id: URL { url }
}

public struct SettingsImportReport: Sendable, Equatable {
    /// Settings this build does not know. They are kept in the file but have no effect.
    public let unknown: [String]
    /// Settings whose value was illegal and fell back to the default.
    public let repaired: [SettingID]
}

public enum SettingsImportError: Error, Equatable {
    case unreadable
    case notASettingsFile
}

/// The one place settings live. Reads and writes a single readable JSON file, keeps the last few versions, and is
/// observable so SwiftUI views update when a value changes.
///
/// Read through `bool(_:)`, `string(_:)` and friends inside a view body and the view tracks exactly that setting.
@MainActor
@Observable
public final class SettingsStore {
    /// The folder inside Application Support that holds every file the app writes.
    public static let folderName = "Apropos"

    /// `~/Library/Application Support`.
    public static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }

    /// `~/Library/Application Support/Apropos/settings.json`.
    public static var defaultURL: URL {
        supportDirectory.appendingPathComponent("\(folderName)/settings.json")
    }

    public let url: URL
    public let historyLimit: Int
    public private(set) var loadOutcome: SettingsLoadOutcome = .created
    /// Set when a write failed, so the settings window can say so. Cleared by the next successful write.
    public private(set) var lastSaveError: String?

    private var overrides: [SettingID: SettingValue] = [:]

    @ObservationIgnored private var document = SettingsDocument()
    @ObservationIgnored private var lastWritten: Data?
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    @ObservationIgnored private let writeDelay: Duration
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var canSave = true

    /// - Parameters:
    ///   - writeDelay: Changes within this window become one write. Zero writes immediately.
    ///   - historyLimit: How many earlier versions of the file are kept.
    public init(
        url: URL = SettingsStore.defaultURL, historyLimit: Int = 10, writeDelay: Duration = .milliseconds(300),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.url = url
        self.historyLimit = max(historyLimit, 0)
        self.writeDelay = writeDelay
        self.now = now
        load()
    }

    // MARK: Reading

    public func value(_ id: SettingID) -> SettingValue {
        overrides[id] ?? SettingsRegistry.definition(for: id)?.defaultValue ?? .bool(false)
    }

    public func bool(_ id: SettingID) -> Bool {
        if case .bool(let flag) = value(id) { return flag }
        return false
    }

    /// Choices are strings: `store.string(.theme)` is `"system"`, `"dark"` or `"light"`.
    public func string(_ id: SettingID) -> String {
        if case .string(let text) = value(id) { return text }
        return ""
    }

    public func number(_ id: SettingID) -> Int {
        if case .number(let number) = value(id) { return number }
        return 0
    }

    public func hotkey(_ id: SettingID) -> HotKeyCombo {
        if case .hotkey(let combo) = value(id) { return combo }
        return .default
    }

    /// Lists and multi-choices.
    public func stringList(_ id: SettingID) -> [String] {
        if case .stringList(let list) = value(id) { return list }
        return []
    }

    public func isDefault(_ id: SettingID) -> Bool { overrides[id] == nil }

    // MARK: Writing

    /// Stores `value`. An illegal value (a choice that does not exist, a hotkey with no modifier) is ignored and
    /// `false` is returned. Numbers are clamped to their range.
    @discardableResult
    public func set(_ value: SettingValue, for id: SettingID) -> Bool {
        guard let definition = SettingsRegistry.definition(for: id), let valid = definition.normalized(value) else {
            return false
        }
        if valid == definition.defaultValue {
            overrides[id] = nil
        } else {
            overrides[id] = valid
        }
        scheduleWrite()
        return true
    }

    public func reset(_ id: SettingID) {
        guard overrides[id] != nil else { return }
        overrides[id] = nil
        scheduleWrite()
    }

    /// Back to every default. Unknown settings in the file are kept.
    public func resetAll() {
        guard !overrides.isEmpty else { return }
        overrides = [:]
        scheduleWrite()
    }

    /// Writes any pending change now. Call on quit.
    public func flush() {
        pendingWrite?.cancel()
        pendingWrite = nil
        writeNow()
    }

    // MARK: History

    /// Earlier versions of the file, newest first.
    public func history() -> [SettingsVersion] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: historyDirectory.path)) ?? []
        return names.filter { $0.hasPrefix("settings-") && $0.hasSuffix(".json") }
            .sorted(by: >)
            .compactMap { name in
                guard let date = Self.date(fromHistoryName: name) else { return nil }
                return SettingsVersion(url: historyDirectory.appendingPathComponent(name), date: date)
            }
    }

    /// Makes `version` the current settings. The file it replaces becomes a history entry itself, so a restore can be
    /// undone.
    @discardableResult
    public func restore(_ version: SettingsVersion) throws -> SettingsImportReport {
        try apply(data: Data(contentsOf: version.url))
    }

    // MARK: Export and import

    /// Writes the current settings to `destination`, for backup or moving to another Mac.
    public func exportSettings(to destination: URL) throws {
        flush()
        try document(withOverrides: overrides).encoded().write(to: destination, options: .atomic)
    }

    /// Replaces the current settings with the contents of an exported file.
    @discardableResult
    public func importSettings(from source: URL) throws -> SettingsImportReport {
        guard let data = try? Data(contentsOf: source) else { throw SettingsImportError.unreadable }
        return try apply(data: data)
    }

    // MARK: Internals

    private var historyDirectory: URL { url.deletingLastPathComponent().appendingPathComponent("history") }

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url) else {
            loadOutcome = .unreadable
            canSave = false
            return
        }
        guard let parsed = try? SettingsDocument.parse(data) else {
            let backup = backupURL(label: "broken-\(Self.stamp(now()))")
            copyIfMissing(to: backup)
            loadOutcome = .recoveredFromCorruption(backup: backup)
            return
        }
        document = parsed
        overrides = parsed.values
        lastWritten = data
        if parsed.version > SettingsDocument.currentVersion {
            let backup = backupURL(label: "v\(parsed.version)-backup")
            copyIfMissing(to: backup)
            loadOutcome = .newerVersion(backup: backup)
        } else {
            loadOutcome = .loaded
        }
    }

    private func apply(data: Data) throws -> SettingsImportReport {
        guard let parsed = try? SettingsDocument.parse(data) else { throw SettingsImportError.notASettingsFile }
        document.unknownSettings = parsed.unknownSettings
        overrides = parsed.values
        canSave = true
        flush()
        return SettingsImportReport(unknown: parsed.unknownSettings.keys.sorted(), repaired: parsed.repaired)
    }

    private func document(withOverrides values: [SettingID: SettingValue]) -> SettingsDocument {
        var copy = document
        copy.values = values
        // A file from a newer build keeps its version number so that build still recognizes it.
        copy.version = max(document.version, SettingsDocument.currentVersion)
        return copy
    }

    private func scheduleWrite() {
        pendingWrite?.cancel()
        if writeDelay == .zero {
            pendingWrite = nil
            writeNow()
            return
        }
        let delay = writeDelay
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pendingWrite = nil
            self?.writeNow()
        }
    }

    private func writeNow() {
        guard canSave else { return }
        do {
            let data = try document(withOverrides: overrides).encoded()
            guard data != lastWritten else { return }
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            archiveCurrentFile()
            try data.write(to: url, options: .atomic)
            lastWritten = data
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
            AproposLog.app.error("settings save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Copies the file about to be replaced into `history/` and drops the oldest entries beyond the limit.
    private func archiveCurrentFile() {
        guard historyLimit > 0, FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        var name = "settings-\(Self.stamp(now())).json"
        var counter = 1
        while FileManager.default.fileExists(atPath: historyDirectory.appendingPathComponent(name).path) {
            counter += 1
            name = "settings-\(Self.stamp(now()))-\(counter).json"
        }
        try? FileManager.default.copyItem(at: url, to: historyDirectory.appendingPathComponent(name))
        for stale in history().dropFirst(historyLimit) {
            try? FileManager.default.removeItem(at: stale.url)
        }
    }

    private func backupURL(label: String) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).\(label)")
    }

    /// Never overwrites an existing backup: the first copy is the original.
    private func copyIfMissing(to destination: URL) {
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        try? FileManager.default.copyItem(at: url, to: destination)
    }

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }

    private static func stamp(_ date: Date) -> String { formatter().string(from: date) }

    private static func date(fromHistoryName name: String) -> Date? {
        let stamp = name.dropFirst("settings-".count).prefix("yyyyMMdd-HHmmss-SSS".count)
        return formatter().date(from: String(stamp))
    }
}
