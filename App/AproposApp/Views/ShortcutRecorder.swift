import AppKit
import Apropos
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
        HStack(spacing: 8) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Group {
                    if isRecording {
                        Text("Press the new shortcut")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.accentText)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(Array(combo.caps.enumerated()), id: \.offset) { KeyCap(text: $0.element) }
                        }
                    }
                }
                .frame(minWidth: 110, minHeight: 30)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(
                        isRecording ? Theme.accentSoft : Theme.Settings.chip)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isRecording ? Theme.accentText : .clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable()
            .aproposFocusRing(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityLabel("Global shortcut, \(combo.display)")
            if let hint {
                Text(hint).font(.system(size: 12)).foregroundStyle(Theme.cautionText)
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
