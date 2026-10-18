import AppKit
import Cue
import SwiftUI

/// Owns the palette panel: builds it once, so opening is just ordering a ready window to the front, and shows, hides and
/// positions it.
@MainActor
final class PanelController: NSObject {
    private let panel = PalettePanel()
    private let state = PanelState()
    private let model: PaletteModel
    private var hideGeneration = 0
    private var resignObserver: NSObjectProtocol?

    var isVisible: Bool { panel.isVisible && state.isPresented }

    init(model: PaletteModel, tracker: FrontmostAppTracker, permission: AccessibilityPermission) {
        self.model = model
        super.init()

        let root = PaletteView(
            model: model, state: state, permission: permission,
            actions: PaletteActions(
                run: { [weak self] in self?.runSelected() },
                runCommand: { [weak self] command in self?.run(command) },
                close: { [weak self] in self?.hide() }))
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: PanelPlacement.size)
        panel.contentView = hosting
        panel.setContentSize(PanelPlacement.size)

        panel.keyHandler = { [weak self] key in self?.handle(key) ?? false }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        hideGeneration += 1
        model.prepareForOpen()
        position()
        state.isPresented = false
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        state.focusToken += 1
        CueLog.panel.info("show target=\(self.model.targetApp?.name ?? "none") commands=\(self.model.results.count)")
        #if DEBUG
        DebugSnapshot.scheduleIfRequested(of: panel, model: model)
        #endif
        // The window is up already; the content eases in on the next turn of the run loop so the spring is visible.
        DispatchQueue.main.async { [state] in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { state.isPresented = true }
        }
    }

    /// Fades the content out and takes the window away. `immediately` skips the fade, for when a command is about to run
    /// in the app underneath and must not wait for it.
    func hide(immediately: Bool = false) {
        guard panel.isVisible else { return }
        hideGeneration += 1
        let generation = hideGeneration
        if immediately {
            state.isPresented = false
            panel.orderOut(nil)
            return
        }
        withAnimation(.easeOut(duration: 0.12)) { state.isPresented = false }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(130))
            guard let self, self.hideGeneration == generation else { return }
            self.panel.orderOut(nil)
        }
    }

    private func position() {
        let screens = NSScreen.screens
        let mouse = NSEvent.mouseLocation
        let index = PanelPlacement.index(containing: mouse, in: screens.map(\.frame))
        guard let index else { return }
        panel.setFrame(PanelPlacement.frame(in: screens[index].visibleFrame), display: false)
    }

    private func handle(_ key: PaletteKey) -> Bool {
        switch key {
        case .close: hide()
        case .run: runSelected()
        case .move(let delta): model.moveSelection(by: delta)
        case .first: model.selectFirst()
        case .last: model.selectLast()
        }
        return true
    }

    private func runSelected() {
        guard let command = model.selected?.command else { return }
        run(command)
    }

    /// Closes the panel first so the key window goes back to the app underneath, then presses the item. If that fails
    /// the panel comes back with the reason.
    private func run(_ command: Command) {
        hide(immediately: true)
        Task { [weak self] in
            guard let self else { return }
            let closed = await self.model.run(command)
            CueLog.panel.info("ran \(command.breadcrumb) > \(command.title) ok=\(closed)")
            if !closed { self.reopenWithError() }
        }
    }

    private func reopenWithError() {
        hideGeneration += 1
        position()
        state.isPresented = true
        panel.makeKeyAndOrderFront(nil)
        state.focusToken += 1
    }
}
