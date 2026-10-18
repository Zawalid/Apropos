#if DEBUG
    import AppKit
    import Apropos

    /// Debug builds only: APROPOS_FIXTURE_COMMANDS=finder|safari|xcode seeds a realistic command list so the palette can be
    /// checked without Accessibility access. Titles keep the noise real menus carry (ellipses, update counts).
    enum DebugFixtures {
        /// The app a fixture list pretends to belong to, so automated runs need not bring the real app to the front.
        @MainActor
        static func targetApp(named name: String) -> TargetApp {
            let (bundle, title): (String, String)
            switch name {
            case "safari": (bundle, title) = ("com.apple.Safari", "Safari")
            case "xcode": (bundle, title) = ("com.apple.dt.Xcode", "Xcode")
            default: (bundle, title) = ("com.apple.finder", "Finder")
            }
            let pid =
                NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier ?? 0
            return TargetApp(pid: pid, bundleID: bundle, name: title)
        }

        static func commands(named name: String) -> [Command] {
            let spec: [(path: [String], title: String, key: KeyShortcut?, enabled: Bool, checked: Bool)]
            let cmd = ModifierSet.command
            switch name {
            case "safari":
                spec = [
                    (["File"], "New Window", KeyShortcut(key: "N", modifiers: cmd), true, false),
                    (["File"], "New Private Window", KeyShortcut(key: "N", modifiers: [.shift, cmd]), true, false),
                    (["File"], "Open File\u{2026}", KeyShortcut(key: "O", modifiers: cmd), true, false),
                    (["File"], "Close Tab", KeyShortcut(key: "W", modifiers: cmd), true, false),
                    (["File"], "Share\u{2026}", nil, true, false),
                    (["Edit"], "Find\u{2026}", KeyShortcut(key: "F", modifiers: cmd), true, false),
                    (["View"], "Show Sidebar", KeyShortcut(key: "S", modifiers: [.shift, cmd]), true, true),
                    (["View"], "Enter Reader", KeyShortcut(key: "R", modifiers: [.shift, cmd]), true, false),
                    (
                        ["History"], "Reopen Last Closed Tab", KeyShortcut(key: "T", modifiers: [.shift, cmd]), true,
                        false
                    ),
                    (["Bookmarks"], "Add Bookmark\u{2026}", KeyShortcut(key: "D", modifiers: cmd), true, false),
                    (["Window"], "Minimize", KeyShortcut(key: "M", modifiers: cmd), true, false),
                    (["Window"], "Software Update, 1 update", nil, false, false),
                ]
            case "xcode":
                spec = [
                    (
                        ["File", "New"], "Project\u{2026}", KeyShortcut(key: "N", modifiers: [.shift, cmd]), true, false
                    ),
                    (["File"], "Open Quickly\u{2026}", KeyShortcut(key: "O", modifiers: [.shift, cmd]), true, false),
                    (
                        ["Edit"], "Find in Project\u{2026}", KeyShortcut(key: "F", modifiers: [.shift, cmd]), true,
                        false
                    ),
                    (
                        ["Navigate"], "Jump to Definition", KeyShortcut(key: "J", modifiers: [.control, cmd]), true,
                        false
                    ),
                    (["Editor"], "Re-Indent", KeyShortcut(key: "I", modifiers: .control), true, false),
                    (["Product"], "Run", KeyShortcut(key: "R", modifiers: cmd), true, false),
                    (["Product"], "Test", KeyShortcut(key: "U", modifiers: cmd), true, false),
                    (["Product"], "Clean Build Folder", KeyShortcut(key: "K", modifiers: [.shift, cmd]), true, false),
                    (["Debug"], "Pause", KeyShortcut(key: "Y", modifiers: [.control, cmd]), false, false),
                    (
                        ["Source Control"], "Commit\u{2026}", KeyShortcut(key: "C", modifiers: [.option, cmd]), true,
                        false
                    ),
                    (["Window"], "Minimize", KeyShortcut(key: "M", modifiers: cmd), true, false),
                ]
            default:
                spec = [
                    (["File"], "New Finder Window", KeyShortcut(key: "N", modifiers: cmd), true, false),
                    (["File"], "New Folder", KeyShortcut(key: "N", modifiers: [.shift, cmd]), true, false),
                    (["File"], "Get Info", KeyShortcut(key: "I", modifiers: cmd), true, false),
                    (["File"], "Compress 3 Items", nil, true, false),
                    (["Edit"], "Copy 3 Items", KeyShortcut(key: "C", modifiers: cmd), true, false),
                    (["View"], "as Columns", KeyShortcut(key: "3", modifiers: cmd), true, true),
                    (["View"], "Show Path Bar", KeyShortcut(key: "P", modifiers: [.option, cmd]), true, false),
                    (["Go"], "Enclosing Folder", KeyShortcut(key: "\u{2191}", modifiers: cmd), true, false),
                    (["Go"], "Go to Folder\u{2026}", KeyShortcut(key: "G", modifiers: [.shift, cmd]), true, false),
                    (["Window"], "Minimize", KeyShortcut(key: "M", modifiers: cmd), true, false),
                    (["Help"], "Finder Help", KeyShortcut(key: "?", modifiers: cmd), true, false),
                ]
            }
            return spec.enumerated().map { index, item in
                Command(
                    id: "fx-\(index)", title: item.title, path: item.path, shortcut: item.key, isEnabled: item.enabled,
                    isChecked: item.checked, source: .menuItem(bundleID: nil))
            }
        }

        // MARK: Send to

        /// Context for the send-to scenes: a browser with a selection and a page, or Finder with some files.
        static func sendValues(bundleID: String?) -> ContextValues {
            if bundleID == "com.apple.finder" {
                return ContextValues(
                    selectedFiles: [
                        URL(fileURLWithPath: "/Users/me/Documents/Taxes 2025.pdf"),
                        URL(fileURLWithPath: "/Users/me/Documents/Receipts.zip"),
                    ], folderURL: URL(fileURLWithPath: "/Users/me/Documents"))
            }
            return ContextValues(
                selectedText: "Quarterly numbers look good, but the margin on the hardware line dropped two points. "
                    + "Worth a look before Friday.",
                pageURL: URL(string: "https://developer.apple.com/documentation/swiftui"),
                pageTitle: "SwiftUI | Apple Developer Documentation")
        }

        /// Teaches the usage store two habits for text, so direct "Send selection to Notes" rows show.
        @MainActor
        static func seedSendUsage(_ store: UsageStore) {
            for _ in 0..<6 { store.recordRun(id: CommandID(rawValue: "send:text>dest:notes")) }
            for _ in 0..<3 { store.recordRun(id: CommandID(rawValue: "send:text>dest:mail")) }
        }

        /// What an agent screenshot of the send-to flow needs from the running app.
        @MainActor
        struct SendHooks {
            let send: SendToCenter
            let actions: ContextActionCenter
            let usage: UsageController
            let sequences: SequenceCenter
        }

        @MainActor static var sendHooks: SendHooks?

        /// Puts the palette into one state of the send-to flow: `rows` (generic and recent rows in the list), `list` (the
        /// destination list), `confirm` (the Mail preview waiting for Return) or `error` (a failed send).
        @MainActor
        static func applySend(_ scene: String, model: PaletteModel) {
            guard let hooks = sendHooks, let app = model.targetApp else { return }
            // Dated ahead, so a real snapshot that lands later (empty, since nothing is sensed here) cannot replace it.
            let snapshot = ContextSnapshot(
                appName: app.name, bundleID: app.bundleID, pid: app.pid, capturedAt: Date().addingTimeInterval(3600),
                values: sendValues(bundleID: app.bundleID))
            hooks.actions.update(with: snapshot)
            hooks.send.update(with: snapshot)
            hooks.sequences.update(with: snapshot)
            seedSendUsage(hooks.usage.store)
            hooks.send.refresh()
            if let sequence = SequenceScene(rawValue: scene) {
                Task { await DebugSequences.apply(sequence, model: model) }
                return
            }
            guard scene != "rows" else { return }
            Task {
                guard
                    let generic = model.results.first(where: {
                        $0.command.id.hasPrefix("send:") && $0.command.title.hasSuffix("to...")
                    })
                else { return }
                _ = await model.run(generic.command)
                let wanted = scene == "confirm" ? "Mail draft" : (scene == "error" ? "Notes" : nil)
                if let wanted, let row = model.results.first(where: { $0.command.title == wanted }) {
                    _ = await model.run(row.command)
                }
            }
        }

        /// Makes the first few fixture commands habits (and pins the fourth) so Suggested and Pinned have something to show.
        @MainActor
        static func seedUsage(_ usage: UsageController, commands: [Command]) {
            for command in commands.prefix(3).enumerated() {
                for _ in 0..<(8 - command.offset * 2) { usage.store.recordRun(of: command.element) }
            }
            if commands.count > 3 { usage.store.setPinned(true, for: commands[3].stableID) }
            usage.refreshRanker()
        }

        /// Teaches the prediction engine one routine over the fixture commands, so the real Usually next path (log,
        /// model, threshold, palette group) shows a row: the sixth command is always followed by the seventh, and the
        /// sixth just ran.
        @MainActor
        static func seedPrediction(_ usage: UsageController, commands: [Command], app: String?) {
            let enabled = commands.filter(\.isEnabled)
            guard enabled.count > 6 else { return }
            let first = enabled[5].stableID
            let second = enabled[6].stableID
            let now = Date()
            for index in 0..<20 {
                let at = now.addingTimeInterval(-Double(index + 1) * 5_400)
                usage.prediction.recordRun(first, title: enabled[5].displayTitle, app: app, at: at)
                usage.prediction.recordRun(
                    second, title: enabled[6].displayTitle, app: app, at: at.addingTimeInterval(20))
            }
            usage.prediction.recordRun(first, title: enabled[5].displayTitle, app: app, at: now.addingTimeInterval(-6))
            usage.refreshRanker()
        }
    }
#endif
