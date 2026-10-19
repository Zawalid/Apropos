#if DEBUG
    import AppKit
    import Apropos
    import Foundation

    /// Counts the events a capture source delivers, by kind only: no position, key or app is looked at. It is how the
    /// live proof tells "the tap delivered nothing" apart from "the tap delivered clicks the recorder did not understand".
    private final class CountingSource: CaptureEventSource, @unchecked Sendable {
        private let inner: any CaptureEventSource
        private let lock = NSLock()
        private var counts: [String: Int] = [:]

        init(wrapping inner: any CaptureEventSource) { self.inner = inner }

        var summary: [String: Int] { lock.withLock { counts } }

        func start(handler: @escaping @Sendable (CaptureEvent) -> Void) throws {
            try inner.start { [weak self] event in
                self?.lock.withLock { self?.counts[Self.kind(of: event), default: 0] += 1 }
                handler(event)
            }
        }

        func stop() { inner.stop() }

        private static func kind(of event: CaptureEvent) -> String {
            switch event {
            case .mouseDown: "mouse down"
            case .keyDown: "key down"
            case .flagsChanged: "modifier change"
            case .appActivated: "app switch"
            case .tick: "tick"
            }
        }
    }

    /// Debug builds only: runs the recorder for real once (milestone R0 of docs/recorder-plan.md) and writes what it
    /// learned to `recorder-r0.txt` in Apropos's support folder. Started and stopped from the menu bar popover. It never
    /// saves a command; it only reports. Nothing typed is in the report, because the recorder never keeps it.
    @MainActor
    final class RecorderProbe {
        static let maxSeconds: TimeInterval = 150

        private(set) var isRunning = false
        private var recorder: Recorder?
        private var source: CountingSource?
        private var timer: Timer?
        private var startedAt = Date()

        static var reportURL: URL {
            SettingsStore.supportDirectory.appendingPathComponent("recorder-r0.txt")
        }

        /// Starts, or stops and writes the report when already running.
        func toggle() {
            if isRunning { finish(reason: "stopped by you") } else { start() }
        }

        private func start() {
            let permission = RecordingPermission()
            let status = permission.status()
            guard status.isGranted(.accessibility), status.isGranted(.inputMonitoring) else {
                // A button the person pressed asked for it, which is the only time the recorder may prompt.
                if !status.isGranted(.inputMonitoring) { permission.request(.inputMonitoring) }
                write(
                    header: "NOT STARTED",
                    lines: [
                        "Accessibility: \(status.isGranted(.accessibility) ? "allowed" : "missing")",
                        "Input Monitoring: \(status.isGranted(.inputMonitoring) ? "allowed" : "missing")",
                        "Allow both for Apropos in System Settings > Privacy and Security, quit Apropos, open it again, and retry.",
                    ])
                return
            }
            let services = RecordingServices(
                system: LiveRecordingSystem(), hitTester: LiveHitTester(), menus: LiveMenuInspector(),
                keyLayout: LiveKeyLayout())
            let engine = RecordingEngine(
                services: services,
                configuration: RecordingConfiguration(limits: RecordingLimits(maxDuration: Self.maxSeconds)),
                permission: permission, log: .standard)
            let counting = CountingSource(wrapping: LiveCaptureSource())
            let recorder = Recorder(engine: engine, source: counting)
            let state = recorder.begin()
            guard state == .recording else {
                write(header: "NOT STARTED", lines: ["The recorder did not start: \(RecorderLog.word(state))"])
                return
            }
            self.recorder = recorder
            source = counting
            startedAt = Date()
            isRunning = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let recorder = self.recorder else { return }
                    if recorder.state.isTerminal { self.finish(reason: RecorderLog.word(recorder.state)) }
                }
            }
        }

        private func finish(reason: String) {
            guard isRunning, let recorder else { return }
            timer?.invalidate()
            timer = nil
            let draft = recorder.finish()
            let counts = source?.summary ?? [:]
            let seconds = Int(Date().timeIntervalSince(startedAt))
            isRunning = false
            self.recorder = nil
            source = nil

            var lines: [String] = []
            lines.append("Ended: \(reason), after \(seconds) seconds")
            lines.append("Events the tap delivered: " + (counts.isEmpty ? "none" : counts.sorted { $0.key < $1.key }
                .map { "\($0.key) \($0.value)" }.joined(separator: ", ")))
            lines.append("")
            lines.append("Rows (\(draft.items.count)):")
            for (index, item) in draft.items.enumerated() {
                var line = "  \(index + 1). \(item.summary)"
                if let origin = item.originNote { line += "  [\(origin)]" }
                if let fragility = item.fragility { line += "  [\(fragility)]" }
                lines.append(line)
            }
            lines.append("")
            lines.append("Not recorded (\(draft.skipped.count) notes):")
            for note in draft.skipped { lines.append("  - \(note.text)") }
            lines.append("")
            do {
                let steps = try draft.validated(dropTextEntries: true)
                lines.append("Validates: yes, \(steps.backend.steps.count) steps")
            } catch {
                lines.append("Validates: no, \(error)")
            }
            write(header: "FINISHED", lines: lines)
        }

        private func write(header: String, lines: [String]) {
            let text = ([header, ""] + lines).joined(separator: "\n") + "\n"
            try? FileManager.default.createDirectory(
                at: Self.reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: Self.reportURL, atomically: true, encoding: .utf8)
            AproposLog.app.info("recorder probe wrote its report")
        }
    }
#endif
