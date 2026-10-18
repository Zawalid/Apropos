// Throwaway fixture app for the recording spike. AppKit only, no nib, no bundle.
// Runs as an accessory app (no Dock icon, never activates) with a fully transparent window that ignores the mouse,
// the same trick as App/AproposApp/Panel/AgentMode.swift. Every user-visible action prints one JSON line to stdout,
// which is the ground truth the harness compares its observations against.
//
//   fixture            run until killed (harness mode)
//   fixture --selftest print its own accessibility tree through the in-process NSAccessibility API and exit.
//                      This needs no Accessibility permission, because the app reads itself.
//   -AppleLanguages "(fr)"  switch the visible titles to French (identifiers stay the same)
import AppKit

let isFrench = (Locale.preferredLanguages.first ?? "en").hasPrefix("fr")
func tr(_ en: String, _ fr: String) -> String { isFrench ? fr : en }

func log(_ event: String, _ detail: String = "") {
    print("{\"event\":\"\(event)\",\"detail\":\"\(detail)\"}")
    fflush(stdout)
}

final class Controller: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let rows = ["alpha", "beta", "gamma"]
    var window: NSWindow!
    let field = NSTextField()
    let secure = NSSecureTextField()
    let popup = NSPopUpButton()
    let label = NSTextField(labelWithString: "")
    let table = NSTableView()

    func button(_ title: String, id: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.setAccessibilityIdentifier(id)
        return b
    }

    func build() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        let save = button(tr("Save", "Enregistrer"), id: "save-button", action: #selector(saveTapped))
        let sheetButton = button(tr("Open sheet", "Ouvrir la feuille"), id: "sheet-button", action: #selector(openSheet))
        let noID = NSButton(title: tr("Export", "Exporter"), target: self, action: #selector(exportTapped))  // no identifier on purpose
        field.placeholderString = tr("Name", "Nom"); field.setAccessibilityIdentifier("name-field"); field.delegate = self
        secure.setAccessibilityIdentifier("password-field"); secure.delegate = self
        popup.addItems(withTitles: [tr("Small", "Petit"), tr("Medium", "Moyen"), tr("Large", "Grand")])
        popup.setAccessibilityIdentifier("size-popup"); popup.target = self; popup.action = #selector(popupChanged)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")); column.title = tr("Item", "Element")
        table.addTableColumn(column); table.dataSource = self; table.delegate = self
        table.setAccessibilityIdentifier("items-table")
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        label.setAccessibilityIdentifier("status-label")
        let stack = NSStackView(views: [field, secure, popup, save, noID, sheetButton, scroll, label])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.frame = content.bounds.insetBy(dx: 16, dy: 16); stack.autoresizingMask = [.width, .height]
        scroll.heightAnchor.constraint(equalToConstant: 100).isActive = true
        content.addSubview(stack)

        window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = tr("Fixture", "Banc d'essai"); window.contentView = content
        window.setAccessibilityIdentifier("main-window")
        window.alphaValue = 0; window.ignoresMouseEvents = true
        window.orderFrontRegardless()  // shows without activating the app
        buildMenu()
    }

    func buildMenu() {
        let main = NSMenu()
        func add(_ title: String, items: [(String, String, Selector, String)]) {
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: ""); main.addItem(top)
            let menu = NSMenu(title: title); top.submenu = menu
            for (t, key, sel, id) in items {
                let item = NSMenuItem(title: t, action: sel, keyEquivalent: key); item.target = self
                item.identifier = NSUserInterfaceItemIdentifier(id); menu.addItem(item)
            }
        }
        add("Fixture", items: [(tr("Quit", "Quitter"), "q", #selector(quit), "menu.quit")])
        add(tr("File", "Fichier"), items: [
            (tr("New Item", "Nouvel element"), "n", #selector(newItem), "menu.new"),
            (tr("Export as PDF", "Exporter en PDF"), "e", #selector(exportTapped), "menu.export"),
        ])
        add(tr("Edit", "Edition"), items: [(tr("Clear Name", "Effacer le nom"), "k", #selector(clearName), "menu.clear")])
        NSApp.mainMenu = main
    }

    @objc func saveTapped() { log("button", "save-button"); label.stringValue = "saved" }
    @objc func exportTapped() { log("menu-or-button", "export") }
    @objc func newItem() { log("menu", "new") }
    @objc func clearName() { log("menu", "clear"); field.stringValue = "" }
    @objc func popupChanged() { log("popup", popup.titleOfSelectedItem ?? "") }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func openSheet() {
        log("sheet", "open")
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let ok = NSButton(title: tr("Done", "Termine"), target: self, action: #selector(closeSheet))
        ok.setAccessibilityIdentifier("sheet-done"); ok.frame = NSRect(x: 100, y: 30, width: 100, height: 30)
        sheet.contentView = NSView(frame: sheet.frame); sheet.contentView?.addSubview(ok)
        window.beginSheet(sheet)
    }
    @objc func closeSheet() { if let s = window.attachedSheet { window.endSheet(s) }; log("sheet", "close") }

    func controlTextDidChange(_ n: Notification) {
        guard let f = n.object as? NSTextField else { return }
        // Never print the secure field value: this mirrors what a recorder must do.
        log("text", f === secure ? "password-field:<redacted>" : "\(f.accessibilityIdentifier()):\(f.stringValue)")
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        NSTextField(labelWithString: rows[row])
    }
    func tableViewSelectionDidChange(_ n: Notification) { log("row", "\(table.selectedRow)") }
}

func dump(_ element: Any, depth: Int = 0) {
    guard let e = element as? NSObjectProtocol & NSAccessibilityProtocol else { return }
    let role = e.accessibilityRole()?.rawValue ?? "-"
    let id = e.accessibilityIdentifier() ?? ""
    let title = e.accessibilityTitle() ?? e.accessibilityLabel() ?? ""
    print(String(repeating: "  ", count: depth) + "\(role)  id=\"\(id)\"  title=\"\(title)\"")
    for child in e.accessibilityChildren() ?? [] where depth < 8 { dump(child, depth: depth + 1) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
controller.build()
if CommandLine.arguments.contains("--selftest") {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        print("locale=\(Locale.preferredLanguages.first ?? "?")")
        dump(controller.window as Any)
        print("-- menu bar items (NSMenu, in-process)")
        for item in NSApp.mainMenu?.items ?? [] {
            print("\(item.title): " + (item.submenu?.items.map { "\($0.title)[id=\($0.identifier?.rawValue ?? "")]" }.joined(separator: ", ") ?? ""))
        }
        exit(0)
    }
}
log("ready", "pid=\(ProcessInfo.processInfo.processIdentifier)")
app.run()
