import AppKit
import ApplicationServices
import Foundation

extension LiveAXNode: ComparableAXNode {
    func isSameElement(as other: any AXNode) -> Bool {
        guard let other = other as? LiveAXNode else { return false }
        return CFEqual(element, other.element)
    }
}

/// Finds the element under the pointer through the Accessibility API. This is the only place the recorder reads another
/// app's UI, and it runs only for a left click while a recording is on.
///
/// Never created by tests: it would read the real screen.
public struct LiveHitTester: ElementHitTester {
    public init() {}

    public func hitTest(at point: CGPoint) -> HitElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        var found: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &found)
        guard status == .success, let element = found else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.25)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        return HitClassifier.classify(LiveAXNode(element: element), pid: pid, bundleID: bundleID)
    }

    public func textFocus(in app: AppIdentity) -> TextFocus {
        let application = LiveAXNode.application(pid: app.pid, timeout: 0.2)
        return HitClassifier.focus(of: application.node(HitAX.focusedElement))
    }
}
