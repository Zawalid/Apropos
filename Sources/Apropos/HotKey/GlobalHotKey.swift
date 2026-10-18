import Carbon.HIToolbox
import Foundation

/// Registers one system-wide shortcut with Carbon, which needs no extra permission and fires even when another app is
/// frontmost. Re-registering replaces the previous shortcut.
@MainActor
public final class GlobalHotKey {
    public private(set) var combo: HotKeyCombo?
    /// False when macOS refused the shortcut, usually because another app already owns it.
    public private(set) var isRegistered = false

    private let handler: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private static var eventHandler: EventHandlerRef?
    private static var live: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private static let signature: OSType = 0x4355_4531  // "CUE1"
    private var id: UInt32 = 0

    public init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @discardableResult
    public func register(_ combo: HotKeyCombo) -> Bool {
        unregister()
        self.combo = combo
        Self.installEventHandlerIfNeeded()

        id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            CueLog.hotKey.error("could not register \(combo.display): \(status)")
            isRegistered = false
            return false
        }
        hotKeyRef = ref
        Self.live[id] = self
        isRegistered = true
        CueLog.hotKey.info("registered \(combo.display)")
        return true
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        Self.live[id] = nil
        isRegistered = false
    }

    private static func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard status == noErr else { return status }
                // Application events are delivered on the main thread.
                MainActor.assumeIsolated { GlobalHotKey.live[hotKeyID.id]?.handler() }
                return noErr
            }, 1, &spec, nil, &eventHandler)
    }
}
