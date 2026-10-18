import AppKit
import Apropos
import Observation

extension Notification.Name {
    /// Posted each time the palette opens, so the onboarding can tell the person that the shortcut worked.
    static let aproposPanelOpened = Notification.Name("com.zawalid.apropos.panel.opened")
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, permission, tryIt, done
}

/// What the onboarding window shows and where it is. The permission step is left out when access is already granted,
/// unless the window was opened for that step on purpose.
@MainActor
@Observable
final class OnboardingModel {
    let permission: AccessibilityPermission
    /// What the stage shows of the person's Mac: the app in front, its commands, the keys held.
    let live: OnboardingLive
    private(set) var steps: [OnboardingStep]
    private(set) var index = 0
    private(set) var panelOpened: Bool
    var showsHelp: Bool
    private(set) var copiedPath = false

    @ObservationIgnored private let hotKeyProvider: () -> HotKeyCombo
    @ObservationIgnored private let finishAction: () -> Void
    @ObservationIgnored private var panelObserver: NSObjectProtocol?

    init(
        permission: AccessibilityPermission, hotKey: @escaping () -> HotKeyCombo, start: OnboardingStep? = nil,
        panelOpened: Bool = false, showsHelp: Bool = false, live: OnboardingLive? = nil,
        finish: @escaping () -> Void = {}
    ) {
        self.permission = permission
        self.live = live ?? .live()
        hotKeyProvider = hotKey
        finishAction = finish
        self.panelOpened = panelOpened
        self.showsHelp = showsHelp
        let skipPermission = permission.isTrusted && start != .permission
        steps = OnboardingStep.allCases.filter { !(skipPermission && $0 == .permission) }
        if let start, let position = steps.firstIndex(of: start) { index = position }
        panelObserver = NotificationCenter.default.addObserver(
            forName: .aproposPanelOpened, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelOpened = true }
        }
    }

    var step: OnboardingStep { steps[index] }
    var hotKey: HotKeyCombo { hotKeyProvider() }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == steps.count - 1 }
    var bundlePath: String { Bundle.main.bundlePath }

    /// What the primary button says. The permission step asks for access until it has been given.
    var primaryTitle: String {
        switch step {
        case .welcome: "Continue"
        case .permission: permission.isTrusted ? "Continue" : "Open System Settings"
        case .tryIt: panelOpened ? "Continue" : "Skip"
        case .done: "Finish"
        }
    }

    var primaryIsAccent: Bool {
        switch step {
        case .welcome, .done: true
        case .permission: true
        case .tryIt: panelOpened
        }
    }

    func primary() {
        switch step {
        case .permission where !permission.isTrusted:
            permission.requestPrompt()
            permission.openSystemSettings()
        case .done:
            finish()
        default:
            next()
        }
    }

    func next() {
        guard !isLast else { return }
        index += 1
    }

    func back() {
        guard !isFirst else { return }
        index -= 1
    }

    func finish() {
        stopObserving()
        finishAction()
    }

    func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bundlePath, forType: .string)
        copiedPath = true
    }

    func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bundlePath)])
    }

    func stopObserving() {
        live.stop()
        if let panelObserver { NotificationCenter.default.removeObserver(panelObserver) }
        panelObserver = nil
    }
}
