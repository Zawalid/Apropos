import AppKit

/// What a key press means to the palette.
enum PaletteKey {
    case close
    case run
    case move(Int)
    case first
    case last
    case actions
    case settings
}

/// The floating window the palette lives in. It is a non-activating panel, so opening it never takes focus from the
/// app the person is working in, which is what keeps that app the target.
final class PalettePanel: NSPanel {
    /// Returns true when the key was used.
    var keyHandler: ((PaletteKey) -> Bool)?

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
        isMovable = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let key = Self.key(for: event), !isComposingText, keyHandler?(key) == true {
            return
        }
        super.sendEvent(event)
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
        case 36,
            76 where flags.isEmpty:
            return .run
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
