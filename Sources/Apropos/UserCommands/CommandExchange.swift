import Foundation

public enum CommandImportError: Error, Equatable, Sendable, CustomStringConvertible {
    case tooLarge
    case notACommandFile
    case newerVersion
    case tooManyCommands
    case empty

    public var description: String {
        switch self {
        case .tooLarge: "That file is too large to be a set of commands."
        case .notACommandFile: "That is not an Apropos commands file."
        case .newerVersion: "That file was made by a newer version of Apropos."
        case .tooManyCommands: "That file has too many commands."
        case .empty: "That file has no commands."
        }
    }
}

/// One command from a file, after checking and cleaning, waiting for the person's decision.
public struct ImportItem: Identifiable, Equatable, Sendable {
    /// The id the command will have once imported. Always fresh: ids in a file are never trusted.
    public var id: ActionID { command.id }
    public let command: UserCommand
    /// What the command does, in plain language, one fact per line.
    public let summary: [String]
    public let risks: [CommandRisk]
    /// True when the command runs a program or AppleScript: it will be stored as pending and must be approved.
    public let needsApproval: Bool
    /// The title of a command already stored (or earlier in the file) that does the same thing.
    public let duplicateOf: String?
    /// Aliases removed because another command already uses them.
    public let droppedAliases: [String]
}

public struct RejectedImport: Equatable, Sendable {
    public let position: Int
    public let title: String?
    public let reason: String
}

/// The result of reading a commands file: what would be added, and what was refused. Nothing is stored yet.
public struct ImportReview: Equatable, Sendable {
    public let items: [ImportItem]
    public let rejected: [RejectedImport]
    public let packName: String?

    /// Items that should be selected by default: all except duplicates.
    public var defaultSelection: Set<ActionID> { Set(items.filter { $0.duplicateOf == nil }.map(\.id)) }
}

public struct ImportResult: Equatable, Sendable {
    public let added: [UserCommand]
    public let failed: [RejectedImport]
}

/// Moves commands between people as one JSON file, and reads files that came from anywhere with strict checks.
///
/// Importing is two steps. `review` reads and validates the file and describes each command without storing anything.
/// `UserCommandStore.importReviewed` stores the ones the person picked. Commands that run a program or an AppleScript
/// are stored as pending and are not listed, bound to a key, run from a link or Shortcuts, or run at all until the
/// person approves them.
///
/// Nothing in a file is trusted beyond the command definition itself: ids, shortcuts, outside access and review state
/// are ignored and replaced.
public enum CommandExchange {
    public static let kind = "apropos.commands"
    public static let maxFileBytes = 1_000_000
    public static let maxCommands = 100

    // MARK: Export

    /// One file with the given commands. Shortcuts, outside access, approval state and ids of review are left out: those
    /// belong to one person's Mac.
    public static func export(_ commands: [UserCommand], name: String? = nil) throws -> Data {
        struct Envelope: Encodable {
            let schemaVersion: Int
            let kind: String
            let name: String?
            let commands: [UserCommandFile]
        }
        let entries = commands.map { command -> UserCommandFile in
            var file = UserCommandFile(command)
            file.allowFromURL = nil
            file.urlConfirmed = nil
            file.panelConfirmed = nil
            file.review = nil
            file.hotkey = nil
            return file
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope(schemaVersion: UserCommand.currentVersion, kind: kind, name: name, commands: entries))
            + Data("\n".utf8)
    }

    // MARK: Review

