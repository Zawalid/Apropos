import AppKit
import Apropos
import CoreGraphics
import SwiftUI

/// The changelog as the app has it: the bundled file, or the repository's in a debug run.
enum ChangelogSource {
    static func load() -> [ChangelogRelease] {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") { candidates.append(bundled) }
        #if DEBUG
            candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("CHANGELOG.md"))
        #endif
        for url in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8) { return ChangelogParser.parse(text) }
        }
        return []
    }
}

// MARK: Updates

struct UpdatesPage: View {
    let settings: SettingsModel

    @State private var releases: [ChangelogRelease] = []
    @State private var open: Set<String> = []

    var body: some View {
        @Bindable var settings = settings
        SettingsSection(
            footer: settings.updatesAvailable
                ? "Apropos asks GitHub once a day when this is on. Nothing is downloaded or installed until you press Install Update."
                : "This build has no update signing key, so a new build is installed by hand. Nothing contacts a server."
        ) {
            SettingsRow(
                title: "You have Apropos \(AboutPage.version)",
                detail: settings.updatesAvailable ? nil : "Updates are not set up in this build."
            ) {
                if settings.updatesAvailable {
                    Button("Check now") { settings.checkForUpdatesNow() }
                        .buttonStyle(SecondaryButtonStyle())
                        .help("Ask GitHub now whether a newer version exists")
                } else {
                    Badge(text: "Early access", tone: .mint)
                }
            }
            SettingToggleRow(id: .checkForUpdates, isOn: $settings.checkForUpdates)
                .opacity(settings.updatesAvailable ? 1 : 0.5)
                .disabled(!settings.updatesAvailable)
                .settingsAnchor("checknow")
        }
        SettingsSection(title: "What has changed") {
            if releases.isEmpty {
                EmptyRows(title: "No changelog here", detail: "This build was made without one.")
            }
            ForEach(releases) { release in
                ReleaseRow(release: release, isOpen: open.contains(release.id)) {
                    if open.contains(release.id) { open.remove(release.id) } else { open.insert(release.id) }
                }
            }
        }
        Color.clear.frame(height: 0).task {
            releases = ChangelogSource.load()
            if let first = releases.first { open = [first.id] }
        }
    }
}

private struct ReleaseRow: View {
    let release: ChangelogRelease
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.text3)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 14)
                    Text(release.isUnreleased ? "Coming next" : "Version \(release.version)")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Brand.text)
                    if let date = release.date {
                        Text(date).font(.system(size: 12)).foregroundStyle(Brand.text3)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                ForEach(release.sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Brand.text3)
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(Brand.text3).frame(width: 4, height: 4)
                                Text(clean(item)).font(.system(size: 12.5)).foregroundStyle(Brand.text2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.leading, 22)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1).padding(.leading, 16) }
    }

    /// Items are long prose. Show the first sentence or two so the list stays readable.
    private func clean(_ item: String) -> String {
        let text = item.replacingOccurrences(of: "`", with: "")
        if text.count <= 220 { return text }
        let cut = text.prefix(220)
        if let end = cut.lastIndex(of: ".") { return String(cut[...end]) }
        return String(cut) + "..."
    }
}

// MARK: About

struct AboutPage: View {
    let controller: AppController
    let settings: SettingsModel

    @Environment(SettingsNavigation.self) private var navigation
    @State private var copied = false

