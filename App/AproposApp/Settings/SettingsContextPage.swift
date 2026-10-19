import AppKit
import Apropos
import SwiftUI

/// What Apropos reads from the app in front, shown live, with a switch for each kind and a setting for each app.
struct ContextPage: View {
    let controller: AppController
    let settings: SettingsModel

    @State private var apps: [AppEntry] = []
    @State private var picking = false

    struct AppEntry: Identifiable, Sendable {
        let bundleID: String
        let name: String
        let path: String
        var id: String { bundleID }
    }

    private static let sourceDetails: [String: String] = [
        "document": "The name and place of the file open in the front window.",
        "url": "The address and title of the page in a browser.",
        "folder": "The folder in a Finder window, and the files selected in it.",
        "branch": "The git branch of the folder or project you are in.",
        "selection": "The text you have selected.",
    ]

    var body: some View {
        @Bindable var settings = settings
        ContextIntro()
        SettingsSection(
            footer: "Everything Apropos reads stays in memory on this Mac, is read only when you open the panel, and is never saved or sent."
        ) {
            SettingToggleRow(id: .contextSensing, isOn: $settings.contextSensing)
        }
        LiveContextCard(controller: controller, settings: settings)
            .opacity(settings.contextSensing ? 1 : 0.5)
        SettingsSection(title: "What it reads", footer: "Turn one off and it is dropped before anything uses it, in every app.") {
            ForEach(SettingsRegistry.contextSourceOptions, id: \.value) { option in
                SettingsRow(title: option.title, detail: Self.sourceDetails[option.value]) {
                    AproposToggle(
                        title: option.title,
                        isOn: Binding(
                            get: { settings.contextSources.contains(option.value) },
                            set: { on in
                                var sources = settings.contextSources
                                if on { sources.insert(option.value) } else { sources.remove(option.value) }
                                settings.contextSources = sources
                            }))
                }
            }
        }
        .settingsAnchor(SettingID.contextSources.rawValue)
        .opacity(settings.contextSensing ? 1 : 0.5)
        .disabled(!settings.contextSensing)
        SettingsSection(
            title: "Apps that are not read",
            footer:
                "Apropos reads every app unless you add it here. Password managers and banks are protected by default.",
            accessory: AnyView(PillButton(title: "Add app", symbol: "plus") { picking = true })
        ) {
            if exceptions.isEmpty {
                EmptyRows(title: "No exceptions", detail: "Apropos reads context in every app.")
            }
            ForEach(exceptions) { app in
                SettingsRow(
                    title: app.name,
                    detail: protectedByDefault(app) ? "Protected by default" : nil,
                    leading: AnyView(AppIconImage(icon: NSWorkspace.shared.icon(forFile: app.path), size: 22))
                ) {
                    HStack(spacing: 8) {
                        ValueMenu(
                            options: [
                                (SettingsModel.AppReading.off, "Reads nothing"),
                                (SettingsModel.AppReading.noSelection, "Skips the selection"),
                            ],
                            selection: Binding(
                                get: { settings.reading(of: app.bundleID) },
                                set: { settings.setReading($0, of: app.bundleID) }))
                        Button {
                            settings.setReading(.full, of: app.bundleID)
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(Brand.text3)
                        }
                        .buttonStyle(.plain)
                        .help("Read this app again")
                        .accessibilityLabel("Read \(app.name) again")
                    }
                }
            }
        }
        .settingsAnchor(SettingID.contextDisabledApps.rawValue)
        .opacity(settings.contextSensing ? 1 : 0.5)
        .disabled(!settings.contextSensing)
        Color.clear.frame(height: 0).task { apps = await Self.scan(including: settings) }
            .sheet(isPresented: $picking) {
                AppPickerSheet(apps: apps.filter { settings.reading(of: $0.bundleID) == .full }) { chosen in
                    settings.setReading(.off, of: chosen.bundleID)
                    picking = false
                } onCancel: { picking = false }
            }
    }

    /// Installed apps that have a rule: not read at all, or read without the selection.
    private var exceptions: [AppEntry] {
        apps.filter { settings.reading(of: $0.bundleID) != .full }
    }

    private func protectedByDefault(_ app: AppEntry) -> Bool {
        SettingsRegistry.defaultIgnoreList.contains(app.bundleID) && settings.reading(of: app.bundleID) == .off
    }

