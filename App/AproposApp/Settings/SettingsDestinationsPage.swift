import AppKit
import Apropos
import SwiftUI

/// Where Send to can put what you have selected: apps and services, and folders to copy or move files into.
struct DestinationsPage: View {
    let controller: AppController

    @State private var destinations: [Destination] = []
    @State private var folders: [URL] = []
    @State private var tick = 0
    @State private var detailed: Destination?
    @State private var creating = false

    var body: some View {
        DestinationsIntro()
        SettingsSection(
            title: "Apps and services",
            footer: "A destination you turn off is never offered in the panel, but stays here. Ones that leave this Mac ask you to confirm once more.",
            accessory: AnyView(
                PillButton(title: "New destination", symbol: "plus") { creating = true })
        ) {
            if destinations.isEmpty {
                EmptyRows(title: "No destinations", detail: "Add one with New destination.")
            }
            ForEach(destinations) { destination in
                DestinationRow(
                    destination: destination, enabled: enabled(destination),
                    onToggle: { on in
                        controller.setDestination(destination.id, enabled: on)
                        tick += 1
                    },
                    onDetails: { detailed = destination })
            }
        }
        SettingsSection(
            title: "Folders",
            footer: "Folders you can copy or move files into from the panel. Apropos remembers the last five.",
            accessory: AnyView(PillButton(title: "Add folder", symbol: "plus", action: addFolder))
        ) {
            if folders.isEmpty {
                EmptyRows(
                    title: "No folders yet",
                    detail: "Add a folder, or choose one the first time you send files from the panel.")
            }
            ForEach(folders, id: \.self) { folder in
                SettingsRow(
                    title: folder.lastPathComponent, detail: abbreviated(folder),
                    leading: AnyView(
                        Image(systemName: "folder").font(.system(size: 14)).foregroundStyle(Brand.text2).frame(width: 22))
                ) {
                    Button("Remove") {
                        controller.send.forgetFolder(folder)
                        refresh()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        SettingsSection {
            SettingsRow(title: "Destinations folder", detail: "Destination files live here. You can edit or share them.") {
                Button("Reveal in Finder") {
                    let folder = DestinationLibrary.userDirectory
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        Color.clear.frame(height: 0)
            .onAppear(perform: refresh)
            .id(tick)
            .sheet(item: $detailed) { destination in
                DestinationDetailSheet(controller: controller, destination: destination) {
                    detailed = nil
                    tick += 1
                }
            }
            .sheet(isPresented: $creating) {
                NewDestinationSheet {
                    creating = false
                    controller.reloadDestinations()
                    refresh()
                }
            }
    }

    private func enabled(_ destination: Destination) -> Bool { controller.destinationToggles.isEnabled(destination.id) }

    private func refresh() {
        destinations = controller.send.library.destinations
        folders = controller.send.savedFolders
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            controller.send.addFolder(url)
            refresh()
        }
    }

    private func abbreviated(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }
}

/// A small filled button for a section header.
struct PillButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Brand.mintInk)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(Brand.mint))
        }
        .buttonStyle(.plain)
    }
}

/// What Send to is, for someone who has never used it.
private struct DestinationsIntro: View {
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Send what you select, anywhere")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.text)
                Text(
                    "Select some text, a page or files, open the panel and choose Send to. Apropos puts it in Notes, Things, a folder, a Mail draft or the Share menu, without leaving the keyboard. The ones you use most come first."
                )
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(Brand.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Image(systemName: "paperplane").font(.system(size: 14)).foregroundStyle(Theme.text2).frame(width: 22)
                Text("Send selection to Notes").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("Selected text").font(.system(size: 12)).foregroundStyle(Theme.text3).lineLimit(1)
                Spacer(minLength: 8)
                KeyCap(text: "\u{21A9}")
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Capsule().fill(Theme.highlight))
            .frame(maxWidth: 440)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        .background(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous).fill(Brand.section))
    }
}

/// One destination: the app's own icon when it has one, its name, what it takes, and a switch.
private struct DestinationRow: View {
    let destination: Destination
    let enabled: Bool
    let onToggle: (Bool) -> Void
    let onDetails: () -> Void

    private var appURL: URL? {
        destination.appBundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    private var missing: Bool { destination.appBundleID != nil && appURL == nil }

    var body: some View {
        SettingsRow(
            title: destination.title,
            detail: missing ? "Not installed on this Mac" : destination.subtitle ?? kinds,
            leading: AnyView(icon.frame(width: 24, height: 24).opacity(missing || !enabled ? 0.45 : 1))
        ) {
            HStack(spacing: 8) {
                if !destination.isRunnable {
                    Badge(text: "Needs approval", tone: .warning)
                } else if destination.confirmation == .preview {
                    Badge(text: "Asks first")
                }
                if destination.origin == .user { Badge(text: "Yours", tone: .mint) }
                AproposToggle(
                    title: destination.title, isOn: Binding(get: { enabled }, set: onToggle))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDetails)
    }

    private var kinds: String {
        "Takes " + destination.accepts.map(\.rawValue).sorted().joined(separator: ", ")
    }

    @ViewBuilder
    private var icon: some View {
        if let appURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path)).resizable().interpolation(.high)
        } else {
            Image(systemName: destination.symbol).font(.system(size: 15)).foregroundStyle(Brand.text2)
        }
    }
}

