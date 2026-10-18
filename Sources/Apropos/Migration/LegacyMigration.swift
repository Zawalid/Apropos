import Foundation

/// Brings data left by the app's former name (Cue) into its current home, once, without ever touching the old copy.
///
/// The old Application Support folder is copied into a scratch folder beside the new one, given a marker file, and
/// only then renamed into place. A failure at any point removes the scratch folder, leaves the old data as it was and
/// leaves the "done" flag unset so the next launch tries again. Nothing is moved or deleted from the old location, and
/// an existing new folder is never overwritten. Old `UserDefaults` values are copied only for keys the new domain has
/// not set.
public struct LegacyMigration {
    /// What a run did. Only counts and file names appear here, never contents.
    public enum Outcome: Equatable, Sendable {
        /// An earlier run finished.
        case alreadyDone
        /// Nothing to bring over: a fresh install.
        case nothingToMigrate
        case migrated(files: Int, defaultsKeys: Int, skipped: [String])
        /// The new folder already existed, so it was left alone. Defaults may still have been copied.
        case keptExistingFolder(defaultsKeys: Int)
        /// Something went wrong; the old data is untouched and the next launch retries.
        case failed(String)

        public var summary: String {
            switch self {
            case .alreadyDone: "legacy migration: already done"
            case .nothingToMigrate: "legacy migration: nothing to migrate"
            case .migrated(let files, let keys, let skipped):
                "legacy migration: copied \(files) files and \(keys) defaults keys, skipped \(skipped.count) unreadable"
            case .keptExistingFolder(let keys):
                "legacy migration: kept existing folder, copied \(keys) defaults keys"
            case .failed(let reason): "legacy migration failed: \(reason)"
            }
        }
    }

    // The former identity. These strings are history, not the app's name.
    public static let legacyFolderName = "Cue"
    public static let legacyDomain = "com.zawalid.cue"
    public static let markerName = "migrated-from-cue"
    public static let doneKey = "legacyMigrationDone"

    private let supportDirectory: URL
    private let folderName: String
    private let oldFolderName: String
    private let defaults: UserDefaults
    private let domain: String
    private let legacyDefaults: UserDefaults
    private let legacyDomain: String
    private let fileManager: FileManager

    /// - Parameters:
    ///   - supportDirectory: The Application Support directory holding both the old and the new folder.
    ///   - folderName: The new folder inside it.
    ///   - defaults: The new defaults; `domain` is its persistent domain name (the bundle id for `.standard`).
    ///   - legacyDefaults: Where the old domain is read from.
    public init(
        supportDirectory: URL, folderName: String, defaults: UserDefaults, domain: String,
        oldFolderName: String = LegacyMigration.legacyFolderName,
        legacyDefaults: UserDefaults = .standard, legacyDomain: String = LegacyMigration.legacyDomain,
        fileManager: FileManager = .default
    ) {
        self.supportDirectory = supportDirectory
        self.folderName = folderName
        self.oldFolderName = oldFolderName
        self.defaults = defaults
        self.domain = domain
        self.legacyDefaults = legacyDefaults
        self.legacyDomain = legacyDomain
        self.fileManager = fileManager
    }

    private var oldFolder: URL { supportDirectory.appendingPathComponent(oldFolderName, isDirectory: true) }
    private var newFolder: URL { supportDirectory.appendingPathComponent(folderName, isDirectory: true) }

    public func run() -> Outcome {
        if defaults.bool(forKey: Self.doneKey)
            || fileManager.fileExists(atPath: newFolder.appendingPathComponent(Self.markerName).path)
        {
            return .alreadyDone
        }
        // A build that still has the old identity has nothing to migrate from itself.
        if oldFolderName == folderName && legacyDomain == domain { return .alreadyDone }

        let hasOldFolder = isDirectory(oldFolder)
        let hasNewFolder = fileManager.fileExists(atPath: newFolder.path)
        var copied: (files: Int, skipped: [String]) = (0, [])
        var keptExisting = false

        if hasOldFolder && oldFolder != newFolder {
            if hasNewFolder {
                keptExisting = true
            } else {
                do {
                    copied = try copyFolder()
                } catch {
                    return .failed(error.localizedDescription)
                }
            }
        }

        let keys = copyDefaults()
        defaults.set(true, forKey: Self.doneKey)

        if keptExisting { return .keptExistingFolder(defaultsKeys: keys) }
        if !hasOldFolder && keys == 0 { return .nothingToMigrate }
        return .migrated(files: copied.files, defaultsKeys: keys, skipped: copied.skipped)
    }

    // MARK: Folder

    private func copyFolder() throws -> (files: Int, skipped: [String]) {
        let scratch = supportDirectory.appendingPathComponent(
            "\(folderName).migrating-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
            let result = try copyContents(into: scratch)
            let marker = scratch.appendingPathComponent(Self.markerName)
            try Data("copied from \(oldFolderName); the original was left in place\n".utf8).write(to: marker)
            try fileManager.moveItem(at: scratch, to: newFolder)
            return result
        } catch {
            try? fileManager.removeItem(at: scratch)
            throw error
        }
    }

    private func copyContents(into scratch: URL) throws -> (files: Int, skipped: [String]) {
        var files = 0
        var skipped: [String] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard
            let walker = fileManager.enumerator(
                at: oldFolder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return (0, []) }
        let basePath = oldFolder.standardizedFileURL.path
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: Set(keys))
            let relative = String(url.standardizedFileURL.path.dropFirst(basePath.count + 1))
            let destination = scratch.appendingPathComponent(relative)
            if values.isDirectory == true {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            guard values.isRegularFile == true else { continue }
            if url.pathExtension.lowercased() == "json", !isValidJSON(url) {
                skipped.append(relative)
                continue
            }
            try fileManager.copyItem(at: url, to: destination)
            files += 1
        }
        return (files, skipped)
    }

    private func isValidJSON(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: Defaults

    private func copyDefaults() -> Int {
        guard legacyDomain != domain, let old = legacyDefaults.persistentDomain(forName: legacyDomain) else { return 0 }
        let current = defaults.persistentDomain(forName: domain) ?? [:]
        var copied = 0
        for (key, value) in old where current[key] == nil {
            defaults.set(value, forKey: key)
            copied += 1
        }
        return copied
    }
}
