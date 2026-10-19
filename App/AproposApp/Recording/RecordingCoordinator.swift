import AppKit
import Apropos
import Carbon.HIToolbox
import SwiftUI

/// Owns what a recording puts on screen: the permission window, the floating bar and the stop shortcut. The model
/// decides what is true; this decides where it is drawn. It follows the model with a timer that runs only while a
/// recording, a permission screen or a result is showing.
@MainActor
final class RecordingCoordinator {
    /// Control-Option-Command-R stops a recording from any app. It is registered only while recording.
    static let stopCombo = HotKeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option, .command])

    let model: RecordingModel
    private let openDraft: () -> Void
    private let shortcutRecording: (Bool) -> Void
    private var reviewWindow: NSWindow?
    private var bar: NSPanel?
    private var permissionWindow: NSWindow?
    private var timer: Timer?
    private var stopKey: GlobalHotKey?
    private var shownPhase: RecordingModel.Phase = .idle
    private var autoDismiss: Task<Void, Never>?

    init(
        model: RecordingModel, openDraft: @escaping () -> Void, shortcutRecording: @escaping (Bool) -> Void = { _ in }
    ) {
        self.model = model
        self.openDraft = openDraft
        self.shortcutRecording = shortcutRecording
    }

    private var actions: RecordingActions {
        RecordingActions(
            stop: { [weak self] in self?.stop() }, cancel: { [weak self] in self?.cancel() },
            openDraft: { [weak self] in
                self?.model.dismissOutcome()
                self?.sync()
                self?.openDraft()
            },
            dismiss: { [weak self] in
                self?.model.dismissOutcome()
                self?.model.dismiss()
                self?.sync()
            },
            allow: { [weak self] in self?.model.allow($0) },
            start: { [weak self] in self?.begin() },
            saveReview: { [weak self] in
                self?.model.saveReview()
                self?.sync()
            },
            addReviewToDraft: { [weak self] in
                self?.model.addReviewToDraft()
                self?.sync()
            },
            discardReview: { [weak self] in
                self?.model.discardReview()
                self?.sync()
            })
    }

    // MARK: Entry

    /// The one way in: starts recording, or shows the permission screen when something is missing.
    func begin() {
        model.start()
        sync()
        startTimer()
    }

    func stop() {
        model.stop()
        sync()
    }

    func cancel() {
        model.cancel()
        sync()
    }

    // MARK: Following the model

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        model.refresh()
        sync()
        if model.phase == .idle {
            timer?.invalidate()
            timer = nil
        }
    }

    private func sync() {
        let phase = model.phase
        let changed = phase != shownPhase
        shownPhase = phase
        switch phase {
        case .idle:
            hideBar()
            hidePermission()
            hideReview()
            releaseStopKey()
        case .needsPermission:
            hideBar()
            showPermission()
            releaseStopKey()
        case .reviewing:
            hideBar()
            hidePermission()
            showReview()
            releaseStopKey()
        case .recording:
            hidePermission()
            if bar == nil || changed { showBar() }
            holdStopKey()
        case .finished, .failed:
            hidePermission()
            hideReview()
            releaseStopKey()
            if changed {
                showBar()
                autoDismiss?.cancel()
                autoDismiss = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(12))
                    guard !Task.isCancelled else { return }
                    self?.model.dismissOutcome()
                    self?.sync()
                }
            }
        }
    }

    // MARK: The stop shortcut

    private func holdStopKey() {
        guard stopKey == nil else { return }
        let key = GlobalHotKey { [weak self] in self?.stop() }
        _ = key.register(Self.stopCombo)
        stopKey = key
    }

    private func releaseStopKey() {
        stopKey?.unregister()
        stopKey = nil
    }

    // MARK: The bar

    private func showBar() {
        let panel = bar ?? makeBar()
        let hosting = NSHostingView(
            rootView: RecordingBarView(model: model, stopKeys: Self.stopCombo.caps, actions: actions))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        let size = hosting.fittingSize
        panel.setContentSize(size)
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 12))
        }
        bar = panel
        panel.orderFrontRegardless()
        AgentMode.conceal(panel)
    }

    private func hideBar() {
        autoDismiss?.cancel()
        bar?.orderOut(nil)
    }

    private func makeBar() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        return panel
    }

    // MARK: The review

    private func showReview() {
        guard let review = model.review else { return }
        let window = reviewWindow ?? makeReviewWindow()
        window.contentView = NSHostingView(
            rootView: RecordingReviewView(review: review, actions: actions, shortcutRecording: shortcutRecording))
        reviewWindow = window
        if !window.isVisible {
            if !AgentMode.isOn { NSApp.activate() }
            window.center()
            window.makeKeyAndOrderFront(nil)
            AgentMode.conceal(window)
        }
    }

    private func hideReview() {
        reviewWindow?.orderOut(nil)
    }

    private func makeReviewWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: RecordingReviewView.size),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Review recording"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        // The red button is the same as Discard: a recording is quick to make again.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.model.phase == .reviewing {
                    self?.model.discardReview()
                    self?.sync()
                }
            }
        }
        return window
    }

    // MARK: The permission screen

    private func showPermission() {
        let window = permissionWindow ?? makePermissionWindow()
        window.contentView = NSHostingView(rootView: RecordingPermissionView(model: model, actions: actions))
        permissionWindow = window
        if !window.isVisible {
            if !AgentMode.isOn { NSApp.activate() }
            window.center()
            window.makeKeyAndOrderFront(nil)
            AgentMode.conceal(window)
        }
    }

    private func hidePermission() {
        permissionWindow?.orderOut(nil)
    }

    private func makePermissionWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: RecordingPermissionView.size),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Recording"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        // Closing the window with its red button is the same as Not now.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.dismiss()
                self?.sync()
            }
        }
        return window
    }
}
