import AppKit
import Cue

/// One entry of the Cmd+K popover.
struct PaletteAction: Identifiable {
    enum Kind { case run, copyPath, copyShortcut }

    let kind: Kind
    let title: String
    let symbol: String
    let keys: [String]

    var id: String { title }

    /// The actions available for a command, in display order.
    static func available(for command: Command?, appName: String?) -> [PaletteAction] {
        guard let command else { return [] }
        var list = [PaletteAction(kind: .run, title: "Run", symbol: "play", keys: ["↩"])]
        list.append(PaletteAction(kind: .copyPath, title: "Copy menu path", symbol: "link", keys: []))
        if let shortcut = command.shortcut {
            list.append(PaletteAction(kind: .copyShortcut, title: "Copy shortcut", symbol: "keyboard", keys: shortcut.caps))
        }
        return list
    }

    @MainActor
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
