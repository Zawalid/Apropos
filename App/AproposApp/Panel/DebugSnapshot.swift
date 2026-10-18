#if DEBUG
    import AppKit
    import Apropos

    /// Debug builds only: when APROPOS_SNAPSHOT_DIR is set, writes a PNG of the palette a moment after it opens and a text
    /// dump of what it shows. Lets the palette be checked without screen recording permission.
    @MainActor
    enum DebugSnapshot {
        static func scheduleIfRequested(of panel: NSPanel, model: PaletteModel) {
            guard let dir = ProcessInfo.processInfo.environment["APROPOS_SNAPSHOT_DIR"] else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard let png = png(of: panel) else { return }
                let stamp =
                    ProcessInfo.processInfo.environment["APROPOS_SNAPSHOT_NAME"]
                    ?? "palette-\(Int(Date().timeIntervalSince1970))"
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(stamp).png"))
                let top = model.results.prefix(12).map {
                    "\($0.command.breadcrumb) > \($0.command.title) \($0.command.shortcut?.display ?? "")"
                }
                let text =
                    "app=\(model.targetApp?.name ?? "none") query=\(model.query) count=\(model.results.count)\n"
                    + top.joined(separator: "\n")
                try? text.write(toFile: "\(dir)/\(stamp).txt", atomically: true, encoding: .utf8)
            }
        }
    }

    extension DebugSnapshot {
        /// Writes a PNG of any window of this app into APROPOS_SNAPSHOT_DIR.
        static func capture(_ window: NSWindow, name: String) {
            guard let dir = ProcessInfo.processInfo.environment["APROPOS_SNAPSHOT_DIR"], let png = png(of: window)
            else { return }
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }

        /// A PNG drawn from the window's own views, so it works while the window is fully transparent and needs no
        /// screen recording permission. The desktop behind the glass is not part of it.
        static func png(of window: NSWindow) -> Data? {
            guard let view = window.contentView?.superview ?? window.contentView,
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            // The glass has no backdrop here, so lay the capture on a flat stand-in for it. Otherwise light text on
            // a transparent PNG is unreadable in a viewer.
            let dark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let backdrop = dark ? NSColor(srgbRed: 0.105, green: 0.115, blue: 0.11, alpha: 1)
                : NSColor(srgbRed: 0.93, green: 0.945, blue: 0.94, alpha: 1)
            guard let image = rep.cgImage,
                let context = CGContext(
                    data: nil, width: rep.pixelsWide, height: rep.pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return rep.representation(using: .png, properties: [:]) }
            let bounds = CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
            context.setFillColor(backdrop.cgColor)
            context.fill(bounds)
            context.draw(image, in: bounds)
            guard let flat = context.makeImage() else { return rep.representation(using: .png, properties: [:]) }
            return NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:])
        }

        /// Notification "com.zawalid.apropos.debug.settings" (object = page name) opens that Settings page and snapshots it.
        static func installSettingsControl(controller: AppController) {
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.zawalid.apropos.debug.settings"), object: nil, queue: .main
            ) { note in
                let name = note.object as? String ?? "general"
                MainActor.assumeIsolated {
                    controller.showSettings(page: SettingPage(rawValue: name))
                    Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        if let window = controller.settingsWindow { capture(window, name: "settings-\(name)") }
                    }
                }
            }
        }

        /// Debug builds only: lets a script open the palette and run the best match for a query without synthesizing
        /// keystrokes, through distributed notifications "com.zawalid.apropos.debug.toggle" and "...debug.run" (object = query).
        static func installRemoteControl(panel: PanelController, model: PaletteModel) {
            let center = DistributedNotificationCenter.default()
            center.addObserver(forName: Notification.Name("com.zawalid.apropos.debug.toggle"), object: nil, queue: .main) {
                _ in
                MainActor.assumeIsolated { panel.toggle() }
            }
            center.addObserver(forName: Notification.Name("com.zawalid.apropos.debug.run"), object: nil, queue: .main) {
                note in
                let query = note.object as? String ?? ""
                MainActor.assumeIsolated {
                    panel.show()
                    model.query = query
                    Task {
                        try? await Task.sleep(for: .milliseconds(900))
                        panel.runSelectedForDebug()
                    }
                }
            }
        }
    }
#endif
