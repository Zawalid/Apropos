import AppKit
import Apropos
import SwiftUI

/// How other things start Apropos: links, Raycast, Alfred, scripts and the Shortcuts app, and the rules around them.
struct IntegrationsPage: View {
    let controller: AppController
    let settings: SettingsModel

    @State private var tick = 0
    @State private var message: String?
    @State private var builderCommand = ""
    @State private var builderText = ""
    @State private var builderURL = ""
    @State private var copiedLink: String?

    private var store: UserCommandStore { controller.userCommands }
    private var allowed: [UserCommand] { store.runnable.filter(\.allowFromURL) }
    private var notAllowed: [UserCommand] { store.runnable.filter { !$0.allowFromURL } }

    var body: some View {
        @Bindable var settings = settings
        IntegrationsIntro()
        SettingsSection(
            footer: "Only commands you allow below can run from outside, and each asks you the first time. Nothing is shared with the caller."
        ) {
            SettingToggleRow(id: .externalControl, isOn: $settings.externalControl)
            SettingToggleRow(id: .externalAlwaysConfirm, isOn: $settings.externalAlwaysConfirm)
                .opacity(settings.externalControl ? 1 : 0.5)
                .disabled(!settings.externalControl)
        }
        Group {
            builtInLinks
            allowedSection
            if !notAllowed.isEmpty { notAllowedSection }
            builder
            recipes
            activity
            shortcuts
        }
        .opacity(settings.externalControl ? 1 : 0.5)
        if let message { Text(message).font(.system(size: 12)).foregroundStyle(Brand.danger) }
        Color.clear.frame(height: 0).id(tick)
    }

    // MARK: Built-in links

    private var builtInLinks: some View {
        SettingsSection(title: "Links that always work", footer: "They open the panel and run nothing.") {
            SettingsRow(title: "Open the panel", detail: ExternalLinks.open) {
                linkButtons(ExternalLinks.open)
            }
            SettingsRow(title: "Open with a search", detail: ExternalLinks.search("reveal")) {
                linkButtons(ExternalLinks.search("reveal"))
            }
        }
    }

    // MARK: Allowed commands

