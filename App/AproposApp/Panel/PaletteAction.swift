import AppKit
import Apropos

/// One entry of the Cmd+K popover.
struct PaletteAction: Identifiable {
    enum Kind: Equatable {
        case run
        case notNow
        case runAlternate(Int)
        case showMenu
        case pin(Bool)
        case hide
        case copyPath
        case copyShortcut
        /// Open Settings to give this menu item an alias and a shortcut of its own.
        case customizeItem
        /// Stop reminding of this item's keyboard shortcut.
        case muteTip
        case addToSequence
        /// Open Settings on one of your commands.
        case editCommand
        case duplicateCommand
        case deleteCommand
        case moveStep(Int)
        case deleteStep
        /// Ask for the step's text when the sequence runs (true), or go back to the chain (false).
        case askMe(Bool)
        /// Read the selection instead of the previous step's result (true), or go back to the chain (false).
        case useSelection(Bool)
        /// Go on with the next step when this one fails (true), or stop there (false).
        case continueOnFailure(Bool)
    }

    let kind: Kind
    let title: String
    let symbol: String
    let keys: [String]

    var id: String { "\(kind)-\(title)" }

    /// The actions available for a command, in display order.
    @MainActor
    static func available(
        for command: Command?, appName: String?, isPinned: Bool, isPredicted: Bool = false,
        hasTip: Bool = false, sequence: SequenceCenter? = nil
    ) -> [PaletteAction] {
        guard let command else { return [] }
        if case .sequence(let target) = command.source { return sequenceActions(for: target, sequence: sequence) }
        var list = [PaletteAction(kind: .run, title: "Run", symbol: "play", keys: ["↩"])]
        if case .app = command.source { return list }
        if PaletteModel.userCommandID(of: command) != nil {
            list.append(PaletteAction(kind: .editCommand, title: "Edit command", symbol: "slider.horizontal.3", keys: []))
            list.append(PaletteAction(kind: .duplicateCommand, title: "Duplicate", symbol: "plus.square.on.square", keys: []))
            list.append(PaletteAction(kind: .deleteCommand, title: "Delete", symbol: "trash", keys: []))
        }
        if canJoinSequence(command) {
            list.append(
                PaletteAction(
                    kind: .addToSequence, title: "Add to sequence", symbol: "plus.square.on.square", keys: []))
        }
        if command.target is MenuRevealing {
            list.append(PaletteAction(kind: .showMenu, title: "Show menu", symbol: "menubar.rectangle", keys: ["⇧", "↩"]))
        }
        if isPredicted {
            list.append(PaletteAction(kind: .notNow, title: "Not now", symbol: "moon.zzz", keys: []))
        }
        for (index, alternate) in command.alternates.enumerated() {
            list.append(
                PaletteAction(
                    kind: .runAlternate(index), title: CommandDisplay.cleanTitle(alternate.title),
                    symbol: "option", keys: alternate.shortcut?.caps ?? ["⌥"]))
        }
        list.append(
            PaletteAction(
                kind: .pin(!isPinned), title: isPinned ? "Unpin" : "Pin to top", symbol: isPinned ? "pin.slash" : "pin",
                keys: []))
        list.append(
            PaletteAction(kind: .hide, title: "Hide in \(appName ?? "this app")", symbol: "eye.slash", keys: []))
        if case .menuItem = command.source {
            list.append(
                PaletteAction(kind: .customizeItem, title: "Alias and shortcut...", symbol: "keyboard", keys: []))
        }
        if hasTip {
            list.append(
                PaletteAction(kind: .muteTip, title: "Stop reminding me of the keys", symbol: "bell.slash", keys: []))
        }
        list.append(PaletteAction(kind: .copyPath, title: "Copy menu path", symbol: "link", keys: []))
        if let shortcut = command.shortcut {
            list.append(
                PaletteAction(kind: .copyShortcut, title: "Copy shortcut", symbol: "keyboard", keys: shortcut.caps))
        }
        return list
    }

    /// Menu items, context actions, your commands and named destinations can become steps. The generic "Send to..." row
    /// needs a choice first, so it cannot.
    static func canJoinSequence(_ command: Command) -> Bool {
        switch command.source {
        case .menuItem, .contextAction:
            return command.isEnabled
        case .sendTo(let target):
            guard case .destination = target else { return false }
            return command.isEnabled
        case .sequence, .app:
            return false
        }
    }

    /// What the Cmd+K popover offers on a row of the sequence draft.
    @MainActor
    private static func sequenceActions(for target: SequenceTarget, sequence: SequenceCenter?) -> [PaletteAction] {
        guard case .step(let id) = target, let sequence else {
            return [PaletteAction(kind: .run, title: "Open", symbol: "play", keys: ["↩"])]
        }
        var list = [
            PaletteAction(kind: .moveStep(-1), title: "Move up", symbol: "arrow.up", keys: ["⌥", "↑"]),
            PaletteAction(kind: .moveStep(1), title: "Move down", symbol: "arrow.down", keys: ["⌥", "↓"]),
        ]
        if sequence.hasTextInput(stepID: id) {
            if sequence.isAsking(stepID: id) {
                list.append(
                    PaletteAction(kind: .askMe(false), title: "Stop asking me", symbol: "text.cursor", keys: []))
            } else {
                if sequence.canChain(stepID: id) {
                    let selection = sequence.usesSelection(stepID: id)
                    list.append(
                        PaletteAction(
                            kind: .useSelection(!selection),
                            title: selection ? "Use the previous result" : "Use the selection instead",
                            symbol: "arrow.triangle.merge", keys: []))
                }
                list.append(
                    PaletteAction(
                        kind: .askMe(true), title: "Ask me for the text", symbol: "text.cursor", keys: []))
            }
        }
        let continues = sequence.continuesOnFailure(stepID: id)
        list.append(
            PaletteAction(
                kind: .continueOnFailure(!continues), title: continues ? "Stop if it fails" : "Keep going if it fails",
                symbol: continues ? "hand.raised" : "forward.end", keys: []))
        list.append(PaletteAction(kind: .deleteStep, title: "Delete step", symbol: "trash", keys: ["⌫"]))
        return list
    }

    @MainActor
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
