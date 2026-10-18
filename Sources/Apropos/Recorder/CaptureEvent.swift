import CoreGraphics
import Foundation

/// An app, as the recorder needs to know it.
public struct AppIdentity: Equatable, Hashable, Sendable {
    public let pid: Int32
    public let bundleID: String
    public let name: String

    public init(pid: Int32, bundleID: String, name: String) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
    }
}

/// A key press reduced to what a shortcut needs: which physical key and which modifiers. It carries no character. The
/// key code is turned into a shortcut candidate in memory only to compare it with the frontmost app's menu key
/// equivalents, and a chord that matches nothing is dropped on the spot.
///
/// It describes and reflects as nothing at all, so a log line, a `dump` or an error message cannot show it.
public struct KeyChord: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let keyCode: UInt16
    public let modifiers: ModifierSet

    public init(keyCode: UInt16, modifiers: ModifierSet) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var description: String { "key event" }
    public var debugDescription: String { "key event" }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// Something the recorder is told about. The source has already thrown away everything the recorder must not see:
/// there is no character in a key event, and a mouse event is only a point to hit test.
public enum CaptureEvent: Sendable {
    /// A left mouse button went down at this point. The point is used once, to find the element, and never stored.
    case mouseDown(CGPoint)
    case keyDown(KeyChord)
    /// A modifier key changed. Dropped at once; it exists so a source can report it without special cases.
    case flagsChanged
    /// The frontmost app changed.
    case appActivated(AppIdentity)
    /// Time passed. Sent a few times a second so limits, secure input and the Apropos check work without input.
    case tick
}

/// Where events come from: a listen-only event tap in the app, a fake in tests.
public protocol CaptureEventSource: AnyObject, Sendable {
    /// Starts delivering events. Throws `CaptureSourceError` when it cannot.
    func start(handler: @escaping @Sendable (CaptureEvent) -> Void) throws
    /// Stops delivering. Safe to call more than once.
    func stop()
}

public enum CaptureSourceError: Error, Equatable, Sendable {
    /// macOS refused to create the tap, normally because Input Monitoring is not allowed.
    case tapUnavailable
}
