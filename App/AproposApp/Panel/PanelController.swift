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
    private let openSettings: (SettingsRequest) -> Void
    private var resignObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    private let positions: PanelPositionStore
    private let guides = SnapGuides()
    private var wasSnapped = false

    var isVisible: Bool { panel.isVisible }

    /// The view the Share menu anchors to.
    var anchorView: NSView? { panel.contentView }

    init(
        model: PaletteModel, tracker: FrontmostAppTracker, permission: AccessibilityPermission,
        settings: SettingsModel, context: ContextModel, usage: UsageController, openSettings: @escaping (SettingsRequest) -> Void,
        openGuide: @escaping () -> Void = {}, positions: PanelPositionStore
    ) {
        self.positions = positions
        self.model = model
        self.settings = settings
        self.usage = usage
        self.context = context
        self.openSettings = openSettings
        super.init()
        usage.contextKinds = { [weak context] in context?.senseKinds ?? [] }
        context.onKindsChange = { [weak model] in model?.refreshPredictions() }

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
                    openSettings(SettingsRequest())
                },
                retry: { [weak self] in self?.model.prepareForOpen() },
                openGuide: { [weak self] in
                    self?.hide(immediately: true)
                    openGuide()
                },
                back: { [weak self] in _ = self?.model.goBack() },
                openDraft: { [weak self] in
                    if let row = self?.model.sequences?.rootCommands.first { self?.runSend(row) }
                }))
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: PanelPlacement.size)
        panel.contentView = hosting
        panel.setContentSize(PanelPlacement.size)
        // The rows of Apropos itself open its Settings; the panel is already hidden when they run.
        model.setAppCommandHandler { app in
            switch app {
            case .newCommand: openSettings(SettingsRequest(page: .commands, intent: .newCommand))
            case .yourCommands: openSettings(SettingsRequest(page: .commands))
            }
        }

        #if DEBUG
            if AgentMode.isOn, let name = ProcessInfo.processInfo.environment["APROPOS_APPEARANCE"] {
                panel.appearance = NSAppearance(named: name == "light" ? .aqua : .darkAqua)
            }
        #endif
        panel.keyHandler = { [weak self] key in self?.handle(key) ?? false }
        panel.dragAdjust = { [weak self] proposed in self?.adjustDrag(proposed) ?? proposed }
        panel.dragEnded = { [weak self] frame in self?.finishDrag(frame) }
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
        // Reopened within the "reset search after" time: the search and the draft level are where the person left them.
        let recent = Date().timeIntervalSince(lastHide) < TimeInterval(settings.resetQuerySeconds)
        model.prepareForOpen(restoringLevel: recent)
        if recent { model.query = lastQuery }
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
            if let scene = env["APROPOS_PREVIEW_SEND"] { DebugFixtures.applySend(scene, model: model) }
            // A sequence scene shares the sample context of the send-to scenes.
            if let scene = env["APROPOS_PREVIEW_SEQUENCE"] { DebugFixtures.applySend(scene, model: model) }
        }
    #endif

    private var mode: PanelPlacement.Mode { PanelPlacement.Mode(rawValue: settings.panelPosition) ?? .centered }

    private func position() {
        let screens = NSScreen.screens
        let index = PanelPlacement.index(containing: NSEvent.mouseLocation, in: screens.map(\.frame))
        guard let index else { return }
        let screen = screens[index]
        let anchor = positions.anchor(forDisplay: screen.displayKey)
        panel.setFrame(
            PanelPlacement.frame(in: screen.visibleFrame, mode: mode, anchor: anchor), display: false)
    }

    /// While dragging: snap to the centre and thirds, show the guides, and keep the panel on the screen it is over.
    private func adjustDrag(_ proposed: CGRect) -> CGRect {
        guard let screen = screen(for: proposed) else { return proposed }
        let snapped = PanelPlacement.snap(proposed, in: screen.visibleFrame)
        guides.show(snapped.guides, in: screen.visibleFrame)
        // A tick on the trackpad each time the panel catches a guide, like aligning in other Mac apps.
        let isSnapped = snapped.guides.contains(where: \.isActive)
        if isSnapped && !wasSnapped {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        wasSnapped = isSnapped
        return PanelPlacement.clamp(snapped.frame, to: screen.visibleFrame)
    }

    private func finishDrag(_ frame: CGRect) {
        guides.hide()
        wasSnapped = false
        guard mode == .remember, let screen = screen(for: frame) else { return }
        positions.set(PanelPlacement.anchor(for: frame, in: screen.visibleFrame), forDisplay: screen.displayKey)
    }

    private func screen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(frame).width * lhs.frame.intersection(frame).height
                < rhs.frame.intersection(frame).width * rhs.frame.intersection(frame).height
        }
    }

    /// The symbol grid, the last field of the save-as-command form (`PanelState.formField`).
    private static let symbolField = 2

    private func handle(_ key: PaletteKey) -> Bool {
        AproposLog.panel.info(
            "key \(String(describing: key), privacy: .public) query=\(self.model.query, privacy: .public) selected=\(self.model.selected?.command.title ?? "none", privacy: .public)"
        )
        if state.actionsOpen { return handleActions(key) }
        switch key {
        case .close:
            // Escape goes back one level first: it cancels a confirmation, then leaves the destination list.
            if !model.goBack() { hide() }
        case .run: runSelected()
        case .runPrediction:
            guard let command = model.topPrediction else { return false }
            run(command)
        case .actions: toggleActions()
        case .settings: actionsOpenSettings()
        case .showMenu:
            guard let command = model.selected?.command, command.target is MenuRevealing else { return false }
            showMenu(of: command)
        case .move(let delta):
            if model.content == .sequenceSave {
                if state.formField == Self.symbolField, let sequences = model.sequences {
                    // In the symbol field the arrows walk the symbols; down opens the grid, up leaves for the fields.
                    var result = SequenceCenter.SymbolKeyResult.handled
                    for _ in 0..<(abs(delta) > 1 ? 3 : 1) { result = sequences.symbolKey(delta > 0 ? .down : .up) }
                    if result == .leave { state.formField = Self.symbolField - 1 }
                } else {
                    // Elsewhere in the save form the arrows move between the fields.
                    state.formField = (state.formField + (delta > 0 ? 1 : 2)) % 3
                }
                return true
            }
            model.cancelPending()
            model.moveSelection(by: delta)
        case .tab(let delta):
            if model.content == .sequenceSave {
                // Tab and Shift-Tab always change field, the grid included, and close it.
                model.sequences?.collapseSymbols()
                state.formField = (state.formField + (delta > 0 ? 1 : 2)) % 3
                return true
            }
            return handle(.move(delta))
        case .sideways(let delta):
            // Left and right only walk the grid; in every text field they move the cursor as usual.
            guard model.content == .sequenceSave, state.formField == Self.symbolField else { return false }
            model.sequences?.symbolKey(delta > 0 ? .right : .left)
        case .first:
            model.cancelPending()
            model.selectFirst()
        case .last:
            model.cancelPending()
            model.selectLast()
        case .deleteStep(let command):
            // Plain Backspace edits the query; it only deletes a step when there is nothing to erase.
            guard model.selectedStepID != nil, command || model.query.isEmpty else { return false }
            model.deleteSelectedStep()
        case .moveStep(let delta):
            guard model.selectedStepID != nil else { return false }
            model.moveSelectedStep(by: delta)
        }
        return true
    }

    /// Keys while the Cmd+K popover is open: it takes the arrows, Return and Escape.
    private func handleActions(_ key: PaletteKey) -> Bool {
        let items = availableActions
        switch key {
        case .close, .actions: closeActions(animated: true)
        case .settings: actionsOpenSettings()
        case .sideways: return false
        case .move(let delta), .tab(let delta):
            guard !items.isEmpty else { return true }
            state.actionIndex = min(max(state.actionIndex + (delta > 0 ? 1 : -1), 0), items.count - 1)
        case .first: state.actionIndex = 0
        case .last: state.actionIndex = max(items.count - 1, 0)
        case .run:
            if items.indices.contains(state.actionIndex) { perform(items[state.actionIndex]) }
        case .runPrediction, .deleteStep, .moveStep, .showMenu: break
        }
        return true
    }

    private var availableActions: [PaletteAction] {
        PaletteAction.available(
            for: model.selected?.command, appName: model.targetApp?.name,
            isPinned: model.selected.map { usage.isPinned($0.command) } ?? false,
            isPredicted: model.selected.map { model.isPredicted(rowID: $0.id) } ?? false,
            sequence: model.sequences)
    }

    private func actionsOpenSettings() {
        hide()
        openSettings(SettingsRequest())
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

    /// Closes the panel and opens the real menu the command lives in, so the person sees where it is.
    private func showMenu(of command: Command) {
        guard let target = command.target as? MenuRevealing else { return }
        hide()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            try? target.showMenu()
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
        case .showMenu:
            showMenu(of: command)
        case .notNow:
            usage.dismissPrediction(command)
            closeActions(animated: true)
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
        case .editCommand:
            if let id = PaletteModel.userCommandID(of: command), model.perform(.edit(id)) { hide(immediately: true) }
        case .duplicateCommand:
            if let id = PaletteModel.userCommandID(of: command) { model.perform(.duplicate(id)) }
            closeActions(animated: true)
        case .deleteCommand:
            // Delete asks first: the confirmation row waits for a Return, Escape cancels.
            model.requestDeletion(of: command)
            closeActions(animated: true)
        case .addToSequence:
            // The panel stays open: a sequence is built one row after another, and a refusal says why.
            model.addToSequence(command)
            closeActions(animated: true)
        case .moveStep(let delta):
            model.moveSelectedStep(by: delta)
            closeActions(animated: true)
        case .deleteStep:
            model.deleteSelectedStep()
            closeActions(animated: true)
        case .askMe(let asking):
            if let id = model.selectedStepID { model.sequences?.setAsking(asking, stepID: id) }
            closeActions(animated: true)
        case .continueOnFailure(let continues):
            if let id = model.selectedStepID { model.sequences?.setContinuesOnFailure(continues, stepID: id) }
            closeActions(animated: true)
        case .useSelection(let usesSelection):
            if let id = model.selectedStepID { model.sequences?.setUsesSelection(usesSelection, stepID: id) }
            closeActions(animated: true)
        }
    }

    func runSelectedForDebug() { runSelected() }

    private func runSelected() {
        if model.sendPending != nil {
            confirmSend()
            return
        }
        if model.pendingDeletion != nil {
            model.confirmDeletion()
            return
        }
        if model.sequenceAsking != nil || model.sequencePending != nil {
            // A question in the search field, or the combined confirmation: Return answers or confirms.
            Task { [weak self] in
                guard let self else { return }
                let closed = await self.model.runSelected()
                self.finishSend(closed: closed)
            }
            return
        }
        if model.content == .sequenceSave {
            // Return in the open symbol grid confirms the choice and closes the grid; the next Return saves.
            if model.sequences?.symbolExpanded == true {
                model.sequences?.collapseSymbols()
            } else {
                model.saveSequence()
            }
            return
        }
        guard let command = model.selected?.command else { return }
        run(command)
    }

    /// Send-to rows keep the panel open until the send finishes: a list opens in place, a confirmation waits for its
    /// Return, and a failure stays on screen with the payload intact. Only a finished send closes the panel.
    private func runSend(_ command: Command) {
        Task { [weak self] in
            guard let self else { return }
            let closed = await self.model.run(command)
            self.finishSend(closed: closed)
        }
    }

    private func confirmSend() {
        Task { [weak self] in
            guard let self else { return }
            let closed = await self.model.confirmPending()
            self.finishSend(closed: closed)
        }
    }

    private func finishSend(closed: Bool) {
        if closed {
            if let sent = model.lastSentCommand {
                usage.recordRun(
                    sent, appName: model.targetApp?.name, appBundleID: model.targetApp?.bundleID,
                    contextKinds: context.senseKinds)
            }
            hide(immediately: true)
        } else if !panel.isVisible {
            // A folder chooser or the Share menu took focus and the panel went away; bring it back where it was.
            reopenWithError()
        }
    }

    /// Closes the panel first so the key window goes back to the app underneath, then presses the item. If that fails
    /// the panel comes back with the reason.
    private func run(_ command: Command) {
        if model.isSendRow(command) || model.isSequenceRow(command) {
            runSend(command)
            return
        }
        hide(immediately: true)
        let appName = model.targetApp?.name
        let appBundleID = model.targetApp?.bundleID
        let kinds = context.senseKinds
        // What was typed to find it: the panel learns the person's own short names for commands.
        let typed = model.query
        Task { [weak self] in
            guard let self else { return }
            let closed = await self.model.run(command)
            if closed {
                self.usage.recordRun(
                    command, appName: appName, appBundleID: appBundleID, contextKinds: kinds, query: typed)
            }
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
