import Foundation
import Observation

/// A file in the commands folder that could not be used, and why. Never includes the file's contents.
public struct CommandFileIssue: Sendable, Equatable {
    public let fileName: String
    public let reason: String
}

public enum HotKeyConflict: Sendable, Equatable {
    /// The shortcut that opens the panel.
    case panel
    case command(title: String)
}

/// The person's own commands, one JSON file each in `Application Support/Apropos/commands`. Observable for SwiftUI.
///
/// Every write is atomic. Before a file is replaced or removed, the old version is copied into `history/` and the last
/// few per command are kept, so an edit or a deletion can be undone by copying a file back. Files edited by hand are
/// picked up by `reload()`; a file that cannot be used is skipped and reported in `issues`, the rest still load.
@MainActor
@Observable
public final class UserCommandStore {
    public static let folderName = "commands"

    /// `~/Library/Application Support/Apropos/commands`.
    public static var defaultDirectory: URL {
        SettingsStore.supportDirectory.appendingPathComponent("\(SettingsStore.folderName)/\(folderName)", isDirectory: true)
    }

    public let directory: URL
    public let historyLimit: Int
    /// Every stored command, pending ones included, by title.
    public private(set) var commands: [UserCommand] = []
    public private(set) var issues: [CommandFileIssue] = []
    /// Changes whenever `commands` is replaced, for views that cache.
    public private(set) var revision = 0

    /// Shortcuts that no command may take, such as the panel's. Set by the app.
    @ObservationIgnored public var reservedHotKeys: () -> [HotKeyCombo] = { [] }
    /// Called after every change to the stored commands (including `reload()`).
    @ObservationIgnored public var onChange: (() -> Void)?

    @ObservationIgnored private let functions: ActionFunctionRegistry
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var fileNames: [ActionID: String] = [:]

    public init(
        directory: URL = UserCommandStore.defaultDirectory, functions: ActionFunctionRegistry = .builtin,
        historyLimit: Int = 5, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.functions = functions
        self.historyLimit = max(historyLimit, 0)
        self.now = now
        reload()
    }

    // MARK: Reading

    /// Approved commands: the ones that may be listed, bound to keys and run.
    public var runnable: [UserCommand] { commands.filter(\.isRunnable) }

    /// Imported commands waiting for the person to read and approve them.
    public var pending: [UserCommand] { commands.filter { !$0.isRunnable } }

    public func command(withID id: ActionID) -> UserCommand? { commands.first { $0.id == id } }

    /// Finds a runnable command by its id or, failing that, by alias (case-insensitive).
    public func runnableCommand(matching reference: String) -> UserCommand? {
        let wanted = reference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return runnable.first { $0.id.rawValue == wanted } ?? runnable.first { $0.aliases.contains(wanted) }
    }

    public func hotkeyConflict(_ combo: HotKeyCombo, excluding id: ActionID?) -> HotKeyConflict? {
        if reservedHotKeys().contains(combo) { return .panel }
        if let other = commands.first(where: { $0.id != id && $0.hotkey == combo }) { return .command(title: other.title) }
        return nil
    }

    // MARK: Changing

    /// Adds a command. A draft is made with `UserCommand(title:backend:...)`, which picks a fresh id.
    @discardableResult
    public func create(_ draft: UserCommand) throws -> UserCommand {
        guard command(withID: draft.id) == nil else { throw UserCommandError.badID }
        let checked = try check(draft)
        try write(checked)
        insert(checked)
        return checked
    }

    @discardableResult
    public func update(_ edited: UserCommand) throws -> UserCommand {
        guard let existing = command(withID: edited.id) else { throw UserCommandError.notFound }
        var checked = try check(edited)
        // A different backend is a different command as far as outside callers go: ask again before the next run.
        if checked.backend != existing.backend { checked.urlConfirmed = false }
        // A pending command stays pending until `approve`, whatever an edit says.
        if existing.review == .pending { checked.review = .pending }
        try write(checked)
        insert(checked)
        return checked
    }