/// What a destination does in plain words, what it can do to the Mac, a switch, and a harmless test.
private struct DestinationDetailSheet: View {
    let controller: AppController
    let destination: Destination
    let onClose: () -> Void

    @State private var enabled: Bool
    @State private var result: String?
    @State private var sending = false

    init(controller: AppController, destination: Destination, onClose: @escaping () -> Void) {
        self.controller = controller
        self.destination = destination
        self.onClose = onClose
        _enabled = State(initialValue: controller.destinationToggles.isEnabled(destination.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Brand.text2)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Brand.raised))
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(Brand.text)
                    Text(destination.isRunnable ? (enabled ? "On" : "Turned off") : "Waiting for your approval")
                        .font(.system(size: 12.5))
                        .foregroundStyle(destination.isRunnable && enabled ? Brand.mint : Brand.text3)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("What it does").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.text3)
                ScrollView {
                    Text(DestinationSummary.lines(for: destination).joined(separator: "\n"))
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Brand.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 160)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.raised))
            }
            let risks = DestinationSummary.risks(for: destination)
            if !risks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What it can do").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.text3)
                    ForEach(risks, id: \.self) { risk in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(risk.needsApproval ? Brand.danger : Brand.text3).frame(width: 5, height: 5)
                            Text(risk.warning).font(.system(size: 12.5)).foregroundStyle(Brand.text2)
                        }
                    }
                }
            }
            HStack {
                Text("Offer it in the panel").font(.system(size: 13)).foregroundStyle(Brand.text)
                Spacer()
                AproposToggle(title: "Offer it in the panel", isOn: $enabled)
                    .onChange(of: enabled) { _, value in controller.setDestination(destination.id, enabled: value) }
            }
            if let result {
                Text(result).font(.system(size: 12.5)).foregroundStyle(Brand.text2).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if destination.isRunnable && destination.accepts.contains(.text) && destination.handler == .engine {
                    Button(sending ? "Sending..." : "Send \u{201C}Hello from Apropos\u{201D}", action: sendTest)
                        .buttonStyle(BrandButtonStyle(kind: .secondary))
                        .disabled(sending)
                }
                Spacer()
                Button("Done", action: onClose).buttonStyle(BrandButtonStyle(kind: .primary))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(26)
        .frame(width: 500)
        .tint(Brand.mint)
    }

    private func sendTest() {
        sending = true
        result = nil
        Task {
            let outcome = await controller.send.sendTest(to: destination)
            sending = false
            switch outcome {
            case .success(let sent): result = sent.notice + ". Check the app."
            case .failure(let error): result = error.message
            }
        }
    }
}

/// A short guided form for a destination of your own.
private struct NewDestinationSheet: View {
    let onDone: () -> Void

    @State private var draft = DestinationDraft()
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New destination")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.text)
            HStack(spacing: 8) {
                ForEach(DestinationDraft.Kind.allCases) { kind in
                    let selected = draft.kind == kind
                    Button {
                        draft.kind = kind
                        problem = nil
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: kind.symbol).font(.system(size: 12.5))
                            Text(kind.title).font(.system(size: 12.5, weight: .medium))
                        }
                        .foregroundStyle(selected ? Brand.mintInk : Brand.text2)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(selected ? Brand.mint : Brand.raised))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text(draft.kind.explanation)
                .font(.system(size: 12.5))
                .foregroundStyle(Brand.text2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                switch draft.kind {
                case .link: field("Address", text: $draft.link, prompt: "bear://x-callback-url/create?text={text}")
                case .shortcut: field("Shortcut name", text: $draft.shortcutName, prompt: "Summarize Text")
                case .appendToFile: field("File", text: $draft.filePath, prompt: "/Users/you/Documents/notes.txt")
                }
                field("Name", text: $draft.title, prompt: "Bear inbox")
                HStack(alignment: .center, spacing: 12) {
                    Text("Symbol").font(.system(size: 12.5)).foregroundStyle(Brand.text2).frame(width: 104, alignment: .leading)
                    SymbolChooser(symbol: $draft.symbol, fallback: draft.kind.symbol)
                }
                if draft.kind != .link {
                    HStack {
                        Text("Also take web pages").font(.system(size: 13)).foregroundStyle(Brand.text)
                        Spacer()
                        AproposToggle(title: "Also take web pages", isOn: $draft.acceptsPages)
                    }
                }
            }
            if let problem {
                Text(problem).font(.system(size: 12.5)).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("It appears in Send to as soon as you add it.").font(.system(size: 12)).foregroundStyle(Brand.text3)
                Spacer()
                Button("Cancel", action: onDone).buttonStyle(BrandButtonStyle(kind: .plain)).keyboardShortcut(.cancelAction)
                Button("Add destination", action: add).buttonStyle(BrandButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 500)
        .tint(Brand.mint)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.system(size: 12.5)).foregroundStyle(Brand.text2).frame(width: 104, alignment: .leading)
            TextField("", text: text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(Brand.raised))
        }
    }

    private func add() {
        do {
            try draft.save(to: DestinationLibrary.userDirectory)
            onDone()
        } catch {
            problem = "\(error)"
        }
    }
}
