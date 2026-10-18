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

    private func rebuild() {
        let applicable = library.applicable(to: values, bundleID: lastBundleID)
        byCommandID = Dictionary(uniqueKeysWithValues: applicable.map { ($0.id.rawValue, $0) })
        commands = applicable.map(Self.command(for:))
        onChange?(commands, snapshotPID)
    }

    static func command(for action: ContextAction) -> Command {
        var command = Command(
            id: action.id.rawValue, title: action.title, path: [action.group.title], source: .contextAction(action.id))
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
        return await engine.run(action, values: values, target: target, confirmed: confirmed)
    }

    /// Connects the center to the palette: commands flow in, and running a context action goes through `run`.
    public func attach(to palette: PaletteModel) {
        observe { [weak palette] commands, pid in palette?.setContextCommands(commands, forPID: pid) }
        palette.setContextRunner { [weak self] command, target, confirmed in
            guard let self else { return .failure(.notApplicable) }
            return await self.run(command, target: target, confirmed: confirmed)
        }
    }
}
