import AppKit
import Apropos
import SwiftUI

/// What the menu bar popover can do. The status item supplies the closures; the previews pass empty ones.
struct MenuPopoverActions {
    var open: () -> Void = {}
    var runRecent: (UsageController.Recent) -> Void = { _ in }
    var allowAccess: () -> Void = {}
    var reviewCommands: () -> Void = {}
    var commands: () -> Void = {}
    var settings: () -> Void = {}
    var welcomeGuide: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var togglePause: () -> Void = {}
    var toggleLearning: () -> Void = {}
    var quit: () -> Void = {}
}

/// The menu bar popover: the app in front and what Apropos sees in it, the way in, recent commands, and the app's own
/// controls as a quiet row of buttons. It replaces the plain menu, which stays on right-click.
struct MenuPopoverView: View {
    let header: ContextHeaderModel
    let recents: [UsageController.Recent]
    let hotKey: HotKeyCombo
    let hasAccess: Bool
    var pendingCommands = 0
    var contextPaused = false
    var learningPaused = false
    let actions: MenuPopoverActions

    static let width: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            contextCard
                .padding(.horizontal, 10)
                .padding(.top, 10)
            pauseButtons
                .padding(.horizontal, 10)
                .padding(.top, 8)
            openButton
                .padding(.horizontal, 10)
                .padding(.top, 8)
            if !hasAccess { notice("Apropos needs Accessibility to read menus.", "Allow", actions.allowAccess) }
            if pendingCommands > 0 {
                notice(
                    "\(pendingCommands) imported command\(pendingCommands == 1 ? "" : "s") waiting.", "Review",
                    actions.reviewCommands)
            }
            recentSection
            footer
        }
        .frame(width: Self.width)
        .tint(Brand.mint)
    }

    // MARK: Context

    private var contextCard: some View {
        HStack(spacing: 11) {
            if let app = header.app {
                AppIcon(pid: app.pid, size: 36)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Brand.text3)
                    .frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(header.app?.name ?? "No app in front")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Text(header.chips.isEmpty ? "Apropos sees only the app" : header.chips.joined(separator: "  \u{00B7}  "))
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.section))
        .accessibilityElement(children: .combine)
    }

    /// Two real buttons: stop reading, or stop learning, for an hour. A paused one fills with the pearl, the colour of
    /// "now", and offers to resume.
    private var pauseButtons: some View {
        HStack(spacing: 8) {
            pauseButton(
                paused: contextPaused, pause: "Pause context", resume: "Resume context",
                help: "Stop reading the app in front for an hour", action: actions.togglePause)
            pauseButton(
                paused: learningPaused, pause: "Pause learning", resume: "Resume learning",
                help: "Stop learning what you run next for an hour", action: actions.toggleLearning)
        }
    }

    private func pauseButton(
        paused: Bool, pause: String, resume: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: paused ? "play.fill" : "pause.fill").font(.system(size: 10, weight: .bold))
                Text(paused ? resume : pause).font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(paused ? Brand.pearl : Brand.text2)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(Capsule().fill(paused ? Brand.pearl.opacity(0.16) : Brand.raised))
            .overlay(Capsule().strokeBorder(paused ? Brand.pearl.opacity(0.5) : Brand.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .help(help)
        .accessibilityLabel(paused ? resume : pause)
    }

    private var openButton: some View {
        Button(action: actions.open) {
            HStack(spacing: 8) {
                Text("Open Apropos")
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    ForEach(Array(hotKey.caps.enumerated()), id: \.offset) { _, cap in
                        Text(cap)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .frame(minWidth: 20, minHeight: 20)
                            .padding(.horizontal, cap.count > 1 ? 5 : 0)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Brand.mintInk.opacity(0.14)))
                    }
                }
            }
            .foregroundStyle(Brand.mintInk)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Capsule().fill(Brand.mint))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Open Apropos")
    }

    private func notice(_ text: String, _ button: String, _ action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Brand.danger).frame(width: 6, height: 6)
            Text(text).font(.system(size: 12)).foregroundStyle(Brand.text2).lineLimit(2)
            Spacer(minLength: 6)
            Button(button, action: action).buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    // MARK: Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Brand.text3)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            if recents.isEmpty {
                Text("Commands you run show up here.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.text3)
                    .padding(.horizontal, 10)
                    .frame(height: 34, alignment: .leading)
            }
            ForEach(recents.prefix(5)) { recent in
                RecentRow(recent: recent) { actions.runRecent(recent) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            FooterButton(symbol: "command", label: "Commands", action: actions.commands)
            FooterButton(symbol: "gearshape", label: "Settings", action: actions.settings)
            FooterButton(symbol: "sparkles", label: "Welcome guide", action: actions.welcomeGuide)
            FooterButton(symbol: "arrow.triangle.2.circlepath", label: "Check for updates", action: actions.checkForUpdates)
            Spacer(minLength: 0)
            FooterButton(symbol: "power", label: "Quit Apropos", action: actions.quit)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
    }
}

/// One recent command: the app's icon, the command, the app's name.
private struct RecentRow: View {
    let recent: UsageController.Recent
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AppIconImage(icon: icon, size: 20)
                Text(recent.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !recent.appName.isEmpty {
                    Text(recent.appName)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Brand.text3)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Capsule().fill(hovering ? Brand.raised : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var icon: NSImage? {
        guard let id = recent.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct FooterButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(hovering ? Brand.text : Brand.text2)
                .frame(width: 36, height: 32)
                .background(Capsule().fill(hovering ? Brand.raised : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A gentle press: the button sinks a little while held.
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.98 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
