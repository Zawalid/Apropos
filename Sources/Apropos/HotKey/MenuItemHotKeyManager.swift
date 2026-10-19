import Foundation

/// Keeps one global shortcut registered for each combination that some menu item uses. A combination can belong to
/// items of several apps (Control-Option-N for New Folder in Finder and New Tab in Safari): pressing it runs the item
/// of the app in front, and does nothing when the app in front has none.
///
/// A system-wide key cannot be passed on to the app when it is not wanted, so a combination with no item for the
/// front app is swallowed. That is why Settings only takes combinations with a modifier and names the app next to the
/// shortcut.
@MainActor
public final class MenuItemHotKeyManager {
    private struct Entry {
        let binding: any HotKeyBinding
        var items: [CommandID]
    }

    /// Items whose combination could not be registered, and why.
    public private(set) var failures: [CommandID: HotKeyFailure] = [:]

    private let makeBinding: @MainActor (@escaping @MainActor () -> Void) -> any HotKeyBinding
    private var entries: [HotKeyCombo: Entry] = [:]
    private var paused = false
    private var last: (items: [(id: CommandID, combo: HotKeyCombo)], panel: [HotKeyCombo], commands: [HotKeyCombo])?
    private var trigger: (@MainActor ([CommandID]) -> Void)?

    public init(
        makeBinding: @escaping @MainActor (@escaping @MainActor () -> Void) -> any HotKeyBinding = {
            GlobalHotKey(handler: $0)
        }
    ) {
        self.makeBinding = makeBinding
    }

    /// The combinations currently registered.
    public var registeredCombos: Set<HotKeyCombo> { Set(entries.keys) }

    /// - Parameters:
    ///   - items: The menu items that have a shortcut.
    ///   - reservedForPanel: Combinations that open Apropos.
    ///   - reservedForCommands: Combinations of the person's own commands, which take them first.
    ///   - run: Called when a combination is pressed, with every item that uses it. The caller picks the one of the app
    ///     in front.
    public func sync(
        _ items: [(id: CommandID, combo: HotKeyCombo)], reservedForPanel: [HotKeyCombo],
        reservedForCommands: [HotKeyCombo], run: @escaping @MainActor ([CommandID]) -> Void
    ) {
        last = (items, reservedForPanel, reservedForCommands)
        trigger = run
        apply()
    }

    /// Releases every shortcut while one is being recorded, so the combination being chosen does not fire.
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
        guard let last else { return }
        let wanted = paused ? [] : last.items
        let byCombo = Dictionary(grouping: wanted, by: \.combo)

        for (combo, entry) in entries where byCombo[combo] == nil || last.panel.contains(combo)
            || last.commands.contains(combo)
        {
            entry.binding.unregister()
            entries[combo] = nil
        }
        failures = [:]

        for (combo, group) in byCombo.sorted(by: { $0.key.display < $1.key.display }) {
            let ids = group.map(\.id).sorted()
            if last.panel.contains(combo) {
                for id in ids { failures[id] = .panel }
                continue
            }
            if last.commands.contains(combo) {
                for id in ids { failures[id] = .duplicate }
                continue
            }
            if var existing = entries[combo] {
                existing.items = ids
                entries[combo] = existing
                continue
            }
            let binding = makeBinding { [weak self] in self?.fire(combo) }
            guard binding.register(combo) else {
                for id in ids { failures[id] = .refusedBySystem }
                continue
            }
            entries[combo] = Entry(binding: binding, items: ids)
        }
    }

    private func fire(_ combo: HotKeyCombo) {
        guard let items = entries[combo]?.items, !items.isEmpty else { return }
        trigger?(items)
    }
}
