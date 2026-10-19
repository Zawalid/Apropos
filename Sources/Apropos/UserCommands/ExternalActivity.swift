import Foundation

/// Builds `apropos://` links, percent-encoded, in the exact form `ExternalRouter` accepts.
public enum ExternalLinks {
    public static let open = "apropos://open"

    public static func search(_ text: String = "") -> String {
        text.isEmpty ? "apropos://search?q=" : "apropos://search?q=\(encode(text))"
    }

    /// A run link for a command, by alias when it has one, else by id. Empty values are left out.
    public static func run(command: UserCommand, parameters: [ActionVariable: String] = [:]) -> String {
        run(reference: command.aliases.first ?? command.id.rawValue, parameters: parameters)
    }

    public static func run(reference: String, parameters: [ActionVariable: String] = [:]) -> String {
        var link = "apropos://run?command=\(encode(reference))"
        for variable in ExternalRouter.allowedVariables {
            if let value = parameters[variable], !value.isEmpty { link += "&\(variable.rawValue)=\(encode(value))" }
        }
        return link
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// One outside request, for the activity list. It holds what was asked and what happened, never the values passed in.
public struct ExternalActivityEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Result: String, Codable, Sendable {
        case ran, declined, refused, failed, turnedOff
    }

    public let time: Date
    /// "open", "search" or "run".
    public let action: String
    /// The command's title for a run, when it was found.
    public let command: String?
    public let result: Result

    public var id: String { "\(time.timeIntervalSince1970)|\(action)|\(command ?? "")" }
}

/// The last outside requests, kept in a small file. Titles and results only.
public final class ExternalActivityLog: @unchecked Sendable {
    public static let limit = 50

    public let url: URL
    private let lock = NSLock()
    private var stored: [ExternalActivityEntry]

    public init(url: URL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let data = try? Data(contentsOf: url), let entries = try? decoder.decode([ExternalActivityEntry].self, from: data) {
            stored = Array(entries.suffix(Self.limit))
        } else {
            stored = []
        }
    }

    /// `~/Library/Application Support/Apropos/external-activity.json`.
    @MainActor public static var defaultURL: URL {
        UsageStore.defaultURL.deletingLastPathComponent().appendingPathComponent("external-activity.json")
    }

    /// Newest first.
    public var entries: [ExternalActivityEntry] { lock.withLock { stored.reversed() } }

    public func record(action: String, command: String? = nil, result: ExternalActivityEntry.Result, at date: Date = Date()) {
        lock.withLock {
            stored.append(ExternalActivityEntry(time: date, action: action, command: command, result: result))
            if stored.count > Self.limit { stored.removeFirst(stored.count - Self.limit) }
            save()
        }
    }

    public func clear() {
        lock.withLock {
            stored = []
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(stored) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
