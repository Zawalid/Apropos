import AppKit
import Apropos

/// A see-through window over the screen that draws the dashed blue lines the panel snaps to while it is dragged.
@MainActor
final class SnapGuides {
    private let window: NSPanel
    private let view = GuideView()

    init() {
        window = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        window.contentView = view
    }

    func show(_ guides: [PanelPlacement.Guide], in screenFrame: CGRect) {
        guard !guides.isEmpty else { return hide() }
        window.setFrame(screenFrame, display: false)
        view.frame = NSRect(origin: .zero, size: screenFrame.size)
        view.guides = guides.map { guide in
            switch guide.axis {
            case .vertical: .init(axis: .vertical, position: guide.position - screenFrame.minX)
            case .horizontal: .init(axis: .horizontal, position: guide.position - screenFrame.minY)
            }
        }
        view.needsDisplay = true
        if !window.isVisible { window.orderFrontRegardless() }
        AgentMode.conceal(window)
    }

    func hide() {
        if window.isVisible { window.orderOut(nil) }
    }

    private final class GuideView: NSView {
        var guides: [PanelPlacement.Guide] = []

        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemBlue.withAlphaComponent(0.85).setStroke()
            for guide in guides {
                let path = NSBezierPath()
                switch guide.axis {
                case .vertical:
                    path.move(to: NSPoint(x: guide.position, y: 0))
                    path.line(to: NSPoint(x: guide.position, y: bounds.height))
                case .horizontal:
                    path.move(to: NSPoint(x: 0, y: guide.position))
                    path.line(to: NSPoint(x: bounds.width, y: guide.position))
                }
                path.lineWidth = 1.5
                path.setLineDash([7, 6], count: 2, phase: 0)
                path.stroke()
            }
        }
    }
}

extension NSScreen {
    /// A stable name for this display, so a position is remembered for it and not for whichever screen is first.
    var displayKey: String {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let number, let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
            let text = CFUUIDCreateString(nil, uuid) as String?
        else { return localizedName }
        return text
    }
}
