import Foundation

/// What a person fills in to make a destination by hand. It becomes a pack file in the destinations folder, checked by
/// the same validator as every pack, and is approved because the person wrote it through this form.
public struct DestinationDraft: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable, Identifiable {
        case link, shortcut, appendToFile

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .link: "Open a link with it"
            case .shortcut: "Run a Shortcut with it"
            case .appendToFile: "Add it to a file"
            }
        }

        public var explanation: String {
            switch self {
            case .link: "Opens an app link or web address. Write {text}, {title} or {url} where the content should go."
            case .shortcut: "Runs an Apple Shortcut and hands it the selected text as its input."
            case .appendToFile: "Adds the selected text to the end of a text file, such as a running notes file."
            }
        }

        public var symbol: String {
            switch self {
            case .link: "link"
            case .shortcut: "square.stack.3d.up"
            case .appendToFile: "doc.badge.plus"
            }
        }
    }

    public struct Problem: Error, Equatable, Sendable, CustomStringConvertible {
        public let description: String
    }

    public var kind: Kind = .link
    public var title = ""
    public var link = ""
    public var shortcutName = ""
    /// Absolute path of the file for `.appendToFile`.
    public var filePath = ""
    public var acceptsPages = false
    /// The symbol the person chose. Empty means the kind's own.
    public var symbol = ""

    public init() {}

    /// The file name to save the pack under.
    public var fileName: String {
        let slug = title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return "my-\(slug.isEmpty ? "destination" : String(slug.prefix(40))).json"
    }

    /// The pack file, as JSON the destination library reads. Throws a plain-language problem when a field is missing or
    /// the validator refuses the result.
    public func packData() throws -> Data {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Problem(description: "Give the destination a name.") }
        var accepts = ["text"]
        if acceptsPages || kind == .link { accepts.append("page") }
        let backend: [String: Any]
        switch kind {
        case .link:
            let address = link.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { throw Problem(description: "Enter the address to open.") }
            backend = ["type": "urlScheme", "url": address]
        case .shortcut:
            let shortcut = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !shortcut.isEmpty else { throw Problem(description: "Enter the name of the Shortcut.") }
            backend = ["type": "shortcut", "name": shortcut, "input": "text"]
        case .appendToFile:
            let path = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/") else { throw Problem(description: "Enter the full path of the file, starting with /.") }
            backend = ["type": "shell", "executable": "/usr/bin/tee", "arguments": ["-a", path], "stdin": "text"]
        }
        let slug = String(fileName.dropFirst(3).dropLast(5))
        let destination: [String: Any] = [
            "id": "user:\(slug)", "title": name, "symbol": symbol.isEmpty ? kind.symbol : symbol, "accepts": accepts, "review": "approved",
            "variants": [["backend": backend]],
        ]
        let pack: [String: Any] = ["schemaVersion": 1, "name": name, "destinations": [destination]]
        let data = try JSONSerialization.data(withJSONObject: pack, options: [.prettyPrinted, .sortedKeys])
        var check = DestinationLibrary()
        check.add(packData: data, source: fileName, origin: .user)
        if let issue = check.issues.first(where: { !$0.reason.contains("waiting for approval") }) {
            throw Problem(description: "That cannot be used: \(issue.reason).")
        }
        guard check.runnable.count == 1 else { throw Problem(description: "That cannot be used.") }
        return data
    }

    /// Writes the pack into `directory`, creating it first. Returns the file written.
    @discardableResult
    public func save(to directory: URL) throws -> URL {
        let data = try packData()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Plain-language descriptions of a destination, for the review sheet.
public enum DestinationSummary {
    public static func lines(for destination: Destination) -> [String] {
        var lines: [String] = []
        let kinds = destination.accepts.map(\.rawValue).sorted().joined(separator: ", ")
        lines.append("Takes: \(kinds).")
        switch destination.handler {
        case .shareMenu: lines.append("Opens the system Share menu.")
        case .chooseFolder(let move):
            lines.append("Asks you for a folder, then \(move ? "moves" : "copies") the files into it.")
        case .engine:
            for variant in destination.variants {
                let command = UserCommand(
                    title: destination.title, requires: variant.action.requires, backend: variant.action.backend,
                    output: .none)
                let part = variant.kinds.isEmpty ? "" : "For \(variant.kinds.map(\.rawValue).sorted().joined(separator: ", ")): "
                lines += CommandSummary.lines(for: command)
                    .filter { !$0.hasPrefix("Needs:") && !$0.hasPrefix("Works in") }
                    .enumerated().map { $0.offset == 0 ? part + $0.element : $0.element }
            }
        }
        if destination.confirmation == .preview { lines.append("Shows what it will send and waits for a second Return.") }
        if let limit = destination.maxTextCharacters { lines.append("Text longer than \(limit) characters is refused.") }
        return lines
    }

    public static func risks(for destination: Destination) -> [CommandRisk] {
        var risks: [CommandRisk] = []
        for variant in destination.variants {
            let command = UserCommand(
                title: destination.title, requires: variant.action.requires, backend: variant.action.backend,
                output: .none)
            for risk in CommandSummary.risks(for: command) where !risks.contains(risk) { risks.append(risk) }
        }
        return risks
    }
}
