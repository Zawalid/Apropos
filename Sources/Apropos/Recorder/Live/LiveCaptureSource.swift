import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// The real event source: a listen-only `CGEvent` tap for left mouse down, key down and modifier changes, the app
/// activation notification, and a half-second tick.
///
/// Privacy by construction: the tap callback reads the key code and the modifier flags of a key event and nothing else.
/// It never asks for the characters of a key event, so no character exists in this process to leak. The tap is
/// listen-only: it cannot change, delay or block anything the person does.
///
/// Nothing in the package or its tests creates one. `start` is the only call that touches the system, and it is made by
/// `Recorder.begin()` after the person pressed Record, or by `apropos-probe --record-live`.
public final class LiveCaptureSource: CaptureEventSource, @unchecked Sendable {
    /// The events the tap asks macOS for.
    static let eventMask: CGEventMask =
        (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.keyDown.rawValue)
        | (1 << CGEventType.flagsChanged.rawValue)

    static let tickInterval: TimeInterval = 0.5

    fileprivate final class Session: @unchecked Sendable {
        let handler: @Sendable (CaptureEvent) -> Void
        var tap: CFMachPort?
        var source: CFRunLoopSource?
        var runLoop: CFRunLoop?
        var observer: NSObjectProtocol?
        var timer: Timer?
        var isStopped = false
        init(handler: @escaping @Sendable (CaptureEvent) -> Void) { self.handler = handler }
    }

    private let lock = NSLock()
    private var session: Session?

    public init() {}

    public func start(handler: @escaping @Sendable (CaptureEvent) -> Void) throws {
        let new = Session(handler: handler)
        let unmanaged = Unmanaged.passRetained(new)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                eventsOfInterest: Self.eventMask, callback: liveTapCallback, userInfo: unmanaged.toOpaque())
        else {
            unmanaged.release()
            throw CaptureSourceError.tapUnavailable
        }
        let alreadyRunning = lock.withLock { () -> Bool in
            if session != nil { return true }
            session = new
            return false
        }
        if alreadyRunning {
            CFMachPortInvalidate(tap)
            unmanaged.release()
            return
        }
        new.tap = tap

        // The tap, the tick and the activation notification all live on one background thread's run loop, so a slow
        // Accessibility read never blocks the main thread.
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [new] in
            let runLoop = CFRunLoopGetCurrent()
            new.runLoop = runLoop
            guard let tap = new.tap else {
                ready.signal()
                return
            }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            new.source = source
            if let source { CFRunLoopAddSource(runLoop, source, .commonModes) }
            let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { _ in new.handler(.tick) }
            RunLoop.current.add(timer, forMode: .common)
            new.timer = timer
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "apropos.recorder"
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()

        new.observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
        ) { [new] note in
            guard !new.isStopped,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let identity = AppIdentity(running: app)
            else { return }
            new.handler(.appActivated(identity))
        }
    }

    public func stop() {
        let current = lock.withLock { () -> Session? in
            defer { session = nil }
            return session
        }
        guard let current else { return }
        current.isStopped = true
        if let observer = current.observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let tap = current.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        // Tear the rest down from outside the tap callback: stop() may be called from inside it.
        DispatchQueue.global(qos: .utility).async {
            current.timer?.invalidate()
            if let source = current.source, let runLoop = current.runLoop {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            if let tap = current.tap { CFMachPortInvalidate(tap) }
            if let runLoop = current.runLoop { CFRunLoopStop(runLoop) }
            Unmanaged.passUnretained(current).release()
        }
    }

    /// Called by the tap callback. Reduces the event to its key code and flags and hands it on.
    fileprivate static func deliver(type: CGEventType, event: CGEvent, to session: Session) {
        guard !session.isStopped else { return }
        switch type {
        case .leftMouseDown:
            session.handler(.mouseDown(event.location))
        case .keyDown:
            // Auto-repeat is a held key, not a new press.
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            session.handler(.keyDown(KeyChord(keyCode: code, modifiers: ModifierSet(flags: event.flags))))
        case .flagsChanged:
            session.handler(.flagsChanged)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = session.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        default:
            break
        }
    }
}

extension ModifierSet {
    init(flags: CGEventFlags) {
        var set = ModifierSet()
        if flags.contains(.maskControl) { set.insert(.control) }
        if flags.contains(.maskAlternate) { set.insert(.option) }
        if flags.contains(.maskShift) { set.insert(.shift) }
        if flags.contains(.maskCommand) { set.insert(.command) }
        self = set
    }
}

private func liveTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let session = Unmanaged<LiveCaptureSource.Session>.fromOpaque(userInfo).takeUnretainedValue()
        LiveCaptureSource.deliver(type: type, event: event, to: session)
    }
    return Unmanaged.passUnretained(event)
}
