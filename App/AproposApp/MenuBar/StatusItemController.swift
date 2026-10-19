import AppKit
import Apropos
import SwiftUI

/// The menu bar item: a native menu with a live context header, recent commands, and the app's own controls.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, NSPopoverDelegate {
    private let controller: AppController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let header = ContextHeaderModel()
    private let popover = NSPopover()
    #if DEBUG
        private let recorderProbe = RecorderProbe()
    #endif
    private var clickMonitor: Any?
    private var observer: NSObjectProtocol?

    init(controller: AppController) {
        self.controller = controller
        super.init()
        if let button = statusItem.button {
            // The ring and pearl mark, drawn as a template so the menu bar tints it for light, dark and selected states.
            let image =
                NSImage(named: "MenuBarGlyph")
                ?? NSImage(systemSymbolName: "command.square", accessibilityDescription: "Apropos")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            image?.accessibilityDescription = "Apropos"
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menu.delegate = self
        menu.autoenablesItems = false
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        applyVisibility()
        observer = NotificationCenter.default.addObserver(
            forName: .aproposSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyVisibility() }
        }
    }

    private func applyVisibility() {
        statusItem.isVisible = controller.settings.showInMenuBar
    }

    // MARK: Popover and menu

    /// Click opens the popover; right-click or Control-click opens the plain menu.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(from: sender)
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        controller.context.refresh(for: controller.tracker.app)
        header.app = controller.tracker.app
        header.chips = controller.context.items.map(\.label)
        controller.context.onChange = { [weak self] in
            guard let self else { return }
            self.header.chips = self.controller.context.items.map(\.label)
        }
        let close: (@escaping () -> Void) -> () -> Void = { [weak self] work in
            {
                self?.popover.performClose(nil)
                work()
            }
        }
        let controller = controller
        let baseActions = MenuPopoverActions(
            open: close { controller.togglePanel() },
            runRecent: { [weak self] recent in
                self?.popover.performClose(nil)
                self?.runRecentCommand(recent.stableID)
            },
            allowAccess: close { controller.showOnboarding(step: .permission) },
            reviewCommands: close { CommandManagement.reviewPending(controller.userCommands) },
            commands: close { controller.showSettings(page: .commands) },
            settings: close { controller.showSettings() },
            welcomeGuide: close { controller.showOnboarding() },
            checkForUpdates: close { controller.settings.checkForUpdatesNow() },
            togglePause: close {
                if controller.context.isPaused { controller.context.resume() } else { controller.context.pause(for: 3600) }
            },
            toggleLearning: close {
                let engine = controller.usage.prediction
                if engine.isLearningPaused { engine.resumeLearning() } else { engine.pauseLearning(for: 3600) }
            },
            quit: close { NSApp.terminate(nil) })
        var actions = baseActions
        #if DEBUG
            if !AgentMode.isOn {
                actions.probeTitle = recorderProbe.isRunning ? "Stop recording test" : "Record test (R0)"
                actions.probe = close { [recorderProbe] in recorderProbe.toggle() }
            }
        #endif
        let view = MenuPopoverView(
            header: header, recents: controller.usage.recents, hotKey: controller.combo,
            hasAccess: controller.permission.isTrusted, pendingCommands: controller.userCommands.pending.count,
            contextPaused: controller.context.isPaused, learningPaused: controller.usage.prediction.isLearningPaused,
            actions: actions)
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        controller.context.onChange = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func showMenu() {
        popover.performClose(nil)
        header.app = controller.tracker.app
        rebuild(menu)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
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

        let entries = MenuBarContent.entries(
            recents: controller.usage.recents, hotKey: controller.combo.display,
            hasAccess: controller.permission.isTrusted, pendingCommands: controller.userCommands.pending.count)
        for entry in entries {
            switch entry {
            case .separator: menu.addItem(.separator())
            case .sectionHeader(let title): menu.addItem(NSMenuItem.sectionHeader(title: title))
            case .placeholder(let title):
                let none = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                none.isEnabled = false
                menu.addItem(none)
            case .recent(let recent, let title):
                let row = item(title, #selector(runRecent(_:)))
                row.representedObject = recent.stableID
                menu.addItem(row)
            case .action(let action, let title, let key):
                menu.addItem(item(title, selector(for: action), key: key))
            }
        }
    }

    private func selector(for action: MenuBarContent.Action) -> Selector {
        switch action {
        case .open: #selector(openApropos)
        case .allowAccess: #selector(allowAccess)
        case .welcomeGuide: #selector(welcomeGuide)
        case .settings: #selector(openSettings)
        case .manageCommands: #selector(manageCommands)
        case .reviewCommands: #selector(reviewCommands)
        case .checkForUpdates: #selector(checkForUpdates)
        case .quit: #selector(quit)
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Runs a recent command if the app in front still offers it, else opens the panel for that app.
    @objc private func runRecent(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        runRecentCommand(raw)
    }

    private func runRecentCommand(_ raw: String) {
        if let command = controller.menus.commands.first(where: { $0.stableID.rawValue == raw }) {
            let appName = controller.tracker.app?.name
            let appBundleID = controller.tracker.app?.bundleID
            Task { [controller] in
                if await controller.palette.run(command) {
                    controller.usage.recordRun(command, appName: appName, appBundleID: appBundleID)
                }
            }
        } else {
            controller.togglePanel()
        }
    }

    @objc private func openApropos() { controller.togglePanel() }
    @objc private func allowAccess() { controller.showOnboarding(step: .permission) }
    @objc private func welcomeGuide() { controller.showOnboarding() }
    @objc private func openSettings() { controller.showSettings() }
    @objc private func checkForUpdates() { controller.settings.checkForUpdatesNow() }
    @objc private func manageCommands() { controller.showSettings(page: .commands) }
    @objc private func reviewCommands() { CommandManagement.reviewPending(controller.userCommands) }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// What the menu lists, as plain values: the status item turns them into `NSMenuItem`s and the previews draw them.
enum MenuBarContent {
    enum Action {
        case open, allowAccess, welcomeGuide, settings, checkForUpdates, quit
        case manageCommands, reviewCommands
    }

    enum Entry {
        case separator
        case sectionHeader(String)
        case placeholder(String)
        case recent(UsageController.Recent, title: String)
        case action(Action, title: String, key: String)
    }

    static func entries(
        recents: [UsageController.Recent], hotKey: String, hasAccess: Bool, pendingCommands: Int = 0
    ) -> [Entry] {
        var list: [Entry] = [.sectionHeader("Recent")]
        if recents.isEmpty { list.append(.placeholder("No recent commands yet")) }
        for recent in recents {
            let title = recent.appName.isEmpty ? recent.title : "\(recent.title)  \u{00B7}  \(recent.appName)"
            list.append(.recent(recent, title: title))
        }
        list.append(.separator)
        list.append(.action(.open, title: "Open Apropos (\(hotKey))", key: ""))
        if !hasAccess { list.append(.action(.allowAccess, title: "Allow Accessibility Access\u{2026}", key: "")) }
        if pendingCommands > 0 {
            let title = "Review \(pendingCommands) Imported Command\(pendingCommands == 1 ? "" : "s")\u{2026}"
            list.append(.action(.reviewCommands, title: title, key: ""))
        }
        list.append(.separator)
        list.append(.action(.manageCommands, title: "Commands\u{2026}", key: ""))
        list.append(.action(.settings, title: "Settings\u{2026}", key: ","))
        list.append(.action(.welcomeGuide, title: "Welcome Guide", key: ""))
        list.append(.action(.checkForUpdates, title: "Check for Updates\u{2026}", key: ""))
        list.append(.separator)
        list.append(.action(.quit, title: "Quit Apropos", key: "q"))
        return list
    }
}

@MainActor
@Observable
final class ContextHeaderModel {
    var app: TargetApp?
    var chips: [String] = []
}

/// The first row of the menu: the app in front and what Apropos sees in it.
struct ContextHeaderView: View {
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
                Text(model.chips.isEmpty ? "Apropos sees only the app" : model.chips.joined(separator: "  \u{00B7}  "))
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
