import Foundation
import Observation

/// Turns the latest context snapshot into palette commands and runs them. One instance per app.
///
/// Flow: the context service finishes a snapshot (off the main thread) and calls `update(with:)`; the center filters
/// the action library down to what applies, builds commands, and hands them to the palette, which lists them under
/// their groups (Selected text, Selected files, This page, This folder). Running one goes through `ActionEngine`
/// off the main thread. Nothing here is read until the snapshot arrives, so the panel never waits on it.
@MainActor
@Observable
public final class ContextActionCenter {
    public private(set) var commands: [Command] = []
    public private(set) var library: ActionPackLibrary

    @ObservationIgnored private let engine: ActionEngine
    @ObservationIgnored private var values = ContextValues()
    @ObservationIgnored private var capturedAt = Date.distantPast
    @ObservationIgnored private var snapshotPID: pid_t?
    @ObservationIgnored private var lastBundleID: String?
    @ObservationIgnored private var byCommandID: [String: ContextAction] = [:]
    @ObservationIgnored private var userCommands: [UserCommand] = []
    @ObservationIgnored private var onChange: (([Command], pid_t?) -> Void)?

    public init(library: ActionPackLibrary = .bundled(), engine: ActionEngine? = nil) {
        self.library = library
        self.engine = engine ?? ActionEngine(functions: library.functions)
    }

    /// Replaces the action library, for example after the person edited their pack folder.
    public func reload(_ library: ActionPackLibrary) {
        self.library = library
        rebuild()
    }

    /// Receives the commands and the pid of the app they were built for each time they change.
    public func observe(_ handler: @escaping ([Command], pid_t?) -> Void) {
        onChange = handler
        handler(commands, snapshotPID)
    }

    /// Takes a fresh snapshot. A snapshot older than the one already used is ignored, so a slow read that finishes late
    /// cannot bring back actions for context that is gone.
    public func update(with snapshot: ContextSnapshot) {
        guard snapshot.capturedAt >= capturedAt else { return }
        capturedAt = snapshot.capturedAt
        values = snapshot.values
        snapshotPID = snapshot.pid
        lastBundleID = snapshot.bundleID
        rebuild()
    }

    /// Forgets the context: sensing was turned off or the panel closed.
    public func clear() {
        capturedAt = Date.distantPast
        values = ContextValues()
        snapshotPID = nil
        rebuild()
    }

    /// The person's own commands. Pending (not yet approved) ones are ignored. They are listed under "Your commands",
    /// ahead of the built-in actions, and the ones that need no context are listed even before a snapshot arrives.
    /// Called after a run the person confirmed went through, with the action's id.
    public var onConfirmedRun: (@MainActor (ActionID) -> Void)?

    public func setUserCommands(_ commands: [UserCommand]) {
        userCommands = commands.filter(\.isRunnable)
        rebuild()
    }

    /// The panel opened for `app`: forget the last snapshot (its selection may be gone) and list what needs no context.
    /// The fresh snapshot adds the rest when it lands.
    public func beginSession(for app: TargetApp?) {
        capturedAt = Date.distantPast
        values = ContextValues()
        snapshotPID = app?.pid
        lastBundleID = app?.bundleID
        rebuild()
    }

    private func rebuild() {
        let mine = userCommands.filter { $0.action.applies(to: values, bundleID: lastBundleID) }
        // Your own commands that cannot run right now are still listed, dimmed, with what they are waiting for, so a
        // command you made can always be found by name. The panel shows them only while searching.
        let waiting = userCommands.filter { command in
            !mine.contains { $0.id == command.id } && command.action.apps.allows(lastBundleID)
        }
        let applicable = library.applicable(to: values, bundleID: lastBundleID)
        var pairs: [(ContextAction, [String])] = mine.map { ($0.action, $0.aliases) }
        pairs += applicable.map { ($0, []) }
        byCommandID = Dictionary(pairs.map { ($0.0.id.rawValue, $0.0) }, uniquingKeysWith: { first, _ in first })
        commands = pairs.map { action, aliases in
            var command = Self.command(for: action)
            command.aliases = aliases
            return command
        }
        for command in waiting {
            var row = Self.command(for: command.action, isEnabled: false)
            row.aliases = command.aliases
            row.detail = Self.waitingNote(for: command.action, values: values)
            commands.append(row)
        }
        onChange?(commands, snapshotPID)
    }