    public static func review(
        _ data: Data, existing: [UserCommand], functions: ActionFunctionRegistry = .builtin
    ) throws -> ImportReview {
        guard data.count <= maxFileBytes else { throw CommandImportError.tooLarge }

        struct Header: Decodable {
            let schemaVersion: Int
            let kind: String
            let name: String?
            let commands: [Lossy]
        }
        struct Lossy: Decodable {
            let file: UserCommandFile?
            init(from decoder: Decoder) throws { file = try? UserCommandFile(from: decoder) }
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.kind == kind else {
            throw CommandImportError.notACommandFile
        }
        guard header.schemaVersion <= UserCommand.currentVersion else { throw CommandImportError.newerVersion }
        guard !header.commands.isEmpty else { throw CommandImportError.empty }
        guard header.commands.count <= maxCommands else { throw CommandImportError.tooManyCommands }

        var takenAliases = Set(existing.flatMap(\.aliases))
        var seen: [(title: String, backend: ActionBackend)] = existing.map { ($0.title, $0.backend) }
        var items: [ImportItem] = []
        var rejected: [RejectedImport] = []

        for (position, entry) in header.commands.enumerated() {
            guard let file = entry.file else {
                rejected.append(RejectedImport(position: position, title: nil, reason: "not a valid command"))
                continue
            }
            let title = file.command.title
            do {
                // Fresh id and cleared trust fields: only the definition is taken from the file.
                var command = try file.makeCommand()
                command = UserCommand(
                    title: command.title, subtitle: command.subtitle, symbol: command.symbol, aliases: command.aliases,
                    apps: command.apps, requires: command.requires, conditions: command.conditions,
                    backend: command.backend, output: command.output, needsConfirmation: command.needsConfirmation,
                    keywords: command.keywords, timeout: command.timeout)
                command = try UserCommandValidator.normalized(command, functions: functions)

                var dropped: [String] = []
                command.aliases = command.aliases.filter { alias in
                    if takenAliases.contains(alias) {
                        dropped.append(alias)
                        return false
                    }
                    takenAliases.insert(alias)
                    return true
                }
                let risks = CommandSummary.risks(for: command)
                let needsApproval = risks.contains(where: \.needsApproval)
                command.review = needsApproval ? .pending : .approved
                let duplicate = seen.first { $0.title == command.title && $0.backend == command.backend }?.title
                seen.append((command.title, command.backend))
                items.append(
                    ImportItem(
                        command: command, summary: CommandSummary.lines(for: command), risks: risks,
                        needsApproval: needsApproval, duplicateOf: duplicate, droppedAliases: dropped))
            } catch let error as UserCommandError {
                rejected.append(RejectedImport(position: position, title: clipped(title), reason: error.description))
            } catch {
                rejected.append(RejectedImport(position: position, title: clipped(title), reason: "the command is incomplete"))
            }
        }
        return ImportReview(items: items, rejected: rejected, packName: header.name.map(clipped))
    }

    private static func clipped(_ text: String) -> String { String(text.prefix(80)) }
}

extension UserCommandStore {
    /// Stores the reviewed items the person selected (all non-duplicates when `selecting` is nil). Items that run a
    /// program or AppleScript are stored pending; approve them one by one with `approve(_:)` after the person has
    /// read `CommandSummary.lines(for:)`.
    @discardableResult
    public func importReviewed(_ review: ImportReview, selecting: Set<ActionID>? = nil) -> ImportResult {
        let chosen = selecting ?? review.defaultSelection
        var added: [UserCommand] = []
        var failed: [RejectedImport] = []
        for (position, item) in review.items.enumerated() where chosen.contains(item.id) {
            do {
                added.append(try create(item.command))
            } catch let error as UserCommandError {
                failed.append(RejectedImport(position: position, title: item.command.title, reason: error.description))
            } catch {
                failed.append(RejectedImport(position: position, title: item.command.title, reason: "could not be saved"))
            }
        }
        return ImportResult(added: added, failed: failed)
    }

    /// Reads a file from disk and reviews it. Refuses large files before reading them.
    public func reviewFile(at url: URL) throws -> ImportReview {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= CommandExchange.maxFileBytes else { throw CommandImportError.tooLarge }
        guard let data = try? Data(contentsOf: url) else { throw CommandImportError.notACommandFile }
        return try CommandExchange.review(data, existing: commands)
    }

    /// Writes the chosen commands (or all) to `url` as one file.
    public func exportCommands(_ ids: Set<ActionID>? = nil, name: String? = nil, to url: URL) throws {
        let chosen = commands.filter { ids?.contains($0.id) ?? true }
        try CommandExchange.export(chosen, name: name).write(to: url, options: .atomic)
    }
}
