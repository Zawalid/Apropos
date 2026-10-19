import Apropos
import SwiftUI

/// What the recording bar and the permission screen can do. The coordinator supplies them; previews leave them empty.
struct RecordingActions {
    var stop: () -> Void = {}
    var cancel: () -> Void = {}
    var openDraft: () -> Void = {}
    var dismiss: () -> Void = {}
    var allow: (RecordingPermissionKind) -> Void = { _ in }
    var start: () -> Void = {}
}

/// The recording bar: a small glass pill that floats near the top of the screen. The pearl pulses while it listens, the
/// time and the step count run, and Stop is one press. It never takes focus, so the app being recorded stays in front.
/// After the recording it says what happened in a line, and offers the draft.
struct RecordingBarView: View {
    let model: RecordingModel
    let stopKeys: [String]
    let actions: RecordingActions

    static let width: CGFloat = 420

    var body: some View {
        Group {
            switch model.phase {
            case .recording: live
            case .finished(let outcome): result(outcome.message, symbol: outcome.addedToDraft ? "checkmark" : "info.circle", open: outcome.addedToDraft)
            case .failed(let message): result(message, symbol: "exclamationmark.triangle.fill", open: false)
            case .idle, .needsPermission: EmptyView()
            }
        }
        .frame(width: Self.width)
    }

    // MARK: Listening

    private var live: some View {
        HStack(spacing: 10) {
            PearlView(size: 8, pulsing: !model.pausedForSecureInput)
                .opacity(model.pausedForSecureInput ? 0.4 : 1)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.pausedForSecureInput ? "Paused, password field" : "Recording")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.text)
                Text(detail)
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Brand.text3)
            }
            Spacer(minLength: 8)
            Button(action: actions.stop) {
                HStack(spacing: 6) {
                    Text("Stop").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                    ForEach(Array(stopKeys.enumerated()), id: \.offset) { KeyCap(text: $0.element, small: true) }
                }
            }
            .buttonStyle(CapsuleButtonStyle())
            .help("Stop and keep what was recorded")
            Button(action: actions.cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.text3)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Cancel and throw the recording away")
            .accessibilityLabel("Cancel recording")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 50)
        .aproposGlass(in: Capsule())
        .accessibilityElement(children: .contain)
    }

    /// "0:42 · 3 steps", counting down in the last half minute.
    private var detail: String {
        let steps = "\(model.stepCount) step\(model.stepCount == 1 ? "" : "s")"
        let remaining = model.maxDuration - model.elapsed
        if remaining <= 30 { return "\(Self.clock(max(remaining, 0))) left · \(steps)" }
        return "\(Self.clock(model.elapsed)) · \(steps)"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.down))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    // MARK: Done

    private func result(_ message: String, symbol: String, open: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(symbol == "checkmark" ? Brand.mint : Brand.text2)
                .frame(width: 18)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Brand.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if open {
                Button("Open draft", action: actions.openDraft)
                    .buttonStyle(CapsuleButtonStyle())
                    .font(.system(size: 12.5, weight: .semibold))
            }
            Button(action: actions.dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.text3)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .aproposGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// The screen that names the two permissions a recording needs, says what each allows, what is never kept, and opens the
/// right page of System Settings. Nothing is requested until the person presses Allow, and Apropos checks again once a
/// second so the row turns green as soon as the switch is on.
struct RecordingPermissionView: View {
    let model: RecordingModel
    let actions: RecordingActions

    static let size = CGSize(width: 500, height: 660)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandGlyph().foregroundStyle(Brand.text).frame(width: 22, height: 22)
                Text(RecordingPermissionCopy.headline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Brand.text)
            }
            Text(RecordingPermissionCopy.summary)
                .font(.system(size: 13))
                .foregroundStyle(Brand.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(Array(RecordingPermissionKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Divider().overlay(Brand.line) }
                    row(kind)
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.section))
            .padding(.top, 16)

            Text("What is never kept")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.text2)
                .padding(.top, 18)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(RecordingPermissionCopy.neverStored, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Brand.text3).frame(width: 4, height: 4).offset(y: -2)
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundStyle(Brand.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 6)

            Text(RecordingPermissionCopy.notRequested + " After allowing Input Monitoring, macOS may ask you to quit and reopen Apropos.")
                .font(.system(size: 11.5))
                .foregroundStyle(Brand.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Spacer(minLength: 12)
            HStack(spacing: 10) {
                Spacer()
                Button("Not now", action: actions.dismiss)
                    .buttonStyle(BrandButtonStyle(kind: .secondary))
                Button("Start recording", action: actions.start)
                    .buttonStyle(BrandButtonStyle(kind: .primary))
                    .disabled(!model.status.canRecord)
                    .opacity(model.status.canRecord ? 1 : 0.5)
            }
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(WindowBackdrop().ignoresSafeArea())
        .tint(Brand.mint)
        .ignoresSafeArea()
    }

    private func row(_ kind: RecordingPermissionKind) -> some View {
        let granted = model.status.isGranted(kind)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(granted ? Brand.mint : Brand.text3)
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Brand.text)
                Text(kind.whatItAllows)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Why: " + kind.whyRecording)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted {
                Text("Allowed").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.mint)
            } else {
                Button("Allow") { actions.allow(kind) }
                    .buttonStyle(BrandButtonStyle(kind: .secondary))
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}