    /// "Needs selected files": what a command that cannot run now is waiting for.
    static func waitingNote(for action: ContextAction, values: ContextValues) -> String {
        let missing = ContextRequirement.allCases.filter { action.requires.contains($0) && !values.has($0) }
        let words = missing.map { requirement -> String in
            switch requirement {
            case .selectedText: "selected text"
            case .selectedFiles: "selected files"
            case .pageURL: "a web page"
            case .folder: "an open folder"
            case .gitRepo: "a git repository"
            case .document: "an open document"
            }
        }
        return words.isEmpty ? "Not available here" : "Needs " + words.joined(separator: " and ")
    }

    static func command(for action: ContextAction, isEnabled: Bool = true) -> Command {
        var command = Command(
            id: action.id.rawValue, title: action.title, path: [action.group.title], isEnabled: isEnabled,
            source: .contextAction(action.id))
        command.symbolName = action.symbol
        command.keywords = action.keywords
        command.detail = action.subtitle
        command.needsConfirmation = action.needsConfirmation
        return command
    }

    /// Runs a command made by this center, on the values of the snapshot it was made from. Returns the engine's result;
    /// the UI shows `outcome.notice` or the error message. Pass `confirmed: true` after asking about destructive ones.
    public func run(
        _ command: Command, target: TargetApp?, confirmed: Bool = false
    ) async -> Result<ActionOutcome, ActionError> {
        guard let action = byCommandID[command.id] else { return .failure(.notApplicable) }
        // A command the person already confirmed once, and did not set to ask every time, goes through its own inner
        // question (a sequence's list of things it will do) as answered.
        let answeredBefore = userCommands.contains { $0.id == action.id && $0.panelConfirmed && !$0.asksEveryTime }
        let result = await engine.run(action, values: values, target: target, confirmed: confirmed || answeredBefore)
        // A command that asks only the first time is remembered as confirmed once a confirmed run went through.
        if confirmed, command.needsConfirmation, case .success = result { onConfirmedRun?(action.id) }
        return result
    }

    /// Runs a user command without the panel: from its global shortcut, a URL or Shortcuts. Context comes from `values`
    /// (callers decide where it came from). A failure is shown as a short notification, since nothing else is on screen.
    /// Pending commands never run.
    @discardableResult
    public func run(
        _ command: UserCommand, values: ContextValues, target: TargetApp?, confirmed: Bool = false
    ) async -> Result<ActionOutcome, ActionError> {
        guard command.isRunnable else { return .failure(.notApplicable) }
        let result = await engine.run(command.action, values: values, target: target, confirmed: confirmed)
        if case .failure(let error) = result, error != .confirmationRequired {
            await engine.services.notify(error.message)
        }
        return result
    }

    /// Runs a user command on the context of `target`, read now. Used by global shortcuts, which fire with no panel
    /// open. `confirm` is asked for commands that need confirmation; without it they do not run.
    @discardableResult
    public func runWithLiveContext(
        _ command: UserCommand, target: TargetApp?, sensing: ContextService,
        confirm: (@MainActor (UserCommand) async -> Bool)? = nil
    ) async -> Result<ActionOutcome, ActionError> {
        var service = sensing
        service.onSnapshot = nil
        var values = ContextValues()
        if !command.requires.isEmpty, let target { values = await service.snapshot(for: target).values }
        var confirmed = false
        if command.needsConfirmation {
            guard let confirm, await confirm(command) else { return .failure(.confirmationRequired) }
            confirmed = true
        }
        return await run(command, values: values, target: target, confirmed: confirmed)
    }

    /// Connects the center to the palette: commands flow in, and running a context action goes through `run`.
    public func attach(to palette: PaletteModel) {
        observe { [weak palette] commands, pid in palette?.setContextCommands(commands, forPID: pid) }
        palette.setOpenHook { [weak self] app in self?.beginSession(for: app) }
        palette.setContextRunner { [weak self] command, target, confirmed in
            guard let self else { return .failure(.notApplicable) }
            return await self.run(command, target: target, confirmed: confirmed)
        }
    }
}
