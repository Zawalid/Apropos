import ApplicationServices
import CoreGraphics
import Foundation

/// One permission a recording needs.
public enum RecordingPermissionKind: String, CaseIterable, Sendable, Identifiable {
    case accessibility
    case inputMonitoring

    public var id: String { rawValue }

    /// The name as System Settings shows it.
    public var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    /// What this permission lets Apropos do, in one sentence a person can weigh.
    public var whatItAllows: String {
        switch self {
        case .accessibility:
            "Lets Apropos look at which menu item or control is under your pointer, and read the menus of the app you are using."
        case .inputMonitoring:
            "Lets Apropos be told that a mouse button or a key was pressed while you record. It cannot change or block anything you do."
        }
    }

    /// Why a recording asks for it.
    public var whyRecording: String {
        switch self {
        case .accessibility:
            "To turn a click into the name of a menu item, and a keyboard shortcut into the menu item it triggers."
        case .inputMonitoring:
            "To notice the moment you click or press a shortcut, so the item under the pointer is read before the screen changes."
        }
    }

    /// The Privacy and Security pane that holds the switch.
    public var settingsURL: URL? {
        switch self {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .inputMonitoring:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        }
    }
}

/// The words a recording UI shows to explain what it is about to ask for. Fixed sentences, so a screen and a test
/// agree on exactly what the person is told.
public enum RecordingPermissionCopy {
    public static let headline = "Recording needs two permissions"

    public static let summary =
        "Apropos watches only while you record. It notes which menu items you choose and which keyboard shortcuts you use, "
        + "and turns them into steps you can review before anything is saved."

    /// What is never stored. Shown next to the request, because this is what makes the request acceptable.
    public static let neverStored: [String] = [
        "The letters you type. Typing is noted as \"text was entered\" with nothing else.",
        "Passwords. Recording pauses while a password field is active.",
        "Where you clicked on the screen. Only the menu item or control is noted.",
        "Screenshots, the clipboard, or anything that leaves this Mac.",
    ]

    public static let notRequested =
        "Apropos does not prompt for these by itself. macOS asks only when you press the button that requests them."

    /// What to say when something is missing.
    public static func missing(_ kinds: [RecordingPermissionKind]) -> String {
        switch kinds.count {
        case 0: return "Everything needed to record is allowed."
        case 1: return "Recording also needs \(kinds[0].title). Allow it in System Settings, then try again."
        default:
            return "Recording needs \(kinds.map(\.title).joined(separator: " and ")). "
                + "Allow them in System Settings, then try again."
        }
    }
}

/// The two answers macOS can give, read without ever showing a prompt.
public protocol RecordingPermissionBackend: Sendable {
    func accessibilityGranted() -> Bool
    func inputMonitoringGranted() -> Bool
    /// Shows macOS's own Accessibility prompt. Only ever called from an explicit request.
    func requestAccessibility()
    /// Shows macOS's own Input Monitoring prompt. Only ever called from an explicit request.
    func requestInputMonitoring()
}

public struct LiveRecordingPermissionBackend: RecordingPermissionBackend {
    public init() {}

    public func accessibilityGranted() -> Bool { AXIsProcessTrusted() }

    public func inputMonitoringGranted() -> Bool { CGPreflightListenEventAccess() }

    public func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func requestInputMonitoring() { _ = CGRequestListenEventAccess() }
}

/// Which permissions a recording has.
public struct RecordingPermissionStatus: Equatable, Sendable {
    public let accessibility: Bool
    public let inputMonitoring: Bool

    public init(accessibility: Bool, inputMonitoring: Bool) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }

    public var canRecord: Bool { accessibility && inputMonitoring }

    /// What is still missing, in the order a person should grant it.
    public var missing: [RecordingPermissionKind] {
        var kinds: [RecordingPermissionKind] = []
        if !accessibility { kinds.append(.accessibility) }
        if !inputMonitoring { kinds.append(.inputMonitoring) }
        return kinds
    }

    public func isGranted(_ kind: RecordingPermissionKind) -> Bool {
        switch kind {
        case .accessibility: accessibility
        case .inputMonitoring: inputMonitoring
        }
    }
}

/// Reports whether recording is allowed. Reading the state never prompts; requesting is a separate, explicit call.
public struct RecordingPermission: Sendable {
    private let backend: any RecordingPermissionBackend

    public init(backend: any RecordingPermissionBackend = LiveRecordingPermissionBackend()) {
        self.backend = backend
    }

    public func status() -> RecordingPermissionStatus {
        RecordingPermissionStatus(
            accessibility: backend.accessibilityGranted(), inputMonitoring: backend.inputMonitoringGranted())
    }

    /// Asks macOS for one permission. Call it only from a button the person pressed.
    public func request(_ kind: RecordingPermissionKind) {
        switch kind {
        case .accessibility: backend.requestAccessibility()
        case .inputMonitoring: backend.requestInputMonitoring()
        }
    }
}
