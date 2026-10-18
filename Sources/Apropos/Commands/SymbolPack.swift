import Foundation

/// A curated set of SF Symbols for one app's menu commands. Packs are plain JSON so they can be written by hand and
/// shipped without a release:
///
/// ```json
/// {
///   "schemaVersion": 1,
///   "name": "Finder",
///   "bundleIDs": ["com.apple.finder"],
///   "commands": [
///     { "titles": ["New Folder", "Nouveau dossier"], "symbol": "folder.badge.plus" },
///     { "titles": ["as List"], "path": ["View"], "symbol": "list.bullet" },
///     { "shortcut": "⇧⌘N", "symbol": "folder.badge.plus" }
///   ]
/// }
/// ```
///
/// An entry matches a command by any of its `titles` (compared the way command identities are: case, diacritics,
/// ellipses and spacing ignored) and, when `path` is given, only inside that menu trail. An entry with only a
/// `shortcut` matches any command with that shortcut, as printed in menus. Title matches win over shortcut matches.
public struct SymbolPack: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public struct Entry: Codable, Sendable, Equatable {
        public var titles: [String]?
        public var path: [String]?
        public var shortcut: String?
        public var symbol: String

        public init(titles: [String]? = nil, path: [String]? = nil, shortcut: String? = nil, symbol: String) {
            self.titles = titles
            self.path = path
            self.shortcut = shortcut
            self.symbol = symbol
        }

        var isUsable: Bool {
            let hasMatcher = !(titles ?? []).isEmpty || !(shortcut ?? "").isEmpty
            return hasMatcher && !symbol.isEmpty && !symbol.contains(where: \.isWhitespace)
        }
    }

    public var schemaVersion = SymbolPack.currentVersion
    public var name: String
    public var bundleIDs: [String]
    public var commands: [Entry]

    public init(name: String, bundleIDs: [String], commands: [Entry]) {
        self.name = name
        self.bundleIDs = bundleIDs
        self.commands = commands
    }

    public static func decode(_ data: Data) throws -> SymbolPack {
        var pack = try JSONDecoder().decode(SymbolPack.self, from: data)
        pack.commands = pack.commands.filter(\.isUsable)
        return pack
    }
}

/// All the packs in effect, indexed for fast lookup. Later packs win over earlier ones, so a user pack overrides a
/// bundled one.
public struct SymbolPackLibrary: Sendable {
    private struct TitleEntry {
        let path: [String]?
        let symbol: String
    }

    private struct AppIndex {
        var byTitle: [String: [TitleEntry]] = [:]
        var byShortcut: [String: String] = [:]
    }

    private var apps: [String: AppIndex] = [:]
    public private(set) var packs: [SymbolPack]

    public init(packs: [SymbolPack] = []) {
        self.packs = packs
        for pack in packs {
            for bundleID in pack.bundleIDs {
                var index = apps[bundleID] ?? AppIndex()
                for entry in pack.commands {
                    let path = entry.path.map { $0.map(CommandID.normalize) }
                    for title in entry.titles ?? [] {
                        // Newest first, so later packs shadow earlier ones.
                        index.byTitle[CommandID.normalize(title), default: []].insert(
                            TitleEntry(path: path, symbol: entry.symbol), at: 0)
                    }
                    if let shortcut = entry.shortcut, !shortcut.isEmpty { index.byShortcut[shortcut] = entry.symbol }
                }
                apps[bundleID] = index
            }
        }
    }

    /// The packs shipped inside the package: Finder, Safari, Xcode and Claude.
    public static func bundled() -> SymbolPackLibrary {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "SymbolPacks") ?? []
        return SymbolPackLibrary(packs: load(urls: urls.sorted { $0.lastPathComponent < $1.lastPathComponent }))
    }

    /// Bundled packs, then every valid `*.json` in `directory` (for example `Application Support/Apropos/packs`). Files that
    /// cannot be read or have a newer schema version are skipped.
    public static func bundled(plus directory: URL?) -> SymbolPackLibrary {
        var packs = bundled().packs
        if let directory,
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        {
            packs += load(urls: names.filter { $0.hasSuffix(".json") }.sorted().map { directory.appendingPathComponent($0) })
        }
        return SymbolPackLibrary(packs: packs)
    }

    static func load(urls: [URL]) -> [SymbolPack] {
        urls.compactMap { url in
            guard let data = try? Data(contentsOf: url), let pack = try? SymbolPack.decode(data),
                pack.schemaVersion <= SymbolPack.currentVersion
            else {
                AproposLog.app.error("symbol pack skipped: \(url.lastPathComponent, privacy: .public)")
                return nil
            }
            return pack
        }
    }

    /// The pack's symbol for a command, or nil. Title entries are tried first, the one whose `path` matches before
    /// one without a `path`; a shortcut entry is the last resort.
    public func symbol(bundleID: String?, title: String, path: [String], shortcut: KeyShortcut?) -> String? {
        guard let bundleID, let index = apps[bundleID] else { return nil }
        if let entries = index.byTitle[CommandID.normalize(title)] {
            let trail = path.map(CommandID.normalize)
            if let exact = entries.first(where: { entry in entry.path.map { trail.suffix($0.count) == $0[...] } ?? false })
            {
                return exact.symbol
            }
            if let open = entries.first(where: { $0.path == nil }) { return open.symbol }
        }
        if let shortcut, let symbol = index.byShortcut[shortcut.display] { return symbol }
        return nil
    }
}
