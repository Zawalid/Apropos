import Apropos
import SwiftUI

/// Every key Apropos uses, in one place: the one that opens the panel, the ones you gave your commands, and the keys the
/// panel itself answers to. Click a shortcut to record a new one.
struct ShortcutsPage: View {
    let controller: AppController

    @State private var message: String?
    @State private var tick = 0
    @State private var focusedItem: String?
    @Environment(SettingsNavigation.self) private var navigation

    private var store: UserCommandStore { controller.userCommands }

    var body: some View {
        let _ = tick
        SettingsSection(
            title: "Open Apropos",
            footer: "Apropos runs alongside your launcher. Pick a shortcut it does not use."
        ) {
            SettingsRow(title: "Open the panel", detail: systemNote(controller.combo)) {
                HStack(spacing: 8) {
                    ShortcutRecorder(
                        combo: controller.combo, onRecordingChange: { controller.setRecording($0) },
                        onChange: { combo in
                            controller.setCombo(combo)
                            tick += 1
                        })
                    if !controller.isHotKeyRegistered { Badge(text: "macOS refused it", tone: .warning) }
                }
            }
        }
        SettingsSection(
            title: "Your commands",
            footer: "A shortcut runs the command on the app in front, from anywhere. Click a field and press the keys."
        ) {
            if store.runnable.isEmpty {
                EmptyRows(
                    title: "No commands yet", detail: "Make one on the Commands page, then give it a shortcut here.")
            }
            ForEach(store.runnable) { command in
                SettingsRow(
                    title: command.title, detail: detail(for: command),
                    leading: AnyView(
                        Image(systemName: command.symbol).font(.system(size: 14)).foregroundStyle(Brand.text2).frame(width: 22))
                ) {
                    HStack(spacing: 8) {
                        if let failure = controller.commandHotKeys.failures[command.id] {
                            Badge(text: label(failure), tone: .warning)
                        }
                        ShortcutRecorder(
                            combo: command.hotkey, placeholder: "Add shortcut", minWidth: 110,
                            onRecordingChange: { controller.setRecording($0) },
                            onChange: { set($0, for: command) }, onClear: { set(nil, for: command) })
                    }
                }
            }
        }
        menuItems
        if let message { Text(message).font(.system(size: 12)).foregroundStyle(Brand.danger) }
        SettingsSection(
            title: "Keys inside the panel",
            footer: "These are fixed for now. They work while the panel is open."
        ) {
            ForEach(Self.panelKeys, id: \.action) { entry in
                SettingsRow(title: entry.action) {
                    HStack(spacing: 4) { ForEach(entry.keys, id: \.self) { KeyCap(text: $0) } }
                }
            }
        }
    }

    // MARK: Menu items

    private var items: [MenuItemSetting] { controller.usage.store.itemSettings }

    private var menuItems: some View {
        SettingsSection(
            title: "Menu items",
            footer: "A shortcut runs the item in its app, and only when that app is in front. The same keys can serve items of different apps."
        ) {
            if items.isEmpty {
                EmptyRows(
                    title: "No menu items yet",
                    detail: "Open the panel in any app, highlight a menu item and press Command-K, then choose Alias and shortcut.")
            }
            ForEach(items) { item in
                MenuItemRow(
                    item: item, usage: controller.usage, controller: controller, isFocused: focusedItem == item.id.rawValue,
                    onError: { message = $0 })
            }
        }
        .onAppear(perform: takeIntent)
        .onChange(of: navigation.intentToken) { takeIntent() }
    }

    private func takeIntent() {
        guard case .customizeItem(let id)? = navigation.takeIntent() else { return }
        focusedItem = id
    }

    private static let panelKeys: [(action: String, keys: [String])] = [
        ("Run the highlighted row", ["\u{21A9}"]),
        ("Run the first Usually next row", ["\u{2318}", "\u{21A9}"]),
        ("Show the menu an item lives in", ["\u{21E7}", "\u{21A9}"]),
        ("Actions for the highlighted row", ["\u{2318}", "K"]),
        ("Open Settings", ["\u{2318}", ","]),
        ("First or last row", ["\u{2318}", "\u{2191}"]),
        ("Move a step in a sequence", ["\u{2325}", "\u{2191}"]),
        ("Go back or close", ["esc"]),
    ]

