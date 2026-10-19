import AppKit

/// What a key press means to the palette.
enum PaletteKey {
    case close
    case run
    /// Command-Return: run the first Usually next row, whatever is highlighted.
    case runPrediction
    case move(Int)
    case first
    case last
    case actions
    case settings
    /// Shift-Return: open the real menu the highlighted item lives in.
    case showMenu
    /// Backspace (query empty) or Command-Backspace: delete the highlighted step of the sequence draft.
    case deleteStep(command: Bool)
    /// Option-Up or Option-Down: move the highlighted step of the sequence draft.
    case moveStep(Int)
}

/// The floating window the palette lives in. It is a non-activating panel, so opening it never takes focus from the
/// app the person is working in, which is what keeps that app the target.
final class PalettePanel: NSPanel {
    /// Returns true when the key was used.
    var keyHandler: ((PaletteKey) -> Bool)?
    /// Given the frame a drag would give the panel, returns the frame to use: snapped and kept on screen.
    var dragAdjust: ((CGRect) -> CGRect)?
    /// Called with the final frame when a drag ends.
    var dragEnded: ((CGRect) -> Void)?
    /// How much of the top of the panel can be grabbed to move it.
    private let grabHeight: CGFloat = 64
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var isDragging = false

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 680, height: 460)),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false  // moved by our own drag, which snaps
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragStart = canGrab(event) ? (NSEvent.mouseLocation, frame.origin) : nil
            isDragging = false
        case .leftMouseDragged:
            if let start = dragStart {
                let mouse = NSEvent.mouseLocation
                let dx = mouse.x - start.mouse.x
                let dy = mouse.y - start.mouse.y
                if isDragging || hypot(dx, dy) > 4 {
                    isDragging = true
                    var proposed = frame
                    proposed.origin = NSPoint(x: start.origin.x + dx, y: start.origin.y + dy)
                    setFrame(dragAdjust?(proposed) ?? proposed, display: true)
                    return
                }
            }
        case .leftMouseUp:
            let wasDragging = isDragging
            dragStart = nil
            isDragging = false
            if wasDragging {
                dragEnded?(frame)
                return
            }
        default:
            break
        }
        if event.type == .keyDown, let key = Self.key(for: event), !isComposingText, keyHandler?(key) == true {
            return
        }
        super.sendEvent(event)
    }

    /// A press in the top strip that is not on the search text, so clicking and selecting text still work.
    private func canGrab(_ event: NSEvent) -> Bool {
        let point = event.locationInWindow
        guard point.y >= frame.height - grabHeight else { return false }
        var view = contentView?.hitTest(point)
        while let current = view {
            if current is NSText || current is NSTextField { return false }
            view = current.superview
        }
        return true
    }

    /// A Return pressed while an input method has marked text confirms the text; it must not run a command.
    private var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    private static func key(for event: NSEvent) -> PaletteKey? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let onlyControl = flags == .control
        switch event.keyCode {
        case 53 where flags.isEmpty: return .close
        case 36 where flags == .shift: return .showMenu
        case 36 where flags == .command, 76 where flags == .command: return .runPrediction
        case 36,
            76 where flags.isEmpty:
            return .run
        case 51 where flags.isEmpty: return .deleteStep(command: false)
        case 51 where flags == .command: return .deleteStep(command: true)
        case 125 where flags == .option: return .moveStep(1)
        case 126 where flags == .option: return .moveStep(-1)
        case 125 where flags.isEmpty: return .move(1)
        case 126 where flags.isEmpty: return .move(-1)
        case 40 where flags == .command: return .actions  // command-K
        case 43 where flags == .command: return .settings  // command-comma
        case 125 where flags == .command: return .last
        case 126 where flags == .command: return .first
        case 48 where flags.isEmpty: return .move(1)
        case 48 where flags == .shift: return .move(-1)
        case 121 where flags.isEmpty: return .move(8)
        case 116 where flags.isEmpty: return .move(-8)
        case 45 where onlyControl: return .move(1)  // control-N
        case 35 where onlyControl: return .move(-1)  // control-P
        case 38 where onlyControl: return .move(1)  // control-J
        case 40 where onlyControl: return .move(-1)  // control-K
        default: return nil
        }
    }
}
