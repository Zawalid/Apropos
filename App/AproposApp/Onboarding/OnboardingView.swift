import Apropos
import SwiftUI

/// The first-run guide: welcome, permission, try it, done. One column, one idea per step, keyboard driven.
struct OnboardingView: View {
    static let size = CGSize(width: 580, height: 600)

    let model: OnboardingModel
    var reduceMotionSetting = false

    @FocusState private var focused: Bool
    @Environment(\.aproposReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                stepView
                    .id(model.step)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, model.step == .permission && model.showsHelp ? 52 : 84)
            .animation(reduceMotion ? nil : Motion.easeOut(0.16), value: model.step)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.Settings.window)
        .tint(Theme.accent)
        .ignoresSafeArea()
        .providesReduceMotion(reduceMotionSetting)
        .background(keyCatcher)
    }

    /// Takes the keyboard on its own, so the buttons never show a focus ring just because the window is key.
    private var keyCatcher: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onKeyPress(.return) { act() }
            .onKeyPress(.rightArrow) { move(1) }
            .onKeyPress(.leftArrow) { move(-1) }
            .onKeyPress(.escape) {
                model.finish()
                return .handled
            }
            .accessibilityHidden(true)
    }

    private func act() -> KeyPress.Result {
        model.primary()
        return .handled
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        if delta > 0 { model.next() } else { model.back() }
        return .handled
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case .welcome: WelcomeStep(model: model)
        case .permission: PermissionStep(model: model)
        case .tryIt: TryItStep(model: model)
        case .done: DoneStep(model: model)
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var primaryButton: some View {
        if model.primaryIsAccent {
            Button(model.primaryTitle) { model.primary() }
                .buttonStyle(AccentButtonStyle())
        } else {
            Button(model.primaryTitle) { model.primary() }
                .buttonStyle(OnboardingSecondaryStyle())
        }
    }

    private var footer: some View {
        ZStack {
            StepDots(count: model.steps.count, current: model.index)
            HStack {
                if !model.isFirst {
                    Button("Back") { model.back() }
                        .buttonStyle(OnboardingSecondaryStyle())
                }
                Spacer()
                primaryButton
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 76)
    }
}

// MARK: Steps

/// The shared frame of a step: a tile, a title and a short paragraph, centered.
private struct StepHeader: View {
    let symbol: String
    let title: String
    let text: String
    var accent = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(accent ? Theme.accentInk : Theme.Settings.tileInk)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent ? Theme.accent : Theme.Settings.tile)
                )
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
        }
    }
}

private struct WelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(
                symbol: "command", title: "Welcome to Apropos",
                text:
                    "Apropos shows the actions that fit the moment, in the app you are in. It runs alongside your launcher, not instead of it.",
                accent: true)
            SamplePalette()
            HStack(spacing: 6) {
                Text("Open it from anywhere with")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text3)
                HotKeyCaps(combo: model.hotKey)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// A small, static picture of the palette: a chip row and three rows, so the welcome shows what the panel is for.
private struct SamplePalette: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                chip("Finder", symbol: "folder")
                chip("3 items selected", symbol: "cursorarrow.click")
            }
            .padding(.horizontal, 10)
            VStack(spacing: 0) {
                row("New folder", symbol: "folder.badge.plus", keys: ["\u{21E7}", "\u{2318}", "N"], selected: true)
                row("Get info", symbol: "info.circle", keys: ["\u{2318}", "I"], selected: false)
                row("Compress items", symbol: "doc.zipper", keys: [], selected: false)
            }
        }
        .padding(.vertical, 12)
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Settings.card))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Settings.cardEdge, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private func chip(_ text: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .medium))
            Text(text).font(.system(size: 11.5))
        }
        .foregroundStyle(Theme.text2)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(Theme.Settings.chip))
    }

    private func row(_ name: String, symbol: String, keys: [String], selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Settings.tileInk)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.Settings.tile))
            Text(name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
            Spacer()
            ForEach(keys, id: \.self) { KeyCap(text: $0, small: true) }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.Settings.highlight : .clear)
        )
        .padding(.horizontal, 6)
    }
}

