import Foundation
import Observation

/// What a send-to row stands for.
public enum SendTarget: Sendable, Hashable {
    /// "Send selection to...": opens the destination list for this kind of payload.
    case generic(PayloadKind)
    /// A destination for one kind of payload: "Send selection to Notes".
    case destination(ActionID, PayloadKind)

    public var kind: PayloadKind {
        switch self {
        case .generic(let kind), .destination(_, let kind): kind
        }
    }

    /// The identity usage, pins and the run log use: ids only. `send:text` and `send:text>dest:notes`. The kind is part
    /// of it, so a destination is ranked separately for text, pages and files.
    public var commandID: CommandID {
        switch self {
        case .generic(let kind): CommandID(rawValue: "send:\(kind.rawValue)")
        case .destination(let id, let kind): CommandID(rawValue: "send:\(kind.rawValue)>\(id.rawValue)")
        }
    }
}

/// The second level of the palette: the destinations for one payload.
public struct SendLevel: Equatable, Sendable {
    public let kind: PayloadKind
    /// The breadcrumb: "Send selection to".
    public let title: String
}

/// A send waiting for the person's Return: what will happen, in one line.
public struct SendPending: Sendable {
    public let command: Command
    public let destinationTitle: String
    /// "Open a draft in Mail: "Title" (240 characters)".
    public let line: String
}

/// What `perform` did with a row.
public enum SendStep: Sendable {
    /// The generic row opened the destination list.
    case enteredLevel
    /// The destination asks first; the preview is in `SendToCenter.pending`.
    case needsConfirmation
    /// Sent. The command is the row that was actually sent, which differs from the one chosen when a folder was picked.
    case sent(SendOutcome, Command)
    case failed(SendError)
}

/// The send-to layer of the palette. It turns the latest context snapshot into payloads and rows (a generic "Send
/// selection to..." row and the person's most used destinations), keeps the second level destination list, and sends.
///
/// Rules it keeps, with tests:
/// - Nothing is sent without a Return. A destination that leaves the Mac or leaves a visible side effect shows a
///   one-line preview first and needs a second, confirming Return.
/// - The payload is held here for as long as the destination list is open, so a failure leaves it intact for a retry or
///   another destination.
/// - Destination ranking is the usage store's: `send:<kind>>dest:<name>` ids, counted per payload kind.
@MainActor
@Observable
public final class SendToCenter {
    /// Bumped whenever the rows or the level change, so the palette's cached list is rebuilt.
    public private(set) var revision = 0
    /// Set while the destination list is open.
    public private(set) var level: SendLevel?
    /// Set while a send waits for the confirming Return.
    public private(set) var pending: SendPending?

    @ObservationIgnored public private(set) var library: DestinationLibrary
    @ObservationIgnored private let runner: DestinationRunner
    @ObservationIgnored private let services: SendServices
    @ObservationIgnored private let folders: SendFolderStore
    @ObservationIgnored private var values = ContextValues()
    @ObservationIgnored private var bundleID: String?
    @ObservationIgnored private var capturedAt = Date.distantPast
    @ObservationIgnored private var snapshotPID: pid_t?
    @ObservationIgnored private var payloads: [Payload] = []
    @ObservationIgnored private var levelPayload: Payload?
    @ObservationIgnored private var cachedRoot: [Command] = []
    @ObservationIgnored private var cachedLevel: [Command] = []
    @ObservationIgnored private var pendingPayload: Payload?
    @ObservationIgnored private var pendingDestination: Destination?
    /// The learned score of a command id. Wire to the usage store.
    @ObservationIgnored public var frecency: @MainActor (CommandID) -> Double = { _ in 0 }
    /// Asks the person for a folder. Wire to an open panel; nil means cancelled.
    @ObservationIgnored public var chooseFolder: (@MainActor (_ move: Bool) async -> URL?)?

    /// The most direct "Send selection to Notes" rows listed beside the generic row.
    public static let directRows = 2
    /// Remembered folders offered as destinations (a copy and a move row each).
    public static let folderRows = 3

