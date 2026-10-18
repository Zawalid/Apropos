import AppKit
import Apropos
import SwiftUI

/// Owns the palette panel: builds it once, so opening is just ordering a ready window to the front, and shows, hides and
/// positions it.
@MainActor
final class PanelController: NSObject {
    private let panel = PalettePanel()
    private let state = PanelState()
    private let context: ContextModel
    private let settings: SettingsModel
    private let usage: UsageController
    private var lastHide = Date.distantPast
    private var lastQuery = ""
    private let model: PaletteModel
    private let openSettings: () -> Void
    private var resignObserver: NSObjectProtocol?
    private var clickMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init(
        model: PaletteModel, tracker: FrontmostAppTracker, permission: AccessibilityPermission,
        settings: SettingsModel, context: ContextModel, usage: UsageController, openSettings: @escaping () -> Void,
        openGuide: @escaping () -> Void = {}
    ) {
        self.model = model
        self.settings = settings
        self.usage = usage
        self.context = context
        self.openSettings = openSettings
        super.init()

        let root = PaletteView(
            model: model, state: state, context: context, usage: usage, permission: permission,
            settings: settings,
            actions: PaletteActions(
                run: { [weak self] in self?.runSelected() },
                runCommand: { [weak self] command in self?.run(command) },
                perform: { [weak self] action in self?.perform(action) },
                toggleActions: { [weak self] in self?.toggleActions() },
                openSettings: { [weak self] in
                    self?.hide(immediately: true)
                    openSettings()
                },
                retry: { [weak self] in self?.model.prepareForOpen() },
                openGuide: { [weak self] in
                    self?.hide(immediately: true)
                    openGuide()
                }))
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: PanelPlacement.size)
        panel.contentView = hosting
        panel.setContentSize(PanelPlacement.size)

