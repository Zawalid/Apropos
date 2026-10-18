import Foundation
import Observation

/// What the palette can show for the target app.
public enum MenuState: Sendable {
    case needsPermission
    case noApp
    case loading
    case loaded([Command])
    case empty
    case failed(String)
}

/// Loads the target app's menu commands, keeps the last result per app so reopening is instant, and refreshes when the
/// app, its menus or Accessibility access change.
@MainActor
@Observable
public final class AppMenuModel {
    public private(set) var state: MenuState = .noApp
    /// Commands currently on offer, whichever state they came from (a refresh keeps the old list visible).
    public private(set) var commands: [Command] = [] {
        didSet { revision += 1 }
    }
    /// Moves every time `commands` is replaced; lets dependants cache work per list.
    public private(set) var revision = 0

    /// Whether Option-key alternates (Empty Trash Securely) get rows of their own. Mirror
    /// `SettingsStore.bool(.showAlternateCommands)` here; changing it re-reads the menus.
    public var showAlternates = false {
        didSet {
            guard showAlternates != oldValue else { return }
            cache = [:]
            refresh()
        }
    }

    @ObservationIgnored private let tracker: FrontmostAppTracker
    @ObservationIgnored private let permission: AccessibilityPermission
    @ObservationIgnored private let reader: AXMenuReader
    @ObservationIgnored private var cache: [pid_t: [Command]] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var isSeeded = false

    public init(
        tracker: FrontmostAppTracker, permission: AccessibilityPermission, reader: AXMenuReader = AXMenuReader()
    ) {
        self.tracker = tracker
        self.permission = permission
        self.reader = reader
        observe()
        refresh()
    }

    /// Re-reads the target's menus. The previous list stays on screen until the new one arrives.
    public func refresh() {
        guard !isSeeded else { return }
        loadTask?.cancel()
        generation += 1
        let current = generation

        guard permission.isTrusted else {
            commands = []
            state = .needsPermission
            return
        }
        guard let app = tracker.app else {
            commands = []
            state = .noApp
            return
        }
        if let cached = cache[app.pid] {
            commands = cached
            state = cached.isEmpty ? .empty : .loaded(cached)
        } else {
            commands = []
            state = .loading
        }

        let reader = self.reader
        let pid = app.pid
        let bundleID = app.bundleID
        let showAlternates = self.showAlternates
        loadTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<[Command], MenuReadError> in
                do {
                    let bar = try reader.readMenuBar(pid: pid)
                    return .success(MenuCommandMapper.commands(from: bar, bundleID: bundleID, showAlternates: showAlternates))
                } catch let error as MenuReadError {
                    return .failure(error)
                } catch {
                    return .failure(.failed(-1))
                }
            }.value
            guard let self, !Task.isCancelled, self.generation == current else { return }
            self.apply(outcome, pid: pid)
        }
    }

    private func apply(_ outcome: Result<[Command], MenuReadError>, pid: pid_t) {
        switch outcome {
        case .success(let list):
            cache[pid] = list
            commands = list
            state = list.isEmpty ? .empty : .loaded(list)
        case .failure(.notTrusted):
            commands = []
            state = .needsPermission
        case .failure(.noMenuBar):
            cache[pid] = []
            commands = []
            state = .empty
        case .failure(let error):
            // Keep showing the old list if there is one; only show the error when there is nothing else.
            if commands.isEmpty { state = .failed(error.message) }
        }
    }

    /// Replaces the commands directly, for previews and tests that have no live app to read.
    public func seed(_ list: [Command]) {
        generation += 1
        loadTask?.cancel()
        isSeeded = true
        commands = list
        state = list.isEmpty ? .empty : .loaded(list)
    }

    /// Runs a command's action off the main thread and reports the outcome.
    public func run(_ command: Command) async -> Result<Void, CommandRunError> {
        guard command.isEnabled else { return .failure(.disabled) }
        guard let target = command.target else { return .failure(.unavailable) }
        return await Task.detached(priority: .userInitiated) {
            do {
                try target.perform()
                return Result<Void, CommandRunError>.success(())
            } catch let error as CommandRunError {
                return .failure(error)
            } catch {
                return .failure(.failed(-1))
            }
        }.value
    }

    private func observe() {
        withObservationTracking {
            _ = tracker.app
            _ = tracker.menuChangeCount
            _ = permission.isTrusted
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.permission.isTrusted { self.tracker.reattach() }
                self.refresh()
                self.observe()
            }
        }
    }
}
