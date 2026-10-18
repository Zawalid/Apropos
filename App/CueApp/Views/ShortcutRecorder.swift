import AppKit
import Cue
import SwiftUI

/// A button that shows the current global shortcut and, when clicked, records the next key combination.
struct ShortcutRecorder: View {
    let combo: HotKeyCombo
    let onRecordingChange: (Bool) -> Void
    let onChange: (HotKeyCombo) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Group {
                    if isRecording {
                        Text("Press the new shortcut")
                            .foregroundStyle(Theme.accentText)
                    } else {
                        HStack(spacing: 3) {
                            ForEach(Array(combo.caps.enumerated()), id: \.offset) { KeyCap(text: $0.element) }
                        }
                    }
                }
                .frame(minWidth: 140, minHeight: 24)
            }
            .buttonStyle(RecorderButtonStyle())
            .accessibilityLabel("Global shortcut, \(combo.display)")
            if let hint {
                Text(hint).font(.system(size: 12)).foregroundStyle(Theme.cautionText)
            } else if combo != .default && !isRecording {
                Button("Reset") { onChange(.default) }
                    .buttonStyle(.link)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        hint = nil
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording { onRecordingChange(false) }
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 {
            stop()
            return
        }
        var modifiers = ModifierSet()
        let flags = event.modifierFlags
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        let candidate = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard candidate.isValid else {
            hint = modifiers.isEmpty ? "Include a modifier key." : "That key is not supported."
            return
        }
        stop()
        onChange(candidate)
    }
}

private struct RecorderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.chip))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.chipEdge, lineWidth: 1))
            .brightness(configuration.isPressed ? -0.05 : 0)
            .contentShape(Rectangle())
            .cueFocusRing(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
