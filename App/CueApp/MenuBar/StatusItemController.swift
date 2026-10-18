import AppKit
import Cue
import SwiftUI

/// The menu bar item: a native menu with a live context header, recent commands, and the app's own controls.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let controller: AppController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let header = ContextHeaderModel()
    private var observer: NSObjectProtocol?

    init(controller: AppController) {
        self.controller = controller
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "Cue")
            image?.isTemplate = true
            button.image = image
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        applyVisibility()
        observer = NotificationCenter.default.addObserver(
            forName: .cueSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyVisibility() }
        }
    }

    private func applyVisibility() {
        statusItem.isVisible = controller.settings.showInMenuBar
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        controller.context.refresh(for: controller.tracker.app)
        header.app = controller.tracker.app
        header.chips = controller.context.items.map(\.label)
        controller.context.onChange = { [weak self] in
            guard let self else { return }
            self.header.chips = self.controller.context.items.map(\.label)
        }
        rebuild(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        controller.context.onChange = nil
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let headerItem = NSMenuItem()
        let host = NSHostingView(rootView: ContextHeaderView(model: header))
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 52)
        headerItem.view = host
        menu.addItem(headerItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem.sectionHeader(title: "Recent"))
        let recents = controller.usage.recents
        if recents.isEmpty {
            let none = NSMenuItem(title: "No recent commands yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for recent in recents {
            let title = recent.appName.isEmpty ? recent.title : "\(recent.title)  \u{2014}  \(recent.appName)"
            let entry = item(title, #selector(runRecent(_:)))
            entry.representedObject = recent.stableID
            menu.addItem(entry)
        }
        menu.addItem(.separator())

        menu.addItem(item("Open Cue (\(controller.combo.display))", #selector(openCue)))
        if !controller.permission.isTrusted {
            menu.addItem(item("Allow Accessibility Access\u{2026}", #selector(allowAccess)))
        }
        menu.addItem(.separator())
        let settings = item("Settings\u{2026}", #selector(openSettings), key: ",")
        menu.addItem(settings)
        menu.addItem(item("Check for Updates\u{2026}", #selector(checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Cue", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Runs a recent command if the app in front still offers it, else opens the panel for that app.
    @objc private func runRecent(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        if let command = controller.menus.commands.first(where: { $0.stableID.rawValue == raw }) {
            let appName = controller.tracker.app?.name
            Task { [controller] in
                if await controller.palette.run(command) { controller.usage.recordRun(command, appName: appName) }
            }
        } else {
            controller.togglePanel()
        }
    }

    @objc private func openCue() { controller.togglePanel() }
    @objc private func allowAccess() { controller.showOnboarding() }
    @objc private func openSettings() { controller.showSettings() }
    @objc private func checkForUpdates() { controller.settings.checkForUpdatesNow() }
    @objc private func quit() { NSApp.terminate(nil) }
}

@MainActor
@Observable
final class ContextHeaderModel {
    var app: TargetApp?
    var chips: [String] = []
}

/// The first row of the menu: the app in front and what Cue sees in it.
private struct ContextHeaderView: View {
    let model: ContextHeaderModel

    var body: some View {
        HStack(spacing: 10) {
            if let app = model.app {
                AppIcon(pid: app.pid, size: 28)
            } else {
                Image(systemName: "app.dashed").font(.system(size: 20)).foregroundStyle(.secondary).frame(
                    width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.app?.name ?? "No app in front")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.chips.isEmpty ? "Cue sees only the app" : model.chips.joined(separator: "  \u{00B7}  "))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 280, height: 52, alignment: .leading)
    }
}