    public init(
        library: DestinationLibrary = .bundled(), services: SendServices = .live,
        folders: SendFolderStore = SendFolderStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent(
                "apropos-send-folders-\(UUID().uuidString).json"))
    ) {
        self.library = library
        self.services = services
        self.folders = folders
        runner = DestinationRunner(services: services)
    }

    public func reload(_ library: DestinationLibrary) {
        self.library = library
        rebuild()
    }

    // MARK: Context

    /// Takes a fresh snapshot. An older one than already used is ignored.
    public func update(with snapshot: ContextSnapshot) {
        guard snapshot.capturedAt >= capturedAt else { return }
        capturedAt = snapshot.capturedAt
        values = snapshot.values
        bundleID = snapshot.bundleID
        snapshotPID = snapshot.pid
        rebuild()
    }

    /// Forgets the context: sensing was turned off or the panel closed.
    public func clear() {
        capturedAt = .distantPast
        values = ContextValues()
        snapshotPID = nil
        rebuild()
    }

    /// The panel opened for `app`: forget the last snapshot and any open level, so a stale selection is never sent.
    public func beginSession(for app: TargetApp?) {
        capturedAt = .distantPast
        values = ContextValues()
        bundleID = app?.bundleID
        snapshotPID = app?.pid
        level = nil
        levelPayload = nil
        pending = nil
        pendingPayload = nil
        pendingDestination = nil
        rebuild()
    }

    /// The app the rows were built for, so another app's selection never offers rows.
    public var pid: pid_t? { snapshotPID }

    /// Recomputes the rows, for example after a send changed what the usage store knows.
    public func refresh() { rebuild() }

    // MARK: Rows

    /// The rows beside the context actions: per payload, the generic row and the most used destinations.
    public var rootCommands: [Command] { cachedRoot }

    /// The destination list of the open level, best first.
    public var levelCommands: [Command] { cachedLevel }

    private func rebuild() {
        payloads = Payload.candidates(from: values, bundleID: bundleID)
        var root: [Command] = []
        for payload in payloads {
            let available = availableDestinations(for: payload)
            guard !available.isEmpty else { continue }
            root.append(Self.genericCommand(for: payload))
            let used = available.filter { $0.sizeProblem(for: payload) == nil }
                .map { (destination: $0, score: frecency(SendTarget.destination($0.id, payload.kind).commandID)) }
                .filter { $0.score > 0 }
                .sorted { $0.score > $1.score }
                .prefix(Self.directRows)
            for item in used {
                root.append(directCommand(item.destination, payload: payload))
            }
        }
        cachedRoot = root
        cachedLevel = levelPayload.map(levelRows) ?? []
        revision += 1
    }

    private func availableDestinations(for payload: Payload) -> [Destination] {
        var all = library.runnable
        if payload.kind == .files || payload.kind == .folder {
            for folder in folders.folders.prefix(Self.folderRows) {
                if let copy = FolderDestinations.destination(for: folder, move: false) { all.append(copy) }
                if let move = FolderDestinations.destination(for: folder, move: true) { all.append(move) }
            }
            all.append(FolderDestinations.chooser(move: false))
            all.append(FolderDestinations.chooser(move: true))
        }
        return all.filter { destination in
            destination.accepts(payload) && (destination.appBundleID.map(services.isInstalled) ?? true)
        }
    }

    private static func genericCommand(for payload: Payload) -> Command {
        var command = Command(
            id: SendTarget.generic(payload.kind).commandID.rawValue, title: "Send \(payload.noun) to...",
            path: [payload.kind.group.title], source: .sendTo(.generic(payload.kind)))
        command.symbolName = "paperplane"
        command.keywords = ["share", "send", "export", "move", "save", "forward"]
        command.detail = "Choose where it goes"
        return command
    }

    private func directCommand(_ destination: Destination, payload: Payload) -> Command {
        let title: String
        if destination.titleIsAction {
            title = destination.title
        } else if destination.handler == .shareMenu {
            title = "Share \(payload.noun)..."
        } else {
            title = "Send \(payload.noun) to \(destination.title)"
        }
        var command = Command(
            id: SendTarget.destination(destination.id, payload.kind).commandID.rawValue, title: title,
            path: [payload.kind.group.title], source: .sendTo(.destination(destination.id, payload.kind)))
        command.symbolName = destination.symbol
        command.keywords = destination.keywords + ["send"]
        command.detail = destination.subtitle
        command.needsConfirmation = destination.confirmation == .preview
        return command
    }

    private func levelRows(for payload: Payload) -> [Command] {
        let title = Self.levelTitle(for: payload)
        let entries = availableDestinations(for: payload)
        var rows: [(command: Command, score: Double, order: Int)] = []
        for (order, destination) in entries.enumerated() {
            let problem = destination.sizeProblem(for: payload)
            var command = Command(
                id: SendTarget.destination(destination.id, payload.kind).commandID.rawValue, title: destination.title,
                path: [title], isEnabled: problem == nil, source: .sendTo(.destination(destination.id, payload.kind)))
            command.symbolName = destination.symbol
            command.keywords = destination.keywords
            command.detail = problem ?? destination.subtitle
            command.needsConfirmation = destination.confirmation == .preview
            rows.append((command, problem == nil ? frecency(command.stableID) : -1, order))
        }
        // Most used first for this kind of payload; the library's own order breaks ties and orders the unused.
        return rows.sorted { ($0.score, -$0.order) > ($1.score, -$1.order) }.map(\.command)
    }

    static func levelTitle(for payload: Payload) -> String { "Send \(payload.noun) to" }

    // MARK: Running

    /// Runs a row of this center. `confirmed` is true for the confirming Return.
    public func perform(_ command: Command, confirmed: Bool = false) async -> SendStep {
        guard case .sendTo(let target) = command.source else { return .failed(.cancelled) }
        switch target {
        case .generic(let kind):
            guard let payload = payloads.first(where: { $0.kind == kind }) else {
                return .failed(.notApplicable(destination: "That"))
            }
            levelPayload = payload
            level = SendLevel(kind: kind, title: Self.levelTitle(for: payload))
            pending = nil
            rebuild()
            return .enteredLevel
        case .destination(let id, let kind):
            let payload = levelPayload?.kind == kind ? levelPayload : payloads.first { $0.kind == kind }
            guard let payload else { return .failed(.notApplicable(destination: "That")) }
            guard let destination = resolve(id, payload: payload) else {
                return .failed(.notApplicable(destination: "That"))
            }
            return await send(destination, payload: payload, command: command, confirmed: confirmed)
        }
    }

    /// The Return that confirms the pending send.
    public func confirmPending() async -> SendStep? {
        guard let pending, let payload = pendingPayload, let destination = pendingDestination else { return nil }
        return await send(destination, payload: payload, command: pending.command, confirmed: true)
    }

    private func send(
        _ destination: Destination, payload: Payload, command: Command, confirmed: Bool
    ) async -> SendStep {
        var destination = destination
        var command = command
        if case .chooseFolder(let move) = destination.handler {
            guard let chooseFolder, let folder = await chooseFolder(move) else { return .failed(.cancelled) }
            folders.remember(folder)
            guard let concrete = FolderDestinations.destination(for: folder, move: move) else {
                return .failed(.notApplicable(destination: destination.title))
            }
            destination = concrete
            command = Command(
                id: SendTarget.destination(concrete.id, payload.kind).commandID.rawValue, title: concrete.title,
                path: command.path, source: .sendTo(.destination(concrete.id, payload.kind)))
            rebuild()
        }
        switch await runner.send(destination, payload: payload, confirmed: confirmed) {
        case .success(let outcome):
            clearPending()
            return .sent(outcome, command)
        case .failure(.confirmationRequired):
            pending = SendPending(
                command: command, destinationTitle: destination.title, line: destination.previewLine(for: payload))
            pendingPayload = payload
            pendingDestination = destination
            revision += 1
            return .needsConfirmation
        case .failure(let error):
            clearPending()
            return .failed(error)
        }
    }

    private func resolve(_ id: ActionID, payload: Payload) -> Destination? {
        availableDestinations(for: payload).first { $0.id == id }
            ?? folders.folders.compactMap { folder in
                [false, true].compactMap { FolderDestinations.destination(for: folder, move: $0) }
            }.flatMap { $0 }.first { $0.id == id }
    }

    private func clearPending() {
        guard pending != nil else { return }
        pending = nil
        pendingPayload = nil
        pendingDestination = nil
        revision += 1
    }

    // MARK: Leaving

    /// Escape: cancels a pending confirmation first, then leaves the destination list. Returns false when there was
    /// nothing to leave, so the caller can close the panel.
    @discardableResult
    public func goBack() -> Bool {
        if pending != nil {
            clearPending()
            return true
        }
        if level != nil {
            level = nil
            levelPayload = nil
            rebuild()
            return true
        }
        return false
    }

    /// Drops a pending confirmation without leaving the destination list.
    public func goBackFromPending() { clearPending() }

    public var isInDestinationList: Bool { level != nil }
}
