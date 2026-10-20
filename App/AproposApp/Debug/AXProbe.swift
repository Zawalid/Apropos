#if DEBUG
    import AppKit
    import ApplicationServices
    import Apropos
    import Foundation

    /// Debug builds only: finds out what the apps you click in actually expose through Accessibility, so recording clicks on
    /// controls is built for what exists. While it runs, every left click is looked up with the Accessibility API and one
    /// line is kept: the app, the element's role, whether it can be pressed, whether it has a name or an identifier, and the
    /// roles of its parents up to the window. It writes `ax-probe.txt` in the support folder and keeps nothing else.
    ///
    /// What it never keeps: text fields' contents, window titles, document names, key presses, positions. A name is kept only
    /// for the roles of controls (buttons, checkboxes, tabs, menu items), cut to 40 characters; it is a local file for the
    /// person running the test.
    ///
    /// With `enableElectronTree`, it first sets `AXManualAccessibility` on the app in front, the switch Electron and
    /// Chromium apps honour to build their accessibility tree. Comparing a run with it and a run without it shows whether it
    /// is worth using.
    @MainActor
    final class AXProbe {
        static let maxSeconds: TimeInterval = 180
        private nonisolated static let controlRoles: Set<String> = [
            "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXTab", "AXMenuItem",
            "AXLink", "AXToolbar", "AXSegmentedControl", "AXDisclosureTriangle", "AXComboBox", "AXSlider",
        ]

        private(set) var isRunning = false
        private let enableElectronTree: Bool
        private let source = LiveCaptureSource()
        private let lock = NSLock()
        private let box = Box()
        private var timer: Timer?
        private var startedAt = Date()

        /// Mutable state shared with the event tap's thread.
        private final class Box: @unchecked Sendable {
            var lines: [String] = []
            var perApp: [String: [Int]] = [:]  // clicks, pressable, named, no element
            var enabledFor: Set<Int32> = []
            var tapEvents = 0
        }

        init(enableElectronTree: Bool) { self.enableElectronTree = enableElectronTree }

        /// One file per mode, in Apropos's own support folder, so the two runs never overwrite each other.
        var reportURL: URL {
            SettingsStore.supportDirectory.appendingPathComponent(
                "Apropos/ax-probe-\(enableElectronTree ? "electron" : "plain").txt")
        }

        func toggle() {
            if isRunning { finish("stopped by you") } else { start() }
        }

        private func start() {
            guard AXIsProcessTrusted(), CGPreflightListenEventAccess() else {
                if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
                write(
                    "NOT STARTED",
                    ["Accessibility and Input Monitoring must both be allowed, then Apropos reopened."])
                return
            }
            let enable = enableElectronTree
            let box = self.box
            let lock = self.lock
            if enable, let front = NSWorkspace.shared.frontmostApplication {
                Self.enableTree(pid: front.processIdentifier, box: box, lock: lock)
            }
            do {
                try source.start { event in
                    switch event {
                    case .appActivated(let app):
                        lock.withLock { box.tapEvents += 1 }
                        if enable { Self.enableTree(pid: app.pid, box: box, lock: lock) }
                    case .mouseDown(let point):
                        lock.withLock { box.tapEvents += 1 }
                        Self.record(click: point, box: box, lock: lock)
                    default:
                        break
                    }
                }
            } catch {
                write("NOT STARTED", ["The event tap could not start. Is Input Monitoring allowed?"])
                return
            }
            startedAt = Date()
            isRunning = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, Date().timeIntervalSince(self.startedAt) > Self.maxSeconds else { return }
                    self.finish("time limit")
                }
            }
        }

        private func finish(_ reason: String) {
            guard isRunning else { return }
            timer?.invalidate()
            timer = nil
            source.stop()
            isRunning = false
            let (lines, perApp, events) = lock.withLock { (box.lines, box.perApp, box.tapEvents) }
            var out: [String] = []
            out.append("Mode: " + (enableElectronTree ? "Electron accessibility switch ON" : "plain, no switch"))
            out.append("Ended: \(reason), after \(Int(Date().timeIntervalSince(startedAt))) seconds, \(events) tap events")
            out.append("")
            out.append("Per app (clicks, with a press action, with a name, no element found):")
            for (app, counts) in perApp.sorted(by: { $0.key < $1.key }) {
                out.append("  \(app): \(counts[0]), \(counts[1]), \(counts[2]), \(counts[3])")
            }
            out.append("")
            out.append("Clicks, in order:")
            out += lines
            write("FINISHED", out)
        }

        private func write(_ header: String, _ lines: [String]) {
            let text = ([header, ""] + lines).joined(separator: "\n") + "\n"
            try? FileManager.default.createDirectory(
                at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: reportURL, atomically: true, encoding: .utf8)
        }

        // MARK: Reading the Accessibility tree

        private nonisolated static func enableTree(pid: pid_t, box: Box, lock: NSLock) {
            let first = lock.withLock { box.enabledFor.insert(pid).inserted }
            guard first else { return }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.3)
            _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }

        private nonisolated static func record(click point: CGPoint, box: Box, lock: NSLock) {
            let systemWide = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(systemWide, 0.3)
            var found: AXUIElement?
            let status = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &found)
            guard status == .success, let element = found else {
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown app"
                lock.withLock {
                    box.perApp[front, default: [0, 0, 0, 0]][0] += 1
                    box.perApp[front, default: [0, 0, 0, 0]][3] += 1
                    box.lines.append("\(box.lines.count + 1). \(front): no element found (\(status.rawValue))")
                }
                return
            }
            AXUIElementSetMessagingTimeout(element, 0.3)
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            let app = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)"

            let role = string(element, kAXRoleAttribute) ?? "?"
            let subrole = string(element, kAXSubroleAttribute)
            let actions = actionNames(element)
            let pressable = actions.contains(kAXPressAction as String)
            let title = string(element, kAXTitleAttribute)
            let help = string(element, kAXDescriptionAttribute)
            let identifier = string(element, "AXIdentifier")
            let named = [title, help, identifier].contains { ($0 ?? "").isEmpty == false }

            var chain: [String] = []
            var current = parent(of: element)
            var depth = 0
            while let node = current, depth < 14 {
                let nodeRole = string(node, kAXRoleAttribute) ?? "?"
                chain.append(nodeRole.replacingOccurrences(of: "AX", with: ""))
                if nodeRole == "AXWindow" || nodeRole == "AXApplication" { break }
                current = parent(of: node)
                depth += 1
            }

            var line = "\(app): \(role)"
            if let subrole { line += "/\(subrole)" }
            line += pressable ? ", press action" : ", no press action"
            if controlRoles.contains(role) {
                if let title, !title.isEmpty { line += ", title \u{201C}\(title.prefix(40))\u{201D}" }
                if let help, !help.isEmpty { line += ", description \u{201C}\(help.prefix(40))\u{201D}" }
            } else {
                line += title?.isEmpty == false ? ", has a title" : ", no title"
            }
            if let identifier, !identifier.isEmpty { line += ", identifier \u{201C}\(identifier.prefix(40))\u{201D}" }
            line += ", enabled \(bool(element, kAXEnabledAttribute) ?? true)"
            line += ", parents \(chain.joined(separator: " < "))"

            lock.withLock {
                box.perApp[app, default: [0, 0, 0, 0]][0] += 1
                if pressable { box.perApp[app, default: [0, 0, 0, 0]][1] += 1 }
                if named { box.perApp[app, default: [0, 0, 0, 0]][2] += 1 }
                box.lines.append("\(box.lines.count + 1). \(line)")
            }
        }

        private nonisolated static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success else { return nil }
            return raw
        }

        private nonisolated static func string(_ element: AXUIElement, _ name: String) -> String? {
            value(element, name) as? String
        }

        private nonisolated static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
            (value(element, name) as? NSNumber)?.boolValue
        }

        private nonisolated static func actionNames(_ element: AXUIElement) -> [String] {
            var names: CFArray?
            guard AXUIElementCopyActionNames(element, &names) == .success, let names else { return [] }
            return (names as? [String]) ?? []
        }

        /// The one place a CF reference becomes an `AXUIElement`: the type id is checked first.
        private nonisolated static func parent(of element: AXUIElement) -> AXUIElement? {
            guard let raw = value(element, kAXParentAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeDowncast(raw, to: AXUIElement.self)
        }
    }
#endif
