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

/// Your own commands and sequences: what they are called, their key, and whether they may run yet.
struct CommandsPage: View {
    let controller: AppController

    @State private var message: String?
    @State private var deleting: UserCommand?

    private var store: UserCommandStore { controller.userCommands }

    var body: some View {
        SettingsSection(
            title: "Your commands",
            footer: "Commands are plain files, so you can edit, copy and share them. Imported ones wait here until you approve them."
        ) {
            if store.commands.isEmpty {
                EmptyRows(
                    title: "No commands yet",
                    detail: "Create one in the palette, or drop a command file into the commands folder.")
            }
            ForEach(store.commands) { command in
                SettingsRow(
                    title: command.title,
                    detail: command.subtitle,
                    leading: AnyView(
                        Image(systemName: command.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(Brand.text2)
                            .frame(width: 22))
                ) {
                    HStack(spacing: 8) {
                        if let hotkey = command.hotkey { Badge(text: hotkey.display) }
                        if !command.isRunnable {
                            Badge(text: "Needs approval", tone: .warning)
                            Button("Approve") { approve(command) }
                                .buttonStyle(SecondaryButtonStyle())
                        } else if command.runsScripts {
                            Badge(text: "Runs a script")
                        }
                        Menu {
                            Button("Duplicate") { duplicate(command) }
                            Button("Delete", role: .destructive) { deleting = command }
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
            }
        }
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
        }
        if let message {
            Text(message).font(.system(size: 12)).foregroundStyle(Brand.danger)
        }
        Color.clear.frame(height: 0)
            .confirmationDialog(
                "Delete \(deleting?.title ?? "this command")?", isPresented: Binding(
                    get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let deleting { run { try store.delete(deleting.id) } }
                    deleting = nil
                }
            } message: {
                Text("The file is kept in the command's history, so you can bring it back from the folder.")
            }
    }

    private func approve(_ command: UserCommand) { run { _ = try store.approve(command.id) } }
    private func duplicate(_ command: UserCommand) { run { _ = try store.duplicate(command.id) } }

    private func run(_ work: () throws -> Void) {
        do {
            try work()
            message = nil
        } catch {
            message = "That did not work: \(error)"
        }
    }

    private func reveal() {
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([store.directory])
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
