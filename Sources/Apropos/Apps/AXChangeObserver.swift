import ApplicationServices
import Foundation

/// Watches one app for the changes that can alter its menus (another window or document in front) through an
/// AXObserver on the main run loop, and calls `onChange` for each.
@MainActor
final class AXChangeObserver {
    private static let notifications: [String] = [
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXWindowCreatedNotification,
        kAXTitleChangedNotification,
        kAXMenuClosedNotification,
    ]

    private var observer: AXObserver?
    private let context: Context
    private let appElement: AXUIElement

    /// Boxed so the C callback can find the closure again from its refcon pointer.
    final class Context {
        let onChange: @MainActor () -> Void
        init(onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    }

    init?(pid: pid_t, onChange: @escaping @MainActor () -> Void) {
        context = Context(onChange: onChange)
        appElement = AXUIElementCreateApplication(pid)

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let context = Unmanaged<Context>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { context.onChange() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return nil }
        observer = created

        let refcon = Unmanaged.passUnretained(context).toOpaque()
        var added = 0
        for name in Self.notifications
        where AXObserverAddNotification(created, appElement, name as CFString, refcon) == .success {
            added += 1
        }
        guard added > 0 else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
    }

    func stop() {
        guard let observer else { return }
        for name in Self.notifications { AXObserverRemoveNotification(observer, appElement, name as CFString) }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
    }

    deinit {
        // `stop` is main-actor isolated; the observer is released with the object, which removes its source.
    }
}
