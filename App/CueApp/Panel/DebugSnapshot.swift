#if DEBUG
    import AppKit
    import Cue

    /// Debug builds only: when CUE_SNAPSHOT_DIR is set, writes a PNG of the palette a moment after it opens and a text
    /// dump of what it shows. Lets the palette be checked without screen recording permission.
    @MainActor
    enum DebugSnapshot {
        static func scheduleIfRequested(of panel: NSPanel, model: PaletteModel) {
            guard let dir = ProcessInfo.processInfo.environment["CUE_SNAPSHOT_DIR"] else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard
                    let image = CGWindowListCreateImage(
                        .null, .optionIncludingWindow, CGWindowID(panel.windowNumber), [.bestResolution])
                else { return }
                let rep = NSBitmapImageRep(cgImage: image)
                let stamp = Int(Date().timeIntervalSince1970)
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(dir)/palette-\(stamp).png"))
                }
                let top = model.results.prefix(12).map {
                    "\($0.command.breadcrumb) > \($0.command.title) \($0.command.shortcut?.display ?? "")"
                }
                let text =
                    "app=\(model.targetApp?.name ?? "none") query=\(model.query) count=\(model.results.count)\n"
                    + top.joined(separator: "\n")
                try? text.write(toFile: "\(dir)/palette-\(stamp).txt", atomically: true, encoding: .utf8)
            }
        }
    }

    extension DebugSnapshot {
        /// Debug builds only: lets a script open the palette and run the best match for a query without synthesizing
        /// keystrokes, through distributed notifications "com.zawalid.cue.debug.toggle" and "...debug.run" (object = query).
        static func installRemoteControl(panel: PanelController, model: PaletteModel) {
            let center = DistributedNotificationCenter.default()
            center.addObserver(forName: Notification.Name("com.zawalid.cue.debug.toggle"), object: nil, queue: .main) {
                _ in
                MainActor.assumeIsolated { panel.toggle() }
            }
            center.addObserver(forName: Notification.Name("com.zawalid.cue.debug.run"), object: nil, queue: .main) {
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
