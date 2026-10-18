import Foundation
import Observation

/// What Apropos has learned about one command. Only the identity and times are stored, never what was typed or selected.
struct UsageRecord: Codable, Equatable {
    var runs: Int
    /// The last few run times, oldest first, at most `Frecency.sampleLimit`.
    var recent: [Date]
}

/// What the user decided about one command. Survives "Reset learned ranking".
struct CommandPreference: Codable, Equatable {
    /// When the command was pinned; pins sort by this, oldest first. Nil means not pinned.
    var pinnedAt: Date?
    var isHidden = false
    var aliases: [String] = []
    /// An SF Symbol the user picked for this command's row.
    var symbol: String?

    var isEmpty: Bool { pinnedAt == nil && !isHidden && aliases.isEmpty && symbol == nil }
}

struct UsageFile: Codable {
    var schemaVersion = 1
    /// Learned from use. Cleared by `resetLearnedRanking()`.
    var usage: [CommandID: UsageRecord] = [:]
    /// Chosen by the user. Never cleared by a ranking reset.
    var preferences: [CommandID: CommandPreference] = [:]

    init() {}

    // Dictionaries keyed by a non-String Codable type encode as arrays; keep the file an object keyed by raw value.
    private enum CodingKeys: String, CodingKey { case schemaVersion, usage, preferences }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let usage = try container.decodeIfPresent([String: UsageRecord].self, forKey: .usage) ?? [:]
        self.usage = Dictionary(uniqueKeysWithValues: usage.map { (CommandID(rawValue: $0.key), $0.value) })
        let prefs = try container.decodeIfPresent([String: CommandPreference].self, forKey: .preferences) ?? [:]
        preferences = Dictionary(uniqueKeysWithValues: prefs.map { (CommandID(rawValue: $0.key), $0.value) })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(Dictionary(uniqueKeysWithValues: usage.map { ($0.key.rawValue, $0.value) }), forKey: .usage)
        try container.encode(
            Dictionary(uniqueKeysWithValues: preferences.map { ($0.key.rawValue, $0.value) }), forKey: .preferences)
    }
}

/// Local store of what the user runs, pins, hides and renames.
///
/// JSON rather than SQLite: the data is small (one record per command ever run, ten timestamps each, pruned after a
/// year idle), it is read once at launch and written in the background, a person can open it and see exactly what Apropos
/// learned, and it needs no schema migrations or library. The same atomic-write approach as the settings file.
///
/// Privacy: a record is a command identity (bundle id plus menu path and title) and times. Query text and selection
/// contents never reach this type. Items under "Open Recent" menus are not recorded at all, because their titles are
/// document names.
@MainActor
@Observable
public final class UsageStore {
    /// `~/Library/Application Support/Apropos/usage.json`.
    public static var defaultURL: URL {
        SettingsStore.defaultURL.deletingLastPathComponent().appendingPathComponent("usage.json")
    }

    /// Records not run for this long (and with no pin, hide or alias) are dropped at launch.
    public static let retention: TimeInterval = 365 * 86_400

    public let url: URL
    public private(set) var lastSaveError: String?
    /// True when the file existed but was not valid; it was copied aside and the store started empty.
    public private(set) var recoveredFromCorruption = false

    private var file = UsageFile()
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    @ObservationIgnored private let writeDelay: Duration
    @ObservationIgnored private var canSave = true
    @ObservationIgnored private var lastWritten: Data?

    public init(url: URL = UsageStore.defaultURL, writeDelay: Duration = .seconds(2), now: Date = Date()) {
        self.url = url
        self.writeDelay = writeDelay
        load(now: now)
    }

    // MARK: Recording

    /// Whether a run of this command may be remembered.
    public static func isRecordable(_ command: Command) -> Bool {
        !command.path.contains { CommandID.normalize($0).contains("recent") }
    }

    /// Counts one run. Use the alternate's own `stableID` when an Option-key variant was run.
    public func recordRun(of command: Command, alternate: CommandAlternate? = nil, at date: Date = Date()) {
        guard Self.isRecordable(command) else { return }
        recordRun(id: alternate?.stableID ?? command.stableID, at: date)
    }

    public func recordRun(id: CommandID, at date: Date = Date()) {
        var record = file.usage[id] ?? UsageRecord(runs: 0, recent: [])
        record.runs += 1
        record.recent.append(date)
        if record.recent.count > Frecency.sampleLimit { record.recent.removeFirst(record.recent.count - Frecency.sampleLimit) }
        file.usage[id] = record
        scheduleWrite()
    }

    // MARK: Reading usage

    public func runCount(_ id: CommandID) -> Int { file.usage[id]?.runs ?? 0 }

    public func lastRun(_ id: CommandID) -> Date? { file.usage[id]?.recent.last }

    public func frecency(_ id: CommandID, now: Date = Date()) -> Double {
        guard let record = file.usage[id] else { return 0 }
        return Frecency.score(runs: record.runs, recent: record.recent, now: now)
    }

    /// Forgets everything learned from use. Pins, hidden commands and aliases are kept.
    public func resetLearnedRanking() {
        guard !file.usage.isEmpty else { return }
        file.usage = [:]
        scheduleWrite()
    }

    /// Forgets the learned ranking of one app only.
    public func resetLearnedRanking(forBundleID bundleID: String) {
        let before = file.usage.count
        file.usage = file.usage.filter { $0.key.bundleID != bundleID }
        if file.usage.count != before { scheduleWrite() }
    }

    // MARK: Pins, hides, aliases

    public func isPinned(_ id: CommandID) -> Bool { file.preferences[id]?.pinnedAt != nil }

