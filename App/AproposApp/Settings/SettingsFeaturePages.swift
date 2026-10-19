import AppKit
import Apropos
import SwiftUI

/// A small rounded label: a trust state, a payload kind, a hotkey.
struct Badge: View {
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
struct EmptyRows: View {
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
    @State private var group: CommandGroup = .all
    @State private var detailed: UserCommand?

    private var store: UserCommandStore { controller.userCommands }

    private var visible: [UserCommand] {
        let inGroup = group == .all ? store.commands : store.commands.filter { CommandGroup.of($0) == group }
        let words = filter.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return inGroup }
        return inGroup.filter { command in
            let haystack = ([command.title, command.subtitle ?? ""] + command.aliases).joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    var body: some View {
        if store.commands.count > 4 { filterField }
        if presentGroups.count > 2 { groupChips }
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
                    command: command, store: store, usage: controller.usage.store,
                    onDetails: { detailed = command }, onDelete: { deleting = command }, onError: { message = $0 })
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
            .sheet(item: $detailed) { command in
                CommandDetailSheet(command: command, store: store, usage: controller.usage.store) { detailed = nil }
            }
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

    /// The groups that have at least one command, with All first.
    private var presentGroups: [CommandGroup] {
        [.all]
            + CommandGroup.allCases.filter { candidate in
                candidate != .all && store.commands.contains { CommandGroup.of($0) == candidate }
            }
    }

    private var groupChips: some View {
        HStack(spacing: 6) {
            ForEach(presentGroups) { item in
                let selected = group == item
                Button {
                    group = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? Brand.mintInk : Brand.text2)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(Capsule().fill(selected ? Brand.mint : Brand.raised))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
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
    let usage: UsageStore
    let onDetails: () -> Void
    let onDelete: () -> Void
    let onError: (String?) -> Void

    @State private var alias = ""

    var body: some View {
        SettingsRow(
            title: command.title,
            detail: command.isRunnable ? detailLine : "Needs approval before it can run",
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
                    Button("Review", action: onDetails)
                        .buttonStyle(SecondaryButtonStyle())
                }
                Menu {
                    Button("Details") { onDetails() }
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onDetails)
        .onAppear { alias = command.aliases.first ?? "" }
    }

    /// What it does, then how it has been used: "Runs a script, used 14 times, last 2 days ago".
    private var detailLine: String {
        let id = CommandID(rawValue: command.id.rawValue)
        var parts = [command.subtitle ?? CommandGroup.of(command).blurb]
        let runs = usage.runCount(id)
        if runs > 0 {
            parts.append("used \(runs) time\(runs == 1 ? "" : "s")")
            if let last = usage.lastRun(id) {
                parts.append("last " + last.formatted(.relative(presentation: .named, unitsStyle: .wide)))
            }
        } else {
            parts.append("not used yet")
        }
        return parts.joined(separator: ", ")
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

/// The kinds of command, for the filter chips and the row summary.
private enum CommandGroup: String, CaseIterable, Identifiable {
    case all, sequences, scripts, links, shortcuts, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .sequences: "Sequences"
        case .scripts: "Scripts"
        case .links: "Links"
        case .shortcuts: "Shortcuts"
        case .other: "Other"
        }
    }

    var blurb: String {
        switch self {
        case .all, .other: "A command"
        case .sequences: "Runs several steps"
        case .scripts: "Runs a script"
        case .links: "Opens a link"
        case .shortcuts: "Runs a Shortcut"
        }
    }

    static func of(_ command: UserCommand) -> CommandGroup {
        switch command.backend {
        case .sequence: .sequences
        case .shell, .appleScript: .scripts
        case .urlScheme: .links
        case .shortcut: .shortcuts
        case .function, .keyPress, .uiSteps: .other
        }
    }
}

/// Everything about one command in plain words, and the place to approve one that waits.
private struct CommandDetailSheet: View {
    let command: UserCommand
    let store: UserCommandStore
    let usage: UsageStore
    let onClose: () -> Void

    @State private var read = false
    @State private var asks: Bool
    @State private var problem: String?

    init(command: UserCommand, store: UserCommandStore, usage: UsageStore, onClose: @escaping () -> Void) {
        self.command = command
        self.store = store
        self.usage = usage
        self.onClose = onClose
        _asks = State(initialValue: command.needsConfirmation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: command.symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Brand.text2)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Brand.raised))
                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(Brand.text)
                    Text(command.isRunnable ? "Ready to use" : "Waiting for your approval")
                        .font(.system(size: 12.5))
                        .foregroundStyle(command.isRunnable ? Brand.mint : Brand.danger)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("What it does").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.text3)
                ScrollView {
                    Text(CommandSummary.lines(for: command).joined(separator: "\n"))
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Brand.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 170)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.raised))
            }
            let risks = CommandSummary.risks(for: command)
            if !risks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What it can do to your Mac").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.text3)
                    ForEach(risks, id: \.self) { risk in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(risk.needsApproval ? Brand.danger : Brand.text3).frame(width: 5, height: 5)
                            Text(risk.warning).font(.system(size: 12.5)).foregroundStyle(Brand.text2)
                        }
                    }
                }
            }
            HStack {
                Text("Ask before it runs").font(.system(size: 13)).foregroundStyle(Brand.text)
                Spacer()
                AproposToggle(title: "Ask before it runs", isOn: $asks)
                    .onChange(of: asks) { _, value in
                        var edited = command
                        edited.needsConfirmation = value
                        do { _ = try store.update(edited) } catch { problem = "\(error)" }
                    }
            }
            if !command.isRunnable {
                Toggle("I have read what it does and want it to run", isOn: $read)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12.5))
            }
            if let problem { Text(problem).font(.system(size: 12.5)).foregroundStyle(Brand.danger) }
            HStack {
                Spacer()
                if !command.isRunnable {
                    Button("Approve") {
                        do {
                            _ = try store.approve(command.id)
                            onClose()
                        } catch {
                            problem = "\(error)"
                        }
                    }
                    .buttonStyle(BrandButtonStyle(kind: .primary))
                    .disabled(!read)
                    .opacity(read ? 1 : 0.5)
                }
                Button("Done", action: onClose).buttonStyle(BrandButtonStyle(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(26)
        .frame(width: 500)
        .tint(Brand.mint)
    }
}

// MARK: Destinations

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
