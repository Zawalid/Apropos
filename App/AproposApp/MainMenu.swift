import AppKit

/// The menu bar of the app while one of its own windows is in front: Apropos (About, Settings with Command-comma, Hide,
/// Quit), Edit (so text fields get Cut, Copy, Paste and Undo) and Window. It is built here, by hand, so that
/// Command-comma opens the one Settings window and nothing else.
@MainActor
enum MainMenu {
    private static var handler: Handler?

    /// Menu actions need a target object; this one just calls the closures it was given.
    private final class Handler: NSObject {
        let openSettings: () -> Void
        let openAbout: () -> Void

        init(openSettings: @escaping () -> Void, openAbout: @escaping () -> Void) {
            self.openSettings = openSettings
            self.openAbout = openAbout
        }

        @objc func settings() { openSettings() }
        @objc func about() { openAbout() }
    }

    static func install(openSettings: @escaping () -> Void, openAbout: @escaping () -> Void) {
        let handler = Handler(openSettings: openSettings, openAbout: openAbout)
        Self.handler = handler
        let name = ProcessInfo.processInfo.processName
        let main = NSMenu()

        let appMenu = NSMenu(title: name)
        appMenu.addItem(item("About \(name)", #selector(Handler.about), "", target: handler))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings\u{2026}", #selector(Handler.settings), ",", target: handler))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"))
        let hideOthers = item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"))
        add(appMenu, to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        let redo = item("Redo", Selector(("redo:")), "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        add(edit, to: main)

        let window = NSMenu(title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        add(window, to: main)
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }

    private static func item(
        _ title: String, _ action: Selector, _ key: String, target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }

    private static func add(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }
}