    private func detail(for command: UserCommand) -> String? {
        if let combo = command.hotkey, let note = systemNote(combo) { return note }
        return command.subtitle
    }

    private func systemNote(_ combo: HotKeyCombo) -> String? {
        SystemShortcuts.name(for: combo).map { "macOS normally uses this for \($0)." }
    }

    private func label(_ failure: HotKeyFailure) -> String {
        switch failure {
        case .refusedBySystem: "Taken by another app"
        case .panel: "Same as the panel"
        case .duplicate: "Used twice"
        }
    }

    private func set(_ combo: HotKeyCombo?, for command: UserCommand) {
        if let combo, let conflict = store.hotkeyConflict(combo, excluding: command.id) {
            switch conflict {
            case .panel: message = "That shortcut opens Apropos."
            case .command(let title): message = "That shortcut already runs \(title)."
            }
            return
        }
        var edited = command
        edited.hotkey = combo
        do {
            _ = try store.update(edited)
            message = nil
        } catch {
            message = "That did not work: \(error)"
        }
        tick += 1
    }
}

/// One menu item: its name and app, an alias to type, a shortcut to record, and a way to take it out of the list.
private struct MenuItemRow: View {
    let item: MenuItemSetting
    let usage: UsageController
    let controller: AppController
    let isFocused: Bool
    let onError: (String?) -> Void

    @State private var alias = ""
    @FocusState private var aliasFocus: Bool

    var body: some View {
        SettingsRow(title: item.label.title, detail: detail) {
            HStack(spacing: 8) {
                if let failure = controller.itemHotKeys.failures[item.id] {
                    Badge(text: Self.label(failure), tone: .warning)
                }
                TextField("Alias", text: $alias)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .multilineTextAlignment(.center)
                    .frame(width: 76, height: 30)
                    .background(Capsule().fill(Brand.raised))
                    .focused($aliasFocus)
                    .onSubmit(commitAlias)
                    .onChange(of: aliasFocus) { if !aliasFocus { commitAlias() } }
                    .accessibilityLabel("Alias for \(item.label.title)")
                ShortcutRecorder(
                    combo: item.hotkey, placeholder: "Add shortcut", minWidth: 110,
                    onRecordingChange: { controller.setRecording($0) }, onChange: setHotKey,
                    onClear: { setHotKey(nil) })
                Button {
                    usage.removeItemCustomization(item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Brand.text3)
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Take this item out of the list")
                .accessibilityLabel("Remove \(item.label.title)")
            }
        }
        .onAppear {
            alias = item.aliases.first ?? ""
            if isFocused { aliasFocus = true }
        }
        .onChange(of: isFocused) { if isFocused { aliasFocus = true } }
    }

    private var detail: String {
        if let combo = item.hotkey, let note = SystemShortcuts.name(for: combo) {
            return "\(item.label.appName). macOS normally uses these keys for \(note)."
        }
        return item.label.appName
    }

    private func commitAlias() {
        let cleaned = alias.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
        alias = cleaned
        guard cleaned != (item.aliases.first ?? "") else { return }
        usage.setItemAlias(cleaned, for: item.id)
    }

    private func setHotKey(_ combo: HotKeyCombo?) {
        if let combo {
            if let conflict = controller.userCommands.hotkeyConflict(combo, excluding: nil) {
                switch conflict {
                case .panel: onError("That shortcut opens Apropos.")
                case .command(let title): onError("That shortcut already runs \(title).")
                }
                return
            }
            if !usage.setItemHotKey(combo, for: item.id) {
                onError("Another item of \(item.label.appName) already uses that shortcut.")
                return
            }
        } else {
            usage.setItemHotKey(nil, for: item.id)
        }
        onError(nil)
    }

    private static func label(_ failure: HotKeyFailure) -> String {
        switch failure {
        case .refusedBySystem: "Taken by another app"
        case .panel: "Same as the panel"
        case .duplicate: "Same as a command"
        }
    }
}