    private var allowedSection: some View {
        SettingsSection(
            title: "Commands that can run from outside",
            footer: "A link runs the command on what it passes in, never on what is selected in the front app."
        ) {
            if allowed.isEmpty {
                EmptyRows(
                    title: "Nothing allowed yet",
                    detail: store.runnable.isEmpty
                        ? "Make a command on the Commands page, then allow it here."
                        : "Allow one of your commands below.")
            }
            ForEach(allowed) { command in
                let link = ExternalLinks.run(command: command)
                SettingsRow(title: command.title, detail: status(of: command)) {
                    HStack(spacing: 8) {
                        copyButton(link)
                        Menu {
                            Button("Ask every time") { toggleAsk(command) }
                            if command.urlConfirmed { Button("Ask again next time") { reset(command) } }
                            Button("Stop allowing", role: .destructive) { setAllowed(command, false) }
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
    }

    private var notAllowedSection: some View {
        SettingsSection(title: "Not allowed from outside") {
            ForEach(notAllowed) { command in
                SettingsRow(title: command.title, detail: "Only you can run it, from the panel or its shortcut.") {
                    Button("Allow") { setAllowed(command, true) }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private func status(of command: UserCommand) -> String {
        let link = command.aliases.first ?? "its id"
        let asks =
            command.needsConfirmation || settings.externalAlwaysConfirm
            ? "Asks every time" : (command.urlConfirmed ? "Asked once, runs now" : "Will ask the first time")
        return "\(asks). Link uses \(link)."
    }

    private func setAllowed(_ command: UserCommand, _ on: Bool) {
        var edited = command
        edited.allowFromURL = on
        run { _ = try store.update(edited) }
    }

    private func toggleAsk(_ command: UserCommand) {
        var edited = command
        edited.needsConfirmation.toggle()
        run { _ = try store.update(edited) }
    }

    private func reset(_ command: UserCommand) { run { try store.resetURLConfirmation(command.id) } }

    private func run(_ work: () throws -> Void) {
        do {
            try work()
            message = nil
        } catch {
            message = "That did not work: \(error)"
        }
        tick += 1
    }

    // MARK: Builder

    private var builder: some View {
        let command = allowed.first { $0.id.rawValue == builderCommand } ?? allowed.first
        let link = command.map {
            ExternalLinks.run(command: $0, parameters: [.text: builderText, .url: builderURL])
        }
        return SettingsSection(title: "Build a link", footer: "Fill in what the link should pass. Everything is encoded for you.") {
            if let command, let link {
                SettingsRow(title: "Command") {
                    ValueMenu(
                        options: allowed.map { ($0.id.rawValue, $0.title) },
                        selection: Binding(get: { command.id.rawValue }, set: { builderCommand = $0 }))
                }
                builderField("Text", text: $builderText, prompt: "Optional")
                builderField("Page address", text: $builderURL, prompt: "Optional, http or https")
                CodeBox(text: link)
                    .padding(16)
            } else {
                EmptyRows(title: "Allow a command first", detail: "Then you can build a link for it here.")
            }
        }
    }

    private func builderField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        SettingsRow(title: title) {
            TextField("", text: text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 12)
                .frame(width: 240, height: 30)
                .background(Capsule().fill(Brand.raised))
        }
    }

    // MARK: Recipes

    private var recipes: some View {
        let sample = allowed.first.map { $0.aliases.first ?? $0.id.rawValue } ?? "up"
        return SettingsSection(title: "Set it up in other tools") {
            recipe("Raycast quicklink", "apropos://run?command=\(sample)&text={Selected Text}")
            recipe("Alfred or a script", "open \"apropos://run?command=\(sample)&text=hello%20world\"")
            recipe("Open the panel from anywhere", "open \"apropos://open\"")
        }
    }

    private func recipe(_ title: String, _ code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Brand.text)
            CodeBox(text: code)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1).padding(.leading, 16) }
    }

    // MARK: Activity

    private var activity: some View {
        let entries = controller.externalLog.entries
        return SettingsSection(
            title: "Recent requests",
            footer: "The last 50, newest first. It shows what was asked and the result, never the values passed in.",
            accessory: entries.isEmpty
                ? nil
                : AnyView(
                    Button {
                        controller.externalLog.clear()
                        tick += 1
                    } label: {
                        Text("Clear")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Brand.text2)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(Capsule().fill(Brand.raised))
                    }
                    .buttonStyle(.plain))
        ) {
            if entries.isEmpty {
                EmptyRows(
                    title: settings.externalLog ? "Nothing yet" : "Not kept",
                    detail: settings.externalLog
                        ? "Requests from links and Shortcuts show up here."
                        : "Turn on \"Keep a list of outside requests\" to see them.")
            }
            ForEach(entries.prefix(10)) { entry in
                SettingsRow(title: describe(entry), detail: entry.time.formatted(.relative(presentation: .named))) {
                    Badge(text: label(entry.result), tone: tone(entry.result))
                }
            }
            SettingToggleRow(id: .externalLog, isOn: Binding(get: { settings.externalLog }, set: { settings.externalLog = $0 }))
        }
    }

    private func describe(_ entry: ExternalActivityEntry) -> String {
        switch entry.action {
        case "open": "Opened the panel"
        case "search": "Opened the panel with a search"
        default: entry.command.map { "Ran \($0)" } ?? "Tried to run a command"
        }
    }

    private func label(_ result: ExternalActivityEntry.Result) -> String {
        switch result {
        case .ran: "Done"
        case .declined: "You said no"
        case .refused: "Refused"
        case .failed: "Failed"
        case .turnedOff: "Turned off"
        }
    }

    private func tone(_ result: ExternalActivityEntry.Result) -> Badge.Tone {
        switch result {
        case .ran: .mint
        case .refused, .failed: .warning
        case .declined, .turnedOff: .quiet
        }
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        SettingsSection(title: "Shortcuts") {
            SettingsRow(
                title: "Actions in the Shortcuts app",
                detail: "Add Run Apropos Command (pick one you allowed, pass text or a page address) or Open Apropos."
            ) {
                Button("Open Shortcuts") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: Pieces

    private func linkButtons(_ link: String) -> some View {
        HStack(spacing: 8) {
            copyButton(link)
            Button("Try") {
                if let url = URL(string: link) { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func copyButton(_ link: String) -> some View {
        Button(copiedLink == link ? "Copied" : "Copy link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
            copiedLink = link
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}

/// A link or command in a monospaced box with a Copy button.
private struct CodeBox: View {
    let text: String

    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Brand.text)
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.raised))
    }
}

/// What outside control is, for someone who has never used a link or Shortcut with it.
private struct IntegrationsIntro: View {
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Start Apropos from anywhere")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.text)
                Text(
                    "A link such as apropos://run?command=up runs one of your commands from a Raycast quicklink, Alfred, a script or the Shortcuts app. It works only for commands you allow, asks you the first time, and tells the caller nothing about what you have."
                )
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(Brand.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ForEach(["apropos://open", "apropos://search?q=", "apropos://run"], id: \.self) { link in
                    Text(link)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.text2)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Theme.chip))
                }
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        .background(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous).fill(Brand.section))
    }
}
