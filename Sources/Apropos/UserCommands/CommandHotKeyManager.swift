import Foundation

/// One system-wide shortcut as the manager sees it: register a combination, or let it go. `GlobalHotKey` is the real one.
@MainActor
public protocol HotKeyBinding: AnyObject {
    @discardableResult func register(_ combo: HotKeyCombo) -> Bool
    func unregister()
}

extension GlobalHotKey: HotKeyBinding {}

public enum HotKeyFailure: Sendable, Equatable {
    /// macOS refused the combination, usually because another app owns it.
    case refusedBySystem
    /// The same combination as the panel's shortcut.
    case panel
    /// Another command with the same combination was registered first.
    case duplicate
}

/// Keeps one global shortcut registered for each approved command that has one, and no others. Call `sync` whenever
/// the commands change: shortcuts of deleted, edited, pending or no longer valid commands are released at once, so a
/// freed key goes back to the system and to other apps.
@MainActor
public final class CommandHotKeyManager {
    private struct Entry {
        let combo: HotKeyCombo
        let binding: any HotKeyBinding
    }

    /// Commands whose shortcut could not be registered, and why. Show it next to the shortcut field.
    public private(set) var failures: [ActionID: HotKeyFailure] = [:]

    private let makeBinding: @MainActor (@escaping @MainActor () -> Void) -> any HotKeyBinding
    private var entries: [ActionID: Entry] = [:]
    private var paused = false
    private var lastCommands: [UserCommand] = []
    private var lastReserved: [HotKeyCombo] = []
    private var trigger: (@MainActor (UserCommand) -> Void)?

    public init(
        makeBinding: @escaping @MainActor (@escaping @MainActor () -> Void) -> any HotKeyBinding = {
            GlobalHotKey(handler: $0)
        }
    ) {
        self.makeBinding = makeBinding
    }

    /// The ids that currently hold a shortcut.
    public var registeredIDs: Set<ActionID> { Set(entries.keys) }

    /// - Parameters:
    ///   - commands: All stored commands; only approved ones with a shortcut are registered.
    ///   - reserved: Combinations that are not available, such as the panel's.
    ///   - run: Called on the main actor when a shortcut is pressed, with the command as it is stored now.
    public func sync(
        _ commands: [UserCommand], reserved: [HotKeyCombo], run: @escaping @MainActor (UserCommand) -> Void
    ) {
        lastCommands = commands
        lastReserved = reserved
        trigger = run
        apply()
    }

    /// Releases every shortcut while the person is recording one, so the combination being chosen does not fire.
    public func setPaused(_ paused: Bool) {
        guard self.paused != paused else { return }
        self.paused = paused
        apply()
    }

    public func unregisterAll() {
        for entry in entries.values { entry.binding.unregister() }
        entries = [:]
        failures = [:]
    }

    private func apply() {
        let wanted: [UserCommand] = paused ? [] : lastCommands.filter { $0.isRunnable && $0.hotkey != nil }
        let wantedByID = Dictionary(wanted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for (id, entry) in entries where wantedByID[id]?.hotkey != entry.combo || lastReserved.contains(entry.combo) {
            entry.binding.unregister()
            entries[id] = nil
        }
        failures = failures.filter { wantedByID[$0.key] != nil }

        var taken = Set(entries.values.map(\.combo))
        for command in wanted.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            guard let combo = command.hotkey, entries[command.id] == nil else { continue }
            if lastReserved.contains(combo) {
                failures[command.id] = .panel
                continue
            }
            if taken.contains(combo) {
                failures[command.id] = .duplicate
                continue
            }
            let id = command.id
            let binding = makeBinding { [weak self] in self?.fire(id) }
            guard binding.register(combo) else {
                failures[command.id] = .refusedBySystem
                continue
            }
            entries[command.id] = Entry(combo: combo, binding: binding)
            taken.insert(combo)
            failures[command.id] = nil
        }
    }

    private func fire(_ id: ActionID) {
        guard let command = lastCommands.first(where: { $0.id == id }), command.isRunnable else { return }
        trigger?(command)
    }
}
