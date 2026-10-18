import CoreGraphics
import Foundation

/// What is under the pointer, as plain values. The live hit tester fills it from the Accessibility API; tests build it
/// directly. Nothing here is stored in a draft except what a step already holds.
public struct HitElement: Equatable, Sendable {
    /// Where the element sits.
    public enum Place: Equatable, Sendable {
        /// A title in the app's menu bar ("File" itself).
        case menuBarTitle(barIndex: Int)
        /// An item of a menu opened from the app's menu bar. `path` is the menus down to the item, then its own title.
        case menuItem(path: [String], barIndex: Int, ancestorIdentifiers: [String], hasSubmenu: Bool)
        /// An item of a context or popup menu, which has no place in the menu bar.
        case contextMenuItem
        /// A status item on the right of the menu bar: another process's, not the app's.
        case menuExtra
        /// Anything in a window.
        case window
    }

    public var pid: Int32
    public var bundleID: String?
    public var role: String
    public var subrole: String
    public var title: String
    public var identifier: String
    public var isEnabled: Bool
    public var place: Place

    public init(
        pid: Int32, bundleID: String?, role: String = "", subrole: String = "", title: String = "",
        identifier: String = "", isEnabled: Bool = true, place: Place
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.role = role
        self.subrole = subrole
        self.title = title
        self.identifier = identifier
        self.isEnabled = isEnabled
        self.place = place
    }

    var isSecure: Bool { role == StepText.secureRole || subrole == StepText.secureRole }

    /// Whether anything about the element could be used to find it again without its position.
    var isAddressable: Bool {
        !identifier.isEmpty || !title.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// What has the keyboard focus in an app, as far as the recorder cares.
public enum TextFocus: Equatable, Sendable {
    case secure
    case textInput
    case other
    /// The app would not say (an Electron app without its accessibility tree, a hung app).
    case unknown
}

/// Reads the element under the pointer and the focus. The only part of the recorder that talks to other apps.
public protocol ElementHitTester: Sendable {
    func hitTest(at point: CGPoint) -> HitElement?
    func textFocus(in app: AppIdentity) -> TextFocus
}

/// The state of the machine the recorder asks about.
public protocol RecordingSystem: Sendable {
    /// A monotonic clock in seconds.
    func now() -> TimeInterval
    func frontmostApp() -> AppIdentity?
    /// `IsSecureEventInputEnabled()`: some app has a password field or Secure Keyboard Entry active.
    func isSecureEventInputOn() -> Bool
}

/// Reads the menu items of an app, with the key each advertises. Never lists the Apple menu or recent items.
public protocol MenuInspecting: Sendable {
    func menuItems(of app: AppIdentity) -> [StepResolver.MenuItemInfo]
}

/// Everything the recorder asks the outside world.
public struct RecordingServices: Sendable {
    public var system: any RecordingSystem
    public var hitTester: any ElementHitTester
    public var menus: any MenuInspecting
    public var keyLayout: any KeyLayout

    public init(
        system: any RecordingSystem, hitTester: any ElementHitTester, menus: any MenuInspecting,
        keyLayout: any KeyLayout
    ) {
        self.system = system
        self.hitTester = hitTester
        self.menus = menus
        self.keyLayout = keyLayout
    }
}