        #if DEBUG
            if AgentMode.isOn, let name = ProcessInfo.processInfo.environment["APROPOS_APPEARANCE"] {
                panel.appearance = NSAppearance(named: name == "light" ? .aqua : .darkAqua)
            }
        #endif
        panel.keyHandler = { [weak self] key in self?.handle(key) ?? false }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.settings.closeOnFocusLoss else { return }
                self.hide()
            }
        }
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Opening is ordering a ready window to the front: no animation, the content is already drawn.
    func show() {
        model.prepareForOpen()
        if Date().timeIntervalSince(lastHide) < TimeInterval(settings.resetQuerySeconds) { model.query = lastQuery }
        context.refresh(for: model.targetApp)
        closeActions(animated: false)
        position()
        panel.makeKeyAndOrderFront(nil)
        AgentMode.conceal(panel)
        panel.invalidateShadow()
        NotificationCenter.default.post(name: .aproposPanelOpened, object: nil)
        state.focusToken += 1
        AproposLog.panel.info(
            "show target=\(self.model.targetApp?.name ?? "none", privacy: .public) commands=\(self.model.results.count)"
        )
        #if DEBUG
            applyDebugPreview()
            DebugSnapshot.scheduleIfRequested(of: panel, model: model)
        #endif
    }

    /// Takes the window away at once. Closing never animates.
    func hide(immediately: Bool = false) {
        guard panel.isVisible else { return }
        closeActions(animated: false)
        lastHide = Date()
        lastQuery = model.query
        panel.orderOut(nil)
    }

    #if DEBUG
        /// APROPOS_PREVIEW_QUERY, APROPOS_PREVIEW_MOVE (rows to move down) and APROPOS_PREVIEW_ACTIONS shape what a snapshot shows.
        private func applyDebugPreview() {
            let env = ProcessInfo.processInfo.environment
            if let query = env["APROPOS_PREVIEW_QUERY"] { model.query = query }
            if let move = env["APROPOS_PREVIEW_MOVE"].flatMap(Int.init) { model.moveSelection(by: move) }
            if env["APROPOS_PREVIEW_ACTIONS"] != nil { toggleActions() }
        }
    #endif

    private func position() {
        let screens = NSScreen.screens
        let mouse = NSEvent.mouseLocation
        let index = PanelPlacement.index(containing: mouse, in: screens.map(\.frame))
        guard let index else { return }
        panel.setFrame(PanelPlacement.frame(in: screens[index].visibleFrame), display: false)
    }

    private func handle(_ key: PaletteKey) -> Bool {
        AproposLog.panel.info(
            "key \(String(describing: key), privacy: .public) query=\(self.model.query, privacy: .public) selected=\(self.model.selected?.command.title ?? "none", privacy: .public)"
        )
        if state.actionsOpen { return handleActions(key) }
        switch key {
        case .close: hide()
        case .run: runSelected()
        case .actions: toggleActions()
        case .settings: actionsOpenSettings()
        case .move(let delta): model.moveSelection(by: delta)
        case .first: model.selectFirst()
        case .last: model.selectLast()
        }
        return true
    }

    /// Keys while the Cmd+K popover is open: it takes the arrows, Return and Escape.
    private func handleActions(_ key: PaletteKey) -> Bool {
        let items = availableActions
        switch key {
        case .close, .actions: closeActions(animated: true)
        case .settings: actionsOpenSettings()
        case .move(let delta):
            guard !items.isEmpty else { return true }
            state.actionIndex = min(max(state.actionIndex + (delta > 0 ? 1 : -1), 0), items.count - 1)
        case .first: state.actionIndex = 0
        case .last: state.actionIndex = max(items.count - 1, 0)
        case .run:
            if items.indices.contains(state.actionIndex) { perform(items[state.actionIndex]) }
        }
        return true
    }

    private var availableActions: [PaletteAction] {
        PaletteAction.available(
            for: model.selected?.command, appName: model.targetApp?.name,
            isPinned: model.selected.map { usage.isPinned($0.command) } ?? false)
    }

    private func actionsOpenSettings() {
        hide()
        openSettings()
    }

    private func toggleActions() {
        if state.actionsOpen {
            closeActions(animated: true)
        } else if model.selected != nil {
            state.actionIndex = 0
            withAnimation(Motion.popover) { state.actionsOpen = true }
        }
    }

    private func closeActions(animated: Bool) {
        guard state.actionsOpen else { return }
        if animated {
            withAnimation(Motion.popover) { state.actionsOpen = false }
        } else {
            state.actionsOpen = false
        }
    }

    private func perform(_ action: PaletteAction) {
        guard let command = model.selected?.command else { return }
        switch action.kind {
        case .run:
            run(command)
        case .runAlternate(let index):
            guard command.alternates.indices.contains(index) else { return }
            let alternate = command.alternates[index]
            run(
                Command(
                    id: command.id, title: alternate.title, path: command.path, shortcut: alternate.shortcut,
                    isEnabled: alternate.isEnabled, isChecked: false, source: command.source, target: alternate.target,
                    stableID: alternate.stableID))
        case .pin(let pinned):
            usage.setPinned(pinned, for: command)
            hide()
        case .hide:
            usage.hide(command)
            hide()
        case .copyPath:
            PaletteAction.copy((command.path + [command.displayTitle]).joined(separator: " > "))
            hide()
        case .copyShortcut:
            PaletteAction.copy(command.shortcut?.display ?? "")
            hide()
        }
    }

    func runSelectedForDebug() { runSelected() }

    private func runSelected() {
        guard let command = model.selected?.command else { return }
        run(command)
    }

    /// Closes the panel first so the key window goes back to the app underneath, then presses the item. If that fails
    /// the panel comes back with the reason.
    private func run(_ command: Command) {
        hide(immediately: true)
        let appName = model.targetApp?.name
        Task { [weak self] in
            guard let self else { return }
            let closed = await self.model.run(command)
            if closed { self.usage.recordRun(command, appName: appName) }
            AproposLog.panel.info(
                "ran \(command.breadcrumb, privacy: .public) > \(command.title, privacy: .public) ok=\(closed) error=\(self.model.runError ?? "none", privacy: .public)"
            )
            if !closed { self.reopenWithError() }
        }
    }

    private func reopenWithError() {
        position()
        panel.makeKeyAndOrderFront(nil)
        state.focusToken += 1
    }
}
