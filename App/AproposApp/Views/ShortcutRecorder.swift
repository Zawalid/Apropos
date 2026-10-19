import AppKit
import Apropos
import SwiftUI

/// A button that shows the current global shortcut and, when clicked, records the next key combination.
struct ShortcutRecorder: View {
    let combo: HotKeyCombo
    let onRecordingChange: (Bool) -> Void
    let onChange: (HotKeyCombo) -> Void

    @State private var isRecording = false
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 8) {
            if let hint {
                Text(hint).font(.system(size: 12)).foregroundStyle(Theme.cautionText)
            }
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
                .background(Capsule().fill(isRecording ? Theme.accentSoft : Theme.Settings.chip))
                .overlay(Capsule().strokeBorder(isRecording ? Theme.accentText : .clear, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .background(
                KeyCatcher(active: isRecording, onKey: handle, onLoseFocus: stop)
                    .frame(width: 0, height: 0))
            .accessibilityLabel("Global shortcut, \(combo.display)")
        }
        .onDisappear { stop() }
    }

    private func start() {
        hint = nil
        isRecording = true
        onRecordingChange(true)
    }

    private func stop() {
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

/// An invisible view that takes the keyboard while recording, so every key reaches the recorder, command combinations
/// included, and nothing else in the window reacts to them.
private struct KeyCatcher: NSViewRepresentable {
    let active: Bool
    let onKey: (NSEvent) -> Void
    let onLoseFocus: () -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onKey = onKey
        view.onLoseFocus = onLoseFocus
        view.isActive = active
        if active, view.window?.firstResponder !== view {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }

    final class CatcherView: NSView {
        var onKey: (NSEvent) -> Void = { _ in }
        var onLoseFocus: () -> Void = {}
        var isActive = false

        override var acceptsFirstResponder: Bool { isActive }

        override func keyDown(with event: NSEvent) { onKey(event) }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isActive, window?.firstResponder === self else { return false }
            onKey(event)
            return true
        }

        override func resignFirstResponder() -> Bool {
            if isActive { onLoseFocus() }
            return super.resignFirstResponder()
        }
    }
}
