import Foundation

/// The file format of the run log: a version and the events, oldest first.
struct SequenceFile: Codable {
    static let currentVersion = 1
    var schemaVersion = SequenceFile.currentVersion
    var events: [RunEvent] = []

    init(events: [RunEvent] = []) { self.events = events }

    private enum CodingKeys: String, CodingKey { case schemaVersion, events }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        // One bad line must not cost the whole history: lines that do not decode (or are not allowed) are skipped.
        events = try container.decodeIfPresent([Lossy<RunEvent>].self, forKey: .events)?.compactMap(\.value) ?? []
    }
}

/// Decodes to nil instead of throwing, so an array of these survives bad elements.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

/// A compact local log of the commands that ran, kept in its own file so the prediction model can learn the order in
/// which a person works. What is stored is exactly `RunEvent`, described in docs/prediction.md.
///
/// The log is rotated by age and by count, written atomically with owner-only permissions, never exported, and
/// cleared by "Reset learned ranking". A damaged file is copied aside and the log starts empty; a file written by a
/// newer version is left alone and read-only.
@MainActor
public final class SequenceLog {
    /// `~/Library/Application Support/Apropos/sequence.json` next to the usage file.
    public nonisolated static func url(besides usageURL: URL) -> URL {
        usageURL.deletingLastPathComponent().appendingPathComponent("sequence.json")
    }

    /// A command that ran this long after the previous one starts a new sequence.
    public nonisolated static let sessionWindow: TimeInterval = 600
    /// Events older than this are dropped at launch and on rotation.
    public nonisolated static let maxAge: TimeInterval = 400 * 86_400
    /// The most events kept. Rotation drops the oldest ones, in steps so it does not run on every append.
    public nonisolated static let maxEvents = 40_000
    nonisolated static let rotationSlack = 2_000

    public let url: URL
    public private(set) var events: [RunEvent] = []
    public private(set) var lastSaveError: String?
    public private(set) var recoveredFromCorruption = false
    /// Bumped on every change, so a model built from the log can tell when it is stale.
    public private(set) var revision = 0

    private var pendingWrite: Task<Void, Never>?
    private let writeDelay: Duration
    private var canSave = true
    private var generation = 0
    private let writer = LogWriter()

    public init(url: URL, writeDelay: Duration = .seconds(5), now: Date = Date()) {
        self.url = url
        self.writeDelay = writeDelay
        load(now: now)
    }

    // MARK: Recording

    /// Whether a run of this command may enter the log. Stricter than the usage store: content menus are left out.
    public static func isRecordable(_ command: Command) -> Bool {
        UsageStore.isRecordable(command) && PredictionPrivacy.isLoggable(command.stableID)
    }

    /// The commands run just before `date`, most recent first, at most two, each within the session window of the next.
    public func recentCommands(at date: Date = Date()) -> [CommandID] {
        var chain: [CommandID] = []
        var reference = date.timeIntervalSince1970
        for event in events.reversed() where event.kind == .run {
            guard reference - event.time <= Self.sessionWindow else { break }
            chain.append(event.command)
            reference = event.time
            if chain.count == 2 { break }
        }
        return chain
    }

    /// Logs one run. Returns the event, or nil when the identity is not allowed in the log.
    @discardableResult
    public func recordRun(
        _ id: CommandID, app: String?, contextKinds: [ContextKind] = [], offered: CommandID? = nil, at date: Date = Date()
    ) -> RunEvent? {
        let previous = recentCommands(at: date).first
        guard
            let event = RunEvent(
                kind: .run, at: date, command: id, app: app, previous: previous, contextKinds: contextKinds,
                offered: offered)
        else { return nil }
        append(event)
        return event
    }

    /// Logs that the person chose Not now on a predicted command.
    @discardableResult
    public func recordDismissal(
        of id: CommandID, app: String?, contextKinds: [ContextKind] = [], at date: Date = Date()
    ) -> RunEvent? {
        guard
            let event = RunEvent(
                kind: .dismiss, at: date, command: id, app: app, previous: recentCommands(at: date).first,
                contextKinds: contextKinds)
        else { return nil }
        append(event)
        return event
    }

    private func append(_ event: RunEvent) {
        events.append(event)
        if events.count > Self.maxEvents + Self.rotationSlack { rotate(now: event.date) }
        revision += 1
        scheduleWrite()
    }

    /// Drops events older than `maxAge` and the oldest ones beyond `maxEvents`.
    func rotate(now: Date) {
        let cutoff = now.timeIntervalSince1970 - Self.maxAge
        if let first = events.firstIndex(where: { $0.time >= cutoff }) {
            if first > 0 { events.removeFirst(first) }
        } else {
            events.removeAll()
        }
        if events.count > Self.maxEvents { events.removeFirst(events.count - Self.maxEvents) }
    }

    /// Forgets the whole log.
    public func clear() {
        guard !events.isEmpty else { return }
        events = []
        revision += 1
        scheduleWrite()
    }

    // MARK: Persistence

    /// Writes any pending change now. Call on quit.
    public func flush() {
        pendingWrite?.cancel()
        pendingWrite = nil
        guard canSave else { return }
        generation += 1
        apply(writer.write(events, to: url, generation: generation))
    }

    private func load(now: Date) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url) else {
            canSave = false
            return
        }
        guard let decoded = try? JSONDecoder().decode(SequenceFile.self, from: data) else {
            moveAside(now: now)
            recoveredFromCorruption = true
            return
        }
        if decoded.schemaVersion > SequenceFile.currentVersion { canSave = false }
        events = decoded.events.sorted { $0.time < $1.time }
        rotate(now: now)
        writer.seed(data)
    }

    private func moveAside(now: Date) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).broken-\(formatter.string(from: now))")
        if !FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.copyItem(at: url, to: backup) }
    }

    private func scheduleWrite() {
        pendingWrite?.cancel()
        guard canSave else { return }
        if writeDelay == .zero {
            pendingWrite = nil
            generation += 1
            apply(writer.write(events, to: url, generation: generation))
            return
        }
        let delay = writeDelay
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pendingWrite = nil
            await self?.writeInBackground()
        }
    }

    private func writeInBackground() async {
        generation += 1
        let token = generation
        let snapshot = events
        let target = url
        let writer = writer
        let outcome = await Task.detached(priority: .utility) {
            writer.write(snapshot, to: target, generation: token)
        }.value
        apply(outcome)
    }

    private func apply(_ outcome: LogWriter.Outcome) {
        switch outcome {
        case .written:
            lastSaveError = nil
        case .unchanged, .superseded:
            break
        case .failed(let message):
            lastSaveError = message
            AproposLog.app.error("sequence log save failed: \(message, privacy: .public)")
        }
    }
}

/// Encodes and writes the file. One lock and a generation number, so a slow background write can never overwrite the
/// result of a newer one, such as the flush on quit or a clear.
final class LogWriter: @unchecked Sendable {
    enum Outcome: Sendable {
        case written
        case unchanged
        case superseded
        case failed(String)
    }

    private let lock = NSLock()
    private var newest = 0
    private var lastData: Data?

    func seed(_ data: Data?) {
        lock.lock()
        lastData = data
        lock.unlock()
    }

    func write(_ events: [RunEvent], to url: URL, generation: Int) -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        guard generation > newest else { return .superseded }
        newest = generation
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(SequenceFile(events: events)) else { return .failed("encoding failed") }
        guard data != lastData else { return .unchanged }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            lastData = data
            return .written
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
