import AppKit
import Apropos
import SwiftUI

/// A small rounded label: a trust state, a payload kind, a hotkey.
private struct Badge: View {
    let text: String
    var tone: Tone = .quiet

    enum Tone { case quiet, mint, warning }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(background))
    }

    private var foreground: Color {
        switch tone {
        case .quiet: Brand.text2
        case .mint: Brand.mint
        case .warning: Brand.danger
        }
    }

    private var background: Color {
        switch tone {
        case .quiet: Brand.raised
        case .mint: Brand.mint.opacity(0.14)
        case .warning: Brand.danger.opacity(0.14)
        }
    }
}

/// A short empty state: one plain sentence and, optionally, the next step.
private struct EmptyRows: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Brand.text)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Brand.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
    }
}

// MARK: Commands

/// Your own commands and sequences, as a table: name, alias, shortcut, and whether each may run yet.
struct CommandsPage: View {
    let controller: AppController

    @State private var message: String?
    @State private var deleting: UserCommand?
    @State private var filter = ""
    @State private var creating = false

    private var store: UserCommandStore { controller.userCommands }

    private var visible: [UserCommand] {
        let words = filter.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return store.commands }
        return store.commands.filter { command in
            let haystack = ([command.title, command.subtitle ?? ""] + command.aliases).joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    var body: some View {
        if store.commands.count > 4 { filterField }
        SettingsSection(
            title: "Your commands",
            footer:
                "An alias is a short word that finds the command in the panel or runs it from a link. Commands are plain files, so you can edit, copy and share them.",
            accessory: AnyView(
                Button {
                    creating = true
                } label: {
                    Label("New command", systemImage: "plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Brand.mintInk)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Brand.mint))
                }
                .buttonStyle(.plain))
        ) {
            if store.commands.isEmpty {
                CommandsIntro()
            } else if visible.isEmpty {
                EmptyRows(title: "No match", detail: "Nothing named \"\(filter)\".")
            }
            ForEach(visible) { command in
                CommandRowView(
                    command: command, store: store, onDelete: { deleting = command }, onError: { message = $0 })
            }
        }
        examples
        if !store.issues.isEmpty {
            SettingsSection(title: "Files that could not be read") {
                ForEach(store.issues, id: \.fileName) { issue in
                    SettingsRow(title: issue.fileName, detail: issue.reason) { EmptyView() }
                }
            }
        }
        SettingsSection {
            SettingsRow(title: "Commands folder", detail: "Where the files live.") {
                Button("Reveal in Finder") { reveal() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            SettingsRow(title: "Import and export", detail: "Share commands as a single file.") {
                HStack(spacing: 8) {
                    Button("Import") { CommandManagement.importCommands(store) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Export") { CommandManagement.exportCommands(store) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        if let message {
            Text(message).font(.system(size: 12)).foregroundStyle(Brand.danger)
        }
        Color.clear.frame(height: 0)
            .sheet(isPresented: $creating) {
                NewCommandSheet(store: store) { creating = false }
            }
            .confirmationDialog(
                "Delete \(deleting?.title ?? "this command")?", isPresented: Binding(
                    get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let deleting {
                        do {
                            try store.delete(deleting.id)
                            message = nil
                        } catch {
                            message = "That did not work: \(error)"
                        }
                    }
                    deleting = nil
                }
            } message: {
                Text("The file is kept in the command's history, so you can bring it back from the folder.")
            }
    }

    /// Ready-made commands to start from, minus the ones already added.
    @ViewBuilder
    private var examples: some View {
        let remaining = CommandTemplate.all.filter { template in !store.commands.contains { $0.title == template.title } }
        if !remaining.isEmpty {
            SettingsSection(
                title: store.commands.isEmpty ? "Start with an example" : "Examples",
                footer: "Each is harmless. Add one, then try it from the panel."
            ) {
                ForEach(remaining) { template in
                    SettingsRow(
                        title: template.title, detail: template.summary,
                        leading: AnyView(
                            Image(systemName: template.symbol)
                                .font(.system(size: 14))
                                .foregroundStyle(Brand.text2)
                                .frame(width: 22))
                    ) {
                        Button("Add") {
                            do {
                                _ = try store.create(template.command())
                                message = nil
                            } catch {
                                message = "That did not work: \(error)"
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private var filterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.text3)
            TextField("Filter commands", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(Brand.section))
    }

    private func reveal() {
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([store.directory])
    }
}

/// What a command is, for someone who has never made one: a sentence and a picture of the result.
private struct CommandsIntro: View {
    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Your own actions, in the panel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.text)
                Text(
                    "A command is something you teach Apropos once: open a folder in Terminal, search the web for what you selected, run a Shortcut. It then shows up as a row in the panel, and can have its own shortcut and a short alias."
                )
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(Brand.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Image(systemName: "terminal").font(.system(size: 14)).foregroundStyle(Theme.text2).frame(width: 22)
                Text("Open in Terminal here").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text("Your commands").font(.system(size: 12)).foregroundStyle(Theme.text3).lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(["\u{2303}", "\u{2325}", "T"], id: \.self) { KeyCap(text: $0) }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Capsule().fill(Theme.highlight))
            .frame(maxWidth: 440)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 28)
    }
}

/// One command: icon, name, an alias to edit, a shortcut to record, and a menu.
private struct CommandRowView: View {
    let command: UserCommand
    let store: UserCommandStore
    let onDelete: () -> Void
    let onError: (String?) -> Void

    @State private var alias = ""

    var body: some View {
        SettingsRow(
            title: command.title,
            detail: command.isRunnable
                ? (command.subtitle ?? (command.runsScripts ? "Runs a script" : nil)) : "Needs approval before it can run",
            leading: AnyView(
                Image(systemName: command.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Brand.text2)
                    .frame(width: 22))
        ) {
            HStack(spacing: 8) {
                if command.isRunnable {
                    aliasField
                    ShortcutRecorder(
                        combo: command.hotkey, placeholder: "Add shortcut", minWidth: 100,
                        onRecordingChange: { _ in }, onChange: setHotkey, onClear: { setHotkey(nil) })
                } else {
                    Button("Approve") { run { _ = try store.approve(command.id) } }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Menu {
                    Button("Duplicate") { run { _ = try store.duplicate(command.id) } }
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Brand.text2)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More for \(command.title)")
            }
        }
        .onAppear { alias = command.aliases.first ?? "" }
    }

    private var aliasField: some View {
        TextField("Alias", text: $alias)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .multilineTextAlignment(.center)
            .frame(width: 76, height: 30)
            .background(Capsule().fill(Brand.raised))
            .onSubmit(commitAlias)
            .accessibilityLabel("Alias for \(command.title)")
    }

    private func commitAlias() {
        let cleaned = alias.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
        alias = cleaned
        guard cleaned != (command.aliases.first ?? "") else { return }
        var edited = command
        edited.aliases = cleaned.isEmpty ? [] : [cleaned]
        run { _ = try store.update(edited) }
    }

    private func setHotkey(_ combo: HotKeyCombo?) {
        if let combo, let conflict = store.hotkeyConflict(combo, excluding: command.id) {
            switch conflict {
            case .panel: onError("That shortcut opens Apropos.")
            case .command(let title): onError("That shortcut already runs \(title).")
            }
            return
        }
        var edited = command
        edited.hotkey = combo
        run { _ = try store.update(edited) }
    }

    private func run(_ work: () throws -> Void) {
        do {
            try work()
            onError(nil)
        } catch {
            onError("That did not work: \(error)")
        }
    }
}

// MARK: Destinations

/// Where Send to can put what you have selected.
struct DestinationsPage: View {
    let controller: AppController

    @State private var destinations: [Destination] = []

    var body: some View {
        SettingsSection(
            title: "Send to",
            footer: "Destinations that leave this Mac ask you to confirm once more. Your own live in the destinations folder."
        ) {
            if destinations.isEmpty {
                EmptyRows(title: "No destinations", detail: "Add a destination file to the destinations folder.")
            }
            ForEach(destinations) { destination in
                SettingsRow(
                    title: destination.title,
                    detail: destination.subtitle,
                    leading: AnyView(
                        Image(systemName: destination.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(Brand.text2)
                            .frame(width: 22))
                ) {
                    HStack(spacing: 6) {
                        if !destination.isRunnable {
                            Badge(text: "Needs approval", tone: .warning)
                        } else if destination.confirmation == .preview {
                            Badge(text: "Asks first")
                        }
                        if destination.origin == .user { Badge(text: "Yours", tone: .mint) }
                        ForEach(destination.accepts.sorted { $0.rawValue < $1.rawValue }, id: \.self) { kind in
                            Badge(text: kind.rawValue.capitalized)
                        }
                    }
                }
            }
        }
        SettingsSection {
            SettingsRow(title: "Destinations folder", detail: "Add a file here to add a destination.") {
                Button("Reveal in Finder") {
                    let folder = DestinationLibrary.userDirectory
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        Color.clear.frame(height: 0).onAppear { destinations = controller.send.library.destinations }
    }
}

// MARK: Prediction

/// What Apropos learns, and how to make it forget.
struct PredictionPage: View {
    let controller: AppController
    let settings: SettingsModel

    @State private var confirmingReset = false

    var body: some View {
        SettingsSection(
            footer: "Learned on this Mac from command names and times only. Nothing you type or select is kept."
        ) {
            SettingToggleRow(
                id: .predictNextCommand,
                isOn: Binding(
                    get: { settings.predictNextCommand },
                    set: {
                        settings.predictNextCommand = $0
                        controller.usage.prediction.configure(from: settings.store)
                    }))
            SettingToggleRow(
                id: .showPredictionReasons,
                isOn: Binding(
                    get: { settings.showPredictionReasons },
                    set: {
                        settings.showPredictionReasons = $0
                        controller.usage.prediction.configure(from: settings.store)
                    })
            )
            .opacity(settings.predictNextCommand ? 1 : 0.5)
            .disabled(!settings.predictNextCommand)
        }
        SettingsSection(title: "Learned data") {
            SettingsRow(title: "Forget what it learned", detail: "Clears the log of runs and starts over.") {
                Button("Forget") { confirmingReset = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .confirmationDialog(
            "Forget everything Apropos learned about what you run next?", isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Forget", role: .destructive) { controller.usage.prediction.reset() }
        }
    }
}

// MARK: Integrations

/// How other things reach Apropos: its web-style links.
struct IntegrationsPage: View {
    let controller: AppController

    @State private var message: String?

    private var store: UserCommandStore { controller.userCommands }

    var body: some View {
        SettingsSection(
            title: "Links",
            footer:
                "A link such as apropos://run?command=my-alias runs a command from a script, Shortcuts or another app. A command only answers links once you allow it here, and asks you the first time."
        ) {
            if store.runnable.isEmpty {
                EmptyRows(
                    title: "No commands to allow",
                    detail: "Commands you create or approve appear here.")
            }
            ForEach(store.runnable) { command in
                SettingsRow(
                    title: command.title,
                    detail: command.aliases.first.map { "apropos://run?command=\($0)" }
                ) {
                    AproposToggle(
                        title: command.title,
                        isOn: Binding(
                            get: { command.allowFromURL },
                            set: { allowed in
                                do {
                                    try store.setAllowFromURL(allowed, for: command.id)
                                    message = nil
                                } catch {
                                    message = "That did not work: \(error)"
                                }
                            }))
                }
            }
        }
        if let message {
            Text(message).font(.system(size: 12)).foregroundStyle(Brand.danger)
        }
        SettingsSection(title: "Shortcuts") {
            SettingsRow(
                title: "Shortcuts and Spotlight",
                detail: "Apropos offers actions to the Shortcuts app, so you can run it from there.")
            {
                Button("Open Shortcuts") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
