import Foundation

/// Which destinations the person turned off, kept in a small file next to the remembered folders.
public final class DestinationToggles: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var ids: Set<String>

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode([String].self, from: data) {
            ids = Set(stored)
        } else {
            ids = []
        }
    }

    /// `~/Library/Application Support/Apropos/send-disabled.json`.
    @MainActor public static var defaultURL: URL {
        UsageStore.defaultURL.deletingLastPathComponent().appendingPathComponent("send-disabled.json")
    }

    public var disabled: Set<ActionID> { lock.withLock { Set(ids.map { ActionID(rawValue: $0) }) } }

    public func isEnabled(_ id: ActionID) -> Bool { lock.withLock { !ids.contains(id.rawValue) } }

    public func set(_ id: ActionID, enabled: Bool) {
        lock.withLock {
            if enabled { ids.remove(id.rawValue) } else { ids.insert(id.rawValue) }
            if let data = try? JSONEncoder().encode(ids.sorted()) {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
