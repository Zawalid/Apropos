import AppKit
import Cue

/// One entry of the Cmd+K popover.
struct PaletteAction: Identifiable {
    enum Kind: Equatable {
        case run
        case runAlternate(Int)
        case pin(Bool)
        case hide
        case copyPath
        case copyShortcut
    }

    let kind: Kind
    let title: String
    let symbol: String
    let keys: [String]

    var id: String { "\(kind)-\(title)" }

    /// The actions available for a command, in display order.
    static func available(for command: Command?, appName: String?, isPinned: Bool) -> [PaletteAction] {
        guard let command else { return [] }
        var list = [PaletteAction(kind: .run, title: "Run", symbol: "play", keys: ["↩"])]
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
        list.append(PaletteAction(kind: .copyPath, title: "Copy menu path", symbol: "link", keys: []))
        if let shortcut = command.shortcut {
            list.append(
                PaletteAction(kind: .copyShortcut, title: "Copy shortcut", symbol: "keyboard", keys: shortcut.caps))
        }
        return list
    }

    @MainActor
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
