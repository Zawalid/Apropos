import Foundation

@testable import Apropos

/// A small Finder-like menu bar built by hand, so the tests never depend on a live app.
enum Fixtures {
    struct Recorder: CommandTarget {
        let name: String
        let log: Log
        func perform() throws { log.record(name) }
    }

    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func record(_ name: String) {
            lock.lock()
            items.append(name)
            lock.unlock()
        }
        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
    }

    static func menuBar(log: Log = Log()) -> [MenuItemSnapshot] {
        func item(
            _ title: String, char: String = "", mods: Int = 0, enabled: Bool = true, mark: String = "",
            glyph: Int = 0, virtual: Int = 0, children: [MenuItemSnapshot] = []
        ) -> MenuItemSnapshot {
            MenuItemSnapshot(
                title: title, isEnabled: enabled, cmdChar: char, cmdModifiers: mods, cmdGlyph: glyph,
                cmdVirtualKey: virtual, markChar: mark, children: children,
                target: children.isEmpty ? Recorder(name: title, log: log) : nil)
        }
        let separator = MenuItemSnapshot(title: "")
        return [
            MenuItemSnapshot(title: "Apple", children: [item("About This Mac")]),
            MenuItemSnapshot(
                title: "Finder",
                children: [
                    item("About Finder"), separator,
                    item("Settings…", char: ",", mods: 0),
                    item("Services", children: [item("Reveal in Finder")]),
                    item("Quit Finder", char: "q"),
                ]),
            MenuItemSnapshot(
                title: "File",
                children: [
                    item("New Finder Window", char: "n"),
                    item("New Folder", char: "n", mods: 1),
                    item("Open Recent", children: [item("Project.txt"), item("Notes.md")]),
                    separator,
                    item("Move to Trash", enabled: false, virtual: 51),
                ]),
            MenuItemSnapshot(
                title: "Edit",
                children: [
                    item("Copy", char: "c"),
                    item("Select All", char: "a"),
                ]),
            MenuItemSnapshot(
                title: "View",
                children: [
                    item("as Icons", char: "1", mark: "✓"),
                    item("as List", char: "2"),
                    item("Show Path Bar", char: "p", mods: 2),
                    item("Show Preview", char: "p", mods: 1 | 8),
                    item("Back", char: "[", mods: 0),
                ]),
        ]
    }
}