    public func delete(_ id: ActionID) throws {
        guard command(withID: id) != nil else { throw UserCommandError.notFound }
        let file = url(for: id)
        archive(file, id: id)
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            throw UserCommandError.saveFailed
        }
        fileNames[id] = nil
        commands.removeAll { $0.id == id }
        changed()
    }

    /// A copy with a new id and title, no shortcut and no outside access. Aliases are not copied: they are unique.
    @discardableResult
    public func duplicate(_ id: ActionID) throws -> UserCommand {
        guard let original = command(withID: id) else { throw UserCommandError.notFound }
        var copy = original
        copy = UserCommand(
            title: original.title + " copy", subtitle: original.subtitle, symbol: original.symbol, aliases: [],
            apps: original.apps, requires: original.requires, conditions: original.conditions,
            backend: original.backend, output: original.output, needsConfirmation: original.needsConfirmation,
            keywords: original.keywords, timeout: original.timeout, review: original.review)
        return try create(copy)
    }

    /// The person read a pending command and allows it to run.
    @discardableResult
    public func approve(_ id: ActionID) throws -> UserCommand {
        guard var command = command(withID: id) else { throw UserCommandError.notFound }
        command.review = .approved
        try write(command)
        insert(command)
        return command
    }

    public func setAllowFromURL(_ allowed: Bool, for id: ActionID) throws {
        guard var command = command(withID: id) else { throw UserCommandError.notFound }
        guard command.isRunnable else { throw UserCommandError.pendingReview }
        command.allowFromURL = allowed
        if !allowed { command.urlConfirmed = false }
        try write(command)
        insert(command)
    }

    /// Records that the person confirmed the first outside run of this command.
    public func markURLConfirmed(_ id: ActionID) throws {
        guard var command = command(withID: id) else { throw UserCommandError.notFound }
        command.urlConfirmed = true
        try write(command)
        insert(command)
    }

    /// Forgets that the first outside run was confirmed, so the next one asks again.
    public func resetURLConfirmation(_ id: ActionID) throws {
        guard var command = command(withID: id) else { throw UserCommandError.notFound }
        command.urlConfirmed = false
        try write(command)
        insert(command)
    }

    /// Reads the folder again, for files edited by hand.
    public func reload() {
        var loaded: [UserCommand] = []
        var problems: [CommandFileIssue] = []
        var names: [ActionID: String] = [:]
        var claimedAliases: [String: String] = [:]
        var claimedKeys: [HotKeyCombo: String] = [:]
        let reserved = reservedHotKeys()

        let listing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in listing.filter({ $0.hasSuffix(".json") }).sorted() {
            let file = directory.appendingPathComponent(name)
            do {
                var command = try Self.read(file, functions: functions)
                if names[command.id] != nil { throw CommandFileFailure("another file has the same id") }
                command.aliases = command.aliases.filter { alias in
                    if claimedAliases[alias] != nil {
                        problems.append(CommandFileIssue(fileName: name, reason: "alias \(alias) is already taken"))
                        return false
                    }
                    claimedAliases[alias] = command.title
                    return true
                }
                if let key = command.hotkey, reserved.contains(key) || claimedKeys[key] != nil {
                    problems.append(CommandFileIssue(fileName: name, reason: "its shortcut is already used"))
                    command.hotkey = nil
                } else if let key = command.hotkey {
                    claimedKeys[key] = command.title
                }
                names[command.id] = name
                loaded.append(command)
            } catch let error as UserCommandError {
                problems.append(CommandFileIssue(fileName: name, reason: error.description))
            } catch let failure as CommandFileFailure {
                problems.append(CommandFileIssue(fileName: name, reason: failure.reason))
            } catch {
                problems.append(CommandFileIssue(fileName: name, reason: "could not be read"))
            }
        }
        commands = loaded.sorted(by: Self.byTitle)
        issues = problems
        fileNames = names
        changed()
    }

    // MARK: Internals

    struct CommandFileFailure: Error {
        let reason: String
        init(_ reason: String) { self.reason = reason }
    }

    private static func byTitle(_ lhs: UserCommand, _ rhs: UserCommand) -> Bool {
        let order = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        return order == .orderedSame ? lhs.id.rawValue < rhs.id.rawValue : order == .orderedAscending
    }

    static func read(_ file: URL, functions: ActionFunctionRegistry) throws -> UserCommand {
        guard let data = try? Data(contentsOf: file) else { throw UserCommandError.unreadable }
        return try decode(data, functions: functions)
    }

    static func decode(_ data: Data, functions: ActionFunctionRegistry) throws -> UserCommand {
        guard data.count <= UserCommandLimits.maxFileBytes else { throw CommandFileFailure("the file is too large") }
        guard let version = (try? JSONDecoder().decode(VersionOnly.self, from: data))?.schemaVersion else {
            throw CommandFileFailure("not a command file")
        }
        guard version <= UserCommand.currentVersion else { throw UserCommandError.newerVersion }
        guard let file = try? JSONDecoder().decode(UserCommandFile.self, from: data) else {
            throw CommandFileFailure("not a valid command file")
        }
        do {
            return try UserCommandValidator.normalized(try file.makeCommand(), functions: functions)
        } catch is ActionDefinition.ConversionError {
            throw UserCommandError.badBackend
        }
    }

    private struct VersionOnly: Decodable { let schemaVersion: Int }

    /// Normalizes and checks everything that depends on the other commands.
    private func check(_ draft: UserCommand) throws -> UserCommand {
        let command = try UserCommandValidator.normalized(draft, functions: functions)
        for alias in command.aliases {
            if let owner = commands.first(where: { $0.id != command.id && $0.aliases.contains(alias) }) {
                throw UserCommandError.aliasTaken(alias: alias, by: owner.title)
            }
        }
        if let key = command.hotkey, let conflict = hotkeyConflict(key, excluding: command.id) {
            switch conflict {
            case .panel: throw UserCommandError.hotkeyTaken(by: "Apropos")
            case .command(let title): throw UserCommandError.hotkeyTaken(by: title)
            }
        }
        return command
    }

    private func url(for id: ActionID) -> URL {
        let name = fileNames[id] ?? String(id.rawValue.dropFirst("user:".count)) + ".json"
        return directory.appendingPathComponent(name)
    }

    private func write(_ command: UserCommand) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(UserCommandFile(command)) + Data("\n".utf8)
            let file = url(for: command.id)
            if let existing = try? Data(contentsOf: file), existing == data { return }
            archive(file, id: command.id)
            try data.write(to: file, options: .atomic)
            fileNames[command.id] = file.lastPathComponent
        } catch {
            throw UserCommandError.saveFailed
        }
    }

    private func insert(_ command: UserCommand) {
        commands.removeAll { $0.id == command.id }
        commands.append(command)
        commands.sort(by: Self.byTitle)
        changed()
    }

    private func changed() {
        revision += 1
        onChange?()
    }

    /// Copies a file about to be replaced or removed into `history/<name>-<stamp>.json` and trims old copies.
    private func archive(_ file: URL, id: ActionID) {
        guard historyLimit > 0, FileManager.default.fileExists(atPath: file.path) else { return }
        let history = directory.appendingPathComponent("history", isDirectory: true)
        try? FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        let base = file.deletingPathExtension().lastPathComponent
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        var name = "\(base)-\(formatter.string(from: now())).json"
        var counter = 1
        while FileManager.default.fileExists(atPath: history.appendingPathComponent(name).path) {
            counter += 1
            name = "\(base)-\(formatter.string(from: now()))-\(counter).json"
        }
        try? FileManager.default.copyItem(at: file, to: history.appendingPathComponent(name))
        let mine = ((try? FileManager.default.contentsOfDirectory(atPath: history.path)) ?? [])
            .filter { $0.hasPrefix(base + "-") }.sorted(by: >)
        for stale in mine.dropFirst(historyLimit) { try? FileManager.default.removeItem(at: history.appendingPathComponent(stale)) }
    }

    /// Earlier saved versions of a command, newest first.
    public func history(of id: ActionID) -> [URL] {
        let history = directory.appendingPathComponent("history", isDirectory: true)
        let base = url(for: id).deletingPathExtension().lastPathComponent
        return ((try? FileManager.default.contentsOfDirectory(atPath: history.path)) ?? [])
            .filter { $0.hasPrefix(base + "-") }.sorted(by: >).map { history.appendingPathComponent($0) }
    }
}
