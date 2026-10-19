import Apropos
import SwiftUI

/// Every key Apropos uses, in one place: the one that opens the panel, the ones you gave your commands, and the keys the
/// panel itself answers to. Click a shortcut to record a new one.
struct ShortcutsPage: View {
    let controller: AppController

    @State private var message: String?
    @State private var tick = 0

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
