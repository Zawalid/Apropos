import CryptoKit
import Foundation

/// Copy or move into a folder. These destinations are built from a folder the person chose, so the folder is a literal
/// in the program's argument list and never a placeholder; the files are the only values.
public enum FolderDestinations {
    /// The id of a folder destination: `dest:folder.copy.<8 hex digits of the path's hash>`. Stable for a path, and the
    /// run log learns the hash, never the path.
    public static func id(for folder: URL, move: Bool) -> ActionID {
        let digest = SHA256.hash(data: Data(folder.standardizedFileURL.path.utf8))
        let hex = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return ActionID(rawValue: "dest:folder.\(move ? "move" : "copy").\(hex)")
    }

    /// "Copy to Downloads" / "Move to Downloads".
    public static func destination(for folder: URL, move: Bool) -> Destination? {
        let path = folder.standardizedFileURL.path
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let name = folder.lastPathComponent.isEmpty ? path : folder.lastPathComponent
        let program = move ? "/bin/mv" : "/bin/cp"
        // A trailing slash makes the tool refuse a destination that is not a folder instead of creating a file.
        let target = literal(path.hasSuffix("/") ? path : path + "/")
        func variant(_ kind: PayloadKind, placeholder: String) -> DestinationVariant? {
            var arguments = move ? ["-n", "--"] : ["-R", "-n", "--"]
            arguments.append(placeholder)
            arguments.append(target)
            guard let templates = try? arguments.map(ActionTemplate.init) else { return nil }
            let backend = ActionBackend.shell(ShellBackend(executable: program, arguments: templates))
            let action = ContextAction(
                id: id(for: folder, move: move), title: name, symbol: "folder",
                requires: [kind == .files ? .selectedFiles : .folder],
                backend: backend, output: .none)
            return DestinationVariant(kinds: [kind], action: action)
        }
        guard let files = variant(.files, placeholder: "{files}"), let whole = variant(.folder, placeholder: "{folder}")
        else { return nil }
        return Destination(
            id: id(for: folder, move: move), title: "\(move ? "Move" : "Copy") to \(name)", subtitle: abbreviated(path),
            symbol: move ? "folder.badge.minus" : "folder.badge.plus", keywords: ["folder", "copy", "move", name],
            accepts: [.files, .folder], variants: [files, whole], confirmation: move ? .preview : .none,
            previewVerb: "Move into \(name)", timeout: 60,
            failureHint: "A file with that name may already be there, or the folder is gone.", titleIsAction: true,
            origin: .bundled)
    }

    /// The row that asks for a folder first: "Copy to a folder...".
    public static func chooser(move: Bool) -> Destination {
        Destination(
            id: ActionID(rawValue: move ? "dest:folder.choose.move" : "dest:folder.choose.copy"),
            title: move ? "Move to a folder..." : "Copy to a folder...",
            subtitle: "Choose where, then it is remembered", symbol: "folder.badge.questionmark",
            keywords: ["folder", "copy", "move", "choose"], accepts: [.files, .folder],
            handler: .chooseFolder(move: move), titleIsAction: true, origin: .bundled)
    }

    /// Braces in a path are literal text in a template.
    static func literal(_ path: String) -> String {
        path.replacingOccurrences(of: "{", with: "{{").replacingOccurrences(of: "}", with: "}}")
    }

    static func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// The folders the person copied or moved into, most recent first, kept in a small JSON file so the second time is one
/// keystroke. Only existing folders are returned.
public final class SendFolderStore: @unchecked Sendable {
    public static let limit = 5

    private let url: URL
    private let lock = NSLock()
    private var paths: [String]

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode([String].self, from: data) {
            paths = Array(stored.filter { $0.hasPrefix("/") }.prefix(Self.limit))
        } else {
            paths = []
        }
    }

    /// `~/Library/Application Support/Apropos/send-folders.json`.
    @MainActor public static var defaultURL: URL {
        UsageStore.defaultURL.deletingLastPathComponent().appendingPathComponent("send-folders.json")
    }

    /// Remembered folders that still exist, most recent first.
    public var folders: [URL] {
        lock.withLock {
            paths.filter { FileManager.default.fileExists(atPath: $0) }.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
        }
    }

    /// Puts a folder at the front of the list.
    public func remember(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        lock.withLock {
            paths = Array(([path] + paths.filter { $0 != path }).prefix(Self.limit))
            if let data = try? JSONEncoder().encode(paths) {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// Removes one folder from the remembered list.
    public func forget(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        lock.withLock {
            paths.removeAll { $0 == path }
            if let data = try? JSONEncoder().encode(paths) { try? data.write(to: url, options: .atomic) }
        }
    }

    public func forgetAll() {
        lock.withLock {
            paths = []
            try? FileManager.default.removeItem(at: url)
        }
    }
}
