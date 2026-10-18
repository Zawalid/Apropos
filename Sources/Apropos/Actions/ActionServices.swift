import AppKit
import ApplicationServices
import Foundation
import UserNotifications

public enum ReplaceResult: Sendable, Equatable {
    case replaced
    case pasted
    /// The focused element is not something text can be put into.
    case notEditable
    case failed
}

/// Everything an action does to the outside world, as replaceable closures, so tests run without touching the
/// clipboard, opening URLs or posting key events. `ActionServices.live` is the real thing.
public struct ActionServices: Sendable {
    public var process: @Sendable (ProcessRequest) async throws -> ProcessOutput
    public var openURL: @Sendable (URL) async -> Bool
    public var copyToClipboard: @Sendable (String) async -> Void
    public var notify: @Sendable (String) async -> Void
    public var postKey: @Sendable (KeyPressBackend) async -> Bool
    public var replaceSelection: @Sendable (_ text: String, _ pid: pid_t) async -> ReplaceResult
    public var uiSteps: UIStepsExecutor

    public init(
        process: @escaping @Sendable (ProcessRequest) async throws -> ProcessOutput,
        openURL: @escaping @Sendable (URL) async -> Bool,
        copyToClipboard: @escaping @Sendable (String) async -> Void,
        notify: @escaping @Sendable (String) async -> Void,
        postKey: @escaping @Sendable (KeyPressBackend) async -> Bool,
        replaceSelection: @escaping @Sendable (String, pid_t) async -> ReplaceResult,
        uiSteps: UIStepsExecutor = .live
    ) {
        self.process = process
        self.openURL = openURL
        self.copyToClipboard = copyToClipboard
        self.notify = notify
        self.postKey = postKey
        self.replaceSelection = replaceSelection
        self.uiSteps = uiSteps
    }

    public static let live = ActionServices(
        process: { try await ProcessRunner.run($0) },
        openURL: { url in await MainActor.run { NSWorkspace.shared.open(url) } },
        copyToClipboard: { text in
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        },
        notify: { await LiveNotifier.shared.post($0) },
        postKey: { LiveKeyboard.post($0) },
        replaceSelection: { text, pid in await LiveSelectionReplacer.replace(text, inProcess: pid) })
}

/// Posts keyboard events. Needs Accessibility; without it nothing is sent and the call reports false.
enum LiveKeyboard {
    static func post(_ key: KeyPressBackend) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        var flags = CGEventFlags()
        if key.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if key.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if key.modifiers.contains(.shift) { flags.insert(.maskShift) }
        if key.modifiers.contains(.control) { flags.insert(.maskControl) }
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key.keyCode), keyDown: isDown)
            else { return false }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}

/// Replaces the selection of another app: through Accessibility when the focused element lets the selected text be
/// set, else by pasting with the clipboard put back afterwards.
enum LiveSelectionReplacer {
    private static let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    static func replace(_ text: String, inProcess pid: pid_t) async -> ReplaceResult {
        guard AXIsProcessTrusted() else { return .failed }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
            let focusedRef, let focused = AXMenuReader.element(focusedRef)
        else { return .failed }

        if isSecure(focused) { return .notEditable }
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute as CFString, &settable) == .success,
            settable.boolValue,
            AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFString) == .success
        {
            return .replaced
        }
        guard isEditable(focused) else { return .notEditable }
        return await paste(text) ? .pasted : .failed
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        attribute(element, kAXSubroleAttribute) == "AXSecureTextField"
            || attribute(element, kAXRoleAttribute) == "AXSecureTextField"
    }

    private static func isEditable(_ element: AXUIElement) -> Bool {
        guard let role = attribute(element, kAXRoleAttribute) else { return false }
        return editableRoles.contains(role)
    }

    /// Puts `text` on the clipboard, sends Command-V, then restores what was there, unless something else wrote to the
    /// clipboard in the meantime.
    @MainActor
    private static func paste(_ text: String) async -> Bool {
        let board = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        board.clearContents()
        board.setString(text, forType: .string)
        let ours = board.changeCount
        let sent = LiveKeyboard.post(KeyPressBackend(keyCode: 9, modifiers: [.command]))
        try? await Task.sleep(for: .milliseconds(300))
        if board.changeCount == ours {
            board.clearContents()
            let restored = saved.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            if !restored.isEmpty { board.writeObjects(restored) }
        }
        return sent
    }
}

/// Short notifications through the notification center. Does nothing outside an app bundle (tests, the probe), and
/// nothing until the person has allowed notifications.
final class LiveNotifier: @unchecked Sendable {
    static let shared = LiveNotifier()

    func post(_ text: String) async {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert])
        }
        let content = UNMutableNotificationContent()
        content.title = "Apropos"
        content.body = text
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