private struct PermissionStep: View {
    let model: OnboardingModel
    @Environment(\.aproposReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            StepHeader(
                symbol: model.permission.isTrusted ? "checkmark" : "hand.raised",
                title: model.permission.isTrusted ? "Accessibility access is on" : "Allow Accessibility access",
                text: model.permission.isTrusted
                    ? "Apropos can read menus now. You can carry on."
                    : "Apropos reads the menu bar of the app you are using, so it can list and run its commands. With context sensing on, it also reads window titles and selections in some apps. Nothing leaves this Mac.",
                accent: model.permission.isTrusted)
            status
            if !model.permission.isTrusted { help }
        }
        .animation(reduceMotion ? nil : Motion.easeOut(0.16), value: model.permission.isTrusted)
        .animation(reduceMotion ? nil : Motion.easeOut(0.16), value: model.showsHelp)
    }

    @ViewBuilder
    private var status: some View {
        if !model.permission.isTrusted {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Waiting for access")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text3)
            }
        }
    }

    private var help: some View {
        VStack(spacing: 10) {
            Button {
                model.showsHelp.toggle()
            } label: {
                HStack(spacing: 5) {
                    Text("Not in the list?")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(model.showsHelp ? 90 : 0))
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .aproposFocusRing(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityValue(model.showsHelp ? "Expanded" : "Collapsed")
            if model.showsHelp { helpBody }
        }
    }

    private var helpBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "macOS lists an app once it has asked. Press Open System Settings first. If Apropos is still missing, press the plus button under the list and choose this app, or drag it in."
            )
            .font(.system(size: 12.5))
            .lineSpacing(2)
            .foregroundStyle(Theme.text2)
            .fixedSize(horizontal: false, vertical: true)
            Text(model.bundlePath)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.Settings.chip))
            HStack(spacing: 8) {
                Button(model.copiedPath ? "Copied" : "Copy path") { model.copyPath() }
                    .buttonStyle(OnboardingSecondaryStyle(compact: true))
                Button("Show in Finder") { model.showInFinder() }
                    .buttonStyle(OnboardingSecondaryStyle(compact: true))
            }
            Text("If an older entry called Cue is in the list, remove it with the minus button first.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 420)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.Settings.card))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.Settings.cardEdge, lineWidth: 1)
        )
        .transition(.opacity)
    }
}

private struct TryItStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(
                symbol: model.panelOpened ? "checkmark" : "keyboard", title: model.panelOpened ? "It works" : "Try it",
                text: model.panelOpened
                    ? "Apropos opened over another app. Press Escape to close it, then continue."
                    : "Switch to any app, then press the shortcut. Apropos lists that app's commands.",
                accent: model.panelOpened)
            HotKeyCaps(combo: model.hotKey, large: true)
                .accessibilityElement(children: .combine)
            if !model.panelOpened {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the shortcut")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text3)
                }
            }
        }
    }
}

private struct DoneStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(
                symbol: "checkmark", title: "Apropos is ready",
                text:
                    "It lives in the menu bar. Click its icon for recent commands and Settings, or press the shortcut from any app. To see this guide again, choose Welcome Guide in that menu.",
                accent: true)
            HStack(spacing: 8) {
                Image("MenuBarGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(Theme.text)
                    .frame(width: 30, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.Settings.highlight))
                Text("in the menu bar")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text3)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: Pieces

private struct HotKeyCaps: View {
    let combo: HotKeyCombo
    var large = false

    var body: some View {
        HStack(spacing: large ? 6 : 4) {
            ForEach(Array(combo.caps.enumerated()), id: \.offset) { _, cap in
                if large {
                    Text(cap)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(minWidth: 34, minHeight: 34)
                        .padding(.horizontal, cap.count > 1 ? 8 : 0)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.Settings.chip))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Theme.keyEdge, lineWidth: 1))
                } else {
                    KeyCap(text: cap)
                }
            }
        }
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.accent : Theme.Settings.switchOff)
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

private struct OnboardingSecondaryStyle: ButtonStyle {
    var compact = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12.5 : 13.5, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, compact ? 12 : 16)
            .frame(height: compact ? 28 : 36)
            .background(
                Capsule().fill(hovering || configuration.isPressed ? Theme.Settings.chipHover : Theme.Settings.chip)
            )
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .aproposFocusRing(Capsule())
    }
}