    public func isHidden(_ id: CommandID) -> Bool { file.preferences[id]?.isHidden ?? false }

    public func aliases(_ id: CommandID) -> [String] { file.preferences[id]?.aliases ?? [] }

    public func setPinned(_ pinned: Bool, for id: CommandID, at date: Date = Date()) {
        update(id) { preference in
            if pinned {
                if preference.pinnedAt == nil { preference.pinnedAt = date }
            } else {
                preference.pinnedAt = nil
            }
        }
    }

    public func setHidden(_ hidden: Bool, for id: CommandID) {
        update(id) { $0.isHidden = hidden }
    }

    /// Replaces the aliases of a command. They are lowercased and trimmed; empty and duplicate ones are dropped.
    public func setAliases(_ aliases: [String], for id: CommandID) {
        var seen = Set<String>()
        let cleaned = aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0.count <= 32 && seen.insert($0).inserted }
        update(id) { $0.aliases = cleaned }
    }

    public func symbolOverride(_ id: CommandID) -> String? { file.preferences[id]?.symbol }

    /// Pins a symbol to a command's row, or clears the choice with nil. Names with whitespace are ignored.
    public func setSymbolOverride(_ symbol: String?, for id: CommandID) {
        let cleaned = symbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned?.contains(where: \.isWhitespace) != true else { return }
        update(id) { $0.symbol = (cleaned?.isEmpty ?? true) ? nil : cleaned }
    }

    /// A resolver that honours the user's symbol choices. Take a new one after `setSymbolOverride`.
    public func symbolResolver(library: SymbolPackLibrary = .bundled()) -> SymbolResolver {
        var overrides: [CommandID: String] = [:]
        for (id, preference) in file.preferences { if let symbol = preference.symbol { overrides[id] = symbol } }
        return SymbolResolver(overrides: overrides, library: library)
    }

    /// Pinned commands of one app, in the order they were pinned.
    public func pinnedIDs(forBundleID bundleID: String) -> [CommandID] {
        file.preferences.filter { $0.key.bundleID == bundleID && $0.value.pinnedAt != nil }
            .sorted { ($0.value.pinnedAt ?? .distantFuture, $0.key) < ($1.value.pinnedAt ?? .distantFuture, $1.key) }
            .map(\.key)
    }

    /// Every hidden command of one app, for a "Hidden commands" list that lets the user bring them back.
    public func hiddenIDs(forBundleID bundleID: String) -> [CommandID] {
        file.preferences.filter { $0.key.bundleID == bundleID && $0.value.isHidden }.map(\.key).sorted()
    }

    private func update(_ id: CommandID, _ change: (inout CommandPreference) -> Void) {
        var preference = file.preferences[id] ?? CommandPreference()
        let before = preference
        change(&preference)
        guard preference != before else { return }
        file.preferences[id] = preference.isEmpty ? nil : preference
        scheduleWrite()
    }

    // MARK: Ranking

    /// A frozen copy of what ranking needs, safe to hand to `CommandRanker` on any thread. Take a new one after
    /// recording a run or changing a pin.
    public func rankingSignal(now: Date = Date()) -> UsageSignal {
        var scores: [CommandID: Double] = [:]
        for (id, record) in file.usage { scores[id] = Frecency.score(runs: record.runs, recent: record.recent, now: now) }
        var pins: [CommandID: Date] = [:]
        var hidden: Set<CommandID> = []
        var aliases: [CommandID: [String]] = [:]
        for (id, preference) in file.preferences {
            if let pinnedAt = preference.pinnedAt { pins[id] = pinnedAt }
            if preference.isHidden { hidden.insert(id) }
            if !preference.aliases.isEmpty { aliases[id] = preference.aliases }
        }
        return UsageSignal(scores: scores, pins: pins, hidden: hidden, aliases: aliases)
    }

    /// The learned usage as per-app shares, the cold-start fallback of next-action prediction.
    public func frecencyPrior(now: Date = Date()) -> FrecencyPrior {
        var scores: [CommandID: Double] = [:]
        for (id, record) in file.usage { scores[id] = Frecency.score(runs: record.runs, recent: record.recent, now: now) }
        return FrecencyPrior(scores: scores)
    }

    // MARK: Persistence

    /// Writes any pending change now. Call on quit.
    public func flush() {
        pendingWrite?.cancel()
        pendingWrite = nil
        writeNow()
    }

    private func load(now: Date) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url) else {
            canSave = false
            return
        }
        guard var decoded = try? Self.decoder.decode(UsageFile.self, from: data) else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).broken-\(formatter.string(from: now))")
            if !FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.copyItem(at: url, to: backup) }
            recoveredFromCorruption = true
            return
        }
        decoded.usage = decoded.usage.filter { now.timeIntervalSince($0.value.recent.last ?? .distantPast) < Self.retention }
        file = decoded
        lastWritten = data
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

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func writeNow() {
        guard canSave else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(file)
            guard data != lastWritten else { return }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            lastWritten = data
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
            AproposLog.app.error("usage save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// An immutable copy of the usage state for ranking.
public struct UsageSignal: RankingSignal {
    let scores: [CommandID: Double]
    let pins: [CommandID: Date]
    let hidden: Set<CommandID>
    let aliases: [CommandID: [String]]

    public func boost(for command: Command) -> Int { Frecency.boost(forScore: scores[command.stableID] ?? 0) }
    public func isHidden(_ command: Command) -> Bool { hidden.contains(command.stableID) }
    public func pinOrder(for command: Command) -> Date? { pins[command.stableID] }
    public func aliases(for command: Command) -> [String] { aliases[command.stableID] ?? [] }
    public func frecency(for command: Command) -> Double { scores[command.stableID] ?? 0 }
}