    var body: some View {
        hero
        SettingsSection(title: "System") {
            info("Version", Self.version).settingsAnchor("version")
            info("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
            info("Shortcut registered", controller.isHotKeyRegistered ? "Yes" : "No", ok: controller.isHotKeyRegistered)
            info("Settings saved", settings.store.lastSaveError == nil ? "Yes" : "No", ok: settings.store.lastSaveError == nil)
        }
        SettingsSection(title: "Permissions") {
            info("Accessibility", controller.permission.isTrusted ? "Allowed" : "Not allowed", ok: controller.permission.isTrusted)
            info("Input Monitoring", CGPreflightListenEventAccess() ? "Allowed" : "Not needed yet", ok: true)
            info("Context sensing", settings.contextSensing ? "On" : "Off", ok: true)
        }
        SettingsSection(title: "Help") {
            SettingsRow(title: "Copy support info", detail: "Versions, permissions and counts. Nothing personal.") {
                Button(copied ? "Copied" : "Copy") { copySupport() }.buttonStyle(SecondaryButtonStyle())
            }
            SettingsRow(title: "Show the welcome guide", detail: "The short tour from the first launch.") {
                Button("Show") { controller.showOnboarding() }.buttonStyle(SecondaryButtonStyle())
            }
            SettingsRow(title: "Open the data folder", detail: "Where Apropos keeps its files.") {
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([controller.settings.store.url.deletingLastPathComponent()])
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        SettingsSection(title: "License") {
            SettingsRow(
                title: "Free and open source",
                detail: "Apropos is MIT licensed. You can read it, change it and build it yourself."
            ) {
                AboutLink(link: .license)
            }
            SettingsRow(title: "Website", detail: "Documentation, the changelog and the download page.") {
                AboutLink(link: .website)
            }
        }
        SettingsSection(title: "Notices") {
            SettingsRow(
                title: "Sparkle",
                detail: "In-app updates use Sparkle, MIT licensed, and only when you turn them on. The rest is built on Apple's system frameworks."
            ) { EmptyView() }
            SettingsRow(title: "Copyright", detail: "Copyright 2026 \(ProjectLinks.author).") { EmptyView() }
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            if let image = Brand.image("HeroRing", file: "hero-ring.png") {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(height: 150)
                    .padding(.top, -44)
                    .padding(.bottom, -32)
                    .accessibilityHidden(true)
            }
            Text("Apropos").font(.system(size: 22, weight: .semibold)).foregroundStyle(Brand.text)
            Text("Version \(Self.version)").font(.system(size: 12.5)).foregroundStyle(Brand.text3)
            Text("What you can do right now, in this app, with this selection.")
                .font(.system(size: 13))
                .foregroundStyle(Brand.text2)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                chip("What has changed", symbol: "clock.arrow.circlepath") { navigation.select(.updates) }
                chip("Privacy", symbol: "lock.shield") { navigation.select(.privacyAndData) }
            }
            .padding(.top, 4)
            Divider().overlay(Brand.line).frame(width: 220).padding(.top, 10)
            Text("Made by \(ProjectLinks.author)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Brand.text)
            HStack(spacing: 16) {
                ForEach([ProjectLinks.Link.authorGitHub, .authorWebsite, .authorX], id: \.self) { AboutLink(link: $0) }
            }
            HStack(spacing: 16) {
                ForEach([ProjectLinks.Link.repository, .issues, .license], id: \.self) { AboutLink(link: $0) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func chip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.text2)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(Brand.raised))
        }
        .buttonStyle(.plain)
    }

    private func info(_ title: String, _ value: String, ok: Bool = true) -> some View {
        SettingsRow(title: title) {
            Text(value).font(.system(size: 12.5)).foregroundStyle(ok ? Brand.text2 : Brand.danger)
        }
    }

    private func copySupport() {
        let info = Bundle.main.infoDictionary
        let report = SupportReport(
            version: info?["CFBundleShortVersionString"] as? String ?? "0", build: info?["CFBundleVersion"] as? String ?? "0",
            macOS: ProcessInfo.processInfo.operatingSystemVersionString, accessibility: controller.permission.isTrusted,
            inputMonitoring: CGPreflightListenEventAccess(), contextSensing: settings.contextSensing,
            shortcutRegistered: controller.isHotKeyRegistered, settingsSaved: settings.store.lastSaveError == nil,
            commands: controller.userCommands.commands.count, destinations: controller.send.library.destinations.count,
            learnedRuns: controller.usage.prediction.summary().runs)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.text, forType: .string)
        copied = true
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

/// A quiet text link with a small icon. The label underlines on hover, and the address shows as the tooltip.
struct AboutLink: View {
    let link: ProjectLinks.Link

    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(link.url)
        } label: {
            Label(link.title, systemImage: link.symbol)
                .font(.system(size: 12.5))
                .underline(hovering)
                .foregroundStyle(hovering ? Brand.mint : Brand.text2)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(link.url.absoluteString)
        .accessibilityLabel(link.title)
        .accessibilityHint("Opens \(link.url.host() ?? "the link") in your browser")
    }
}