    /// Every app installed in the usual places, plus running ones from elsewhere. An id named in a list but not found on
    /// this Mac is left out: the rule still applies if the app is installed later.
    @MainActor
    static func scan(including settings: SettingsModel) async -> [AppEntry] {
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> AppEntry? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, let url = app.bundleURL else {
                return nil
            }
            return AppEntry(bundleID: id, name: app.localizedName ?? id, path: url.path)
        }
        let own = Bundle.main.bundleIdentifier
        let installed = await Task.detached(priority: .userInitiated) { () -> [AppEntry] in
            let fm = FileManager.default
            let roots = [
                "/Applications", "/Applications/Utilities", "/System/Applications",
                "/System/Applications/Utilities", NSHomeDirectory() + "/Applications",
            ]
            var found: [AppEntry] = []
            for root in roots {
                for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".app") {
                    let path = root + "/" + name
                    guard let id = Bundle(path: path)?.bundleIdentifier else { continue }
                    found.append(
                        AppEntry(
                            bundleID: id, name: fm.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""),
                            path: path))
                }
            }
            return found
        }.value
        var seen = Set<String>()
        var list: [AppEntry] = []
        for entry in running + installed where entry.bundleID != own && seen.insert(entry.bundleID).inserted {
            list.append(entry)
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// A searchable list of installed apps to choose one from.
struct AppPickerSheet: View {
    let apps: [ContextPage.AppEntry]
    var note = "Apropos will read nothing in the app you choose."
    let onChoose: (ContextPage.AppEntry) -> Void
    let onCancel: () -> Void

    @State private var query = ""

    private var matches: [ContextPage.AppEntry] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return apps }
        return apps.filter { app in words.allSatisfy { app.name.lowercased().contains($0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose an app")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.text)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.text3)
                TextField("Search apps", text: $query).textFieldStyle(.plain).font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Brand.raised))
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(matches) { app in
                        Button {
                            onChoose(app)
                        } label: {
                            HStack(spacing: 10) {
                                AppIconImage(icon: NSWorkspace.shared.icon(forFile: app.path), size: 24)
                                Text(app.name).font(.system(size: 13.5)).foregroundStyle(Brand.text)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 300)
            HStack {
                Text(note)
                    .font(.system(size: 12)).foregroundStyle(Brand.text3)
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(BrandButtonStyle(kind: .plain))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(26)
        .frame(width: 440)
        .tint(Brand.mint)
    }
}

/// What context is, for someone who has never seen it.
private struct ContextIntro: View {
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("What the front app is showing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.text)
                Text(
                    "When you open the panel, Apropos looks at the app in front: its document, web address, folder, git branch and what you have selected. That is how it offers the right actions, such as copying a page as a link or compressing the files you picked."
                )
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(Brand.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ForEach([("doc", "Notes.md"), ("link", "linear.app"), ("arrow.triangle.branch", "feat/panel")], id: \.1) {
                    pair in
                    HStack(spacing: 5) {
                        Image(systemName: pair.0).font(.system(size: 10.5, weight: .medium))
                        Text(pair.1).font(.system(size: 11.5))
                    }
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 9)
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

/// The real thing, live: the app that was in front and the chips Apropos read from it just now.
private struct LiveContextCard: View {
    let controller: AppController
    let settings: SettingsModel

    @State private var refreshed = false

    var body: some View {
        let app = controller.tracker.app
        let model = controller.context
        SettingsSection(
            title: "Read right now",
            accessory: AnyView(
                Button(action: refresh) {
                    Label("Read again", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Brand.text2)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Brand.raised))
                }
                .buttonStyle(.plain))
        ) {
            HStack(spacing: 12) {
                if let app {
                    AppIcon(pid: app.pid, size: 34)
                } else {
                    Image(systemName: "macwindow").font(.system(size: 24, weight: .light)).foregroundStyle(Brand.text3)
                        .frame(width: 34, height: 34)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(app?.name ?? "No app in front")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.text)
                    chips(model: model)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .onAppear(perform: refresh)
    }

    @ViewBuilder
    private func chips(model: ContextModel) -> some View {
        if model.isPaused {
            Text("Paused. Nothing is being read.").font(.system(size: 12.5)).foregroundStyle(Brand.text3)
        } else if !settings.contextSensing {
            Text("Context is off.").font(.system(size: 12.5)).foregroundStyle(Brand.text3)
        } else if model.items.isEmpty {
            Text(refreshed ? "Nothing read from this app." : "Reading...")
                .font(.system(size: 12.5)).foregroundStyle(Brand.text3)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(model.items) { item in
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 10.5, weight: .medium))
                        Text(item.label).font(.system(size: 11.5)).lineLimit(1)
                    }
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(Theme.chip))
                }
            }
        }
    }

    private func refresh() {
        controller.context.refresh(for: controller.tracker.app)
        Task {
            try? await Task.sleep(for: .seconds(1))
            refreshed = true
        }
    }
}
