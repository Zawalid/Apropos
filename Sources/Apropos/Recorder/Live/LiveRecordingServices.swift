import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// The clock, the frontmost app and secure input, read from the system. Reading them touches no other app.
public struct LiveRecordingSystem: RecordingSystem {
    public init() {}

    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    public func frontmostApp() -> AppIdentity? {
        NSWorkspace.shared.frontmostApplication.flatMap(AppIdentity.init(running:))
    }

    public func isSecureEventInputOn() -> Bool { IsSecureEventInputEnabled() }
}

extension AppIdentity {
    /// Nil for a process with no bundle identifier, which no step can name.
    init?(running app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return nil }
        self.init(
            pid: app.processIdentifier, bundleID: bundleID, name: app.localizedName ?? bundleID)
    }
}

/// Reads an app's menu bar through the step resolver, with a short deadline so a hung app cannot stall a key press.
public struct LiveMenuInspector: MenuInspecting {
    public var deadline: TimeInterval

    public init(deadline: TimeInterval = 0.6) { self.deadline = deadline }

    public func menuItems(of app: AppIdentity) -> [StepResolver.MenuItemInfo] {
        let started = ProcessInfo.processInfo.systemUptime
        let limit = deadline
        let resolver = StepResolver(
            budget: ResolveBudget(isExpired: { ProcessInfo.processInfo.systemUptime - started > limit }))
        return resolver.menuItems(in: LiveAXNode.application(pid: app.pid, timeout: 0.3))
    }
}

/// The base character of each key on the current ASCII-capable layout, read once when the recorder is built.
///
/// macOS requires the keyboard layout APIs to run on the main thread, so the table is built here, up front, and a
/// layout change during a recording is not noticed. The table maps key codes to the characters printed on the keys; it
/// has nothing to do with what is typed.
public struct LiveKeyLayout: KeyLayout {
    private let table: [UInt16: String]

    @MainActor
    public init() {
        var built: [UInt16: String] = [:]
        if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        {
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
            let keyboardType = UInt32(LMGetKbdType())
            let bytes = CFDataGetBytePtr(data)
            for code in UInt16(0)...127 {
                var deadKeys: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = bytes?.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
                    UCKeyTranslate(
                        layout, code, UInt16(kUCKeyActionDown), 0, keyboardType,
                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
                }
                if status == noErr, length > 0 {
                    built[code] = String(utf16CodeUnits: characters, count: length)
                }
            }
        }
        self.table = built
    }

    public func baseCharacter(forKeyCode keyCode: UInt16) -> String? {
        table[keyCode] ?? USKeyLayout().baseCharacter(forKeyCode: keyCode)
    }
}
