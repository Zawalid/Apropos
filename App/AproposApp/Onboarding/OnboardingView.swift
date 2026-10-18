import AppKit
import Apropos
import SwiftUI

extension OnboardingStep {
    fileprivate var title: String {
        switch self {
        case .welcome: "Welcome"
        case .permission: "Allow Accessibility"
        case .tryIt: "Try it"
        case .done: "Ready"
        }
    }
}

/// The first-run guide. One idea: the ring of the app icon closes as you set up, around the pearl that waits in its gap,
/// until it is the logo. The left column talks; the glass stage on the right (`Stage`) shows Apropos working on this
/// Mac. Keyboard driven; Return acts, arrows move, Escape closes.
struct OnboardingView: View {
    static let size = CGSize(width: 900, height: 580)

    let model: OnboardingModel
    var reduceMotionSetting = false
    /// Draws the ring in when the window opens. Previews leave it off and show each step as it rests.
    var drawsIn = false

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            CopyColumn(model: model)
                .frame(width: 430)
            Stage(model: model, drawsIn: drawsIn)
                .brandGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.vertical, 10)
                .padding(.trailing, 10)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(WindowBackdrop().ignoresSafeArea())
        .tint(Brand.mint)
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
            .onKeyPress(.return) {
                model.primary()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                model.next()
                return .handled
            }
            .onKeyPress(.leftArrow) {
                model.back()
                return .handled
            }
            .onKeyPress(.escape) {
                model.finish()
                return .handled
            }
            .accessibilityHidden(true)
    }
}

// MARK: Copy column

private struct CopyColumn: View {
    let model: OnboardingModel
    @Environment(\.aproposReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                stepCopy
                    .id(model.step)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(.leading, 56)
        .padding(.trailing, 28)
        .padding(.top, 78)
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.26), value: model.step)
    }

    @ViewBuilder
    private var stepCopy: some View {
        switch model.step {
        case .welcome: WelcomeCopy(model: model)
        case .permission: PermissionCopy(model: model)
        case .tryIt: TryItCopy(model: model)
        case .done: DoneCopy(model: model)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            StepDots(count: model.steps.count, current: model.index)
            Spacer()
            if !model.isFirst {
                Button("Back") { model.back() }
                    .buttonStyle(BrandButtonStyle(kind: .plain))
            }
            Button(model.primaryTitle) { model.primary() }
                .buttonStyle(BrandButtonStyle(kind: model.primaryIsAccent ? .primary : .secondary))
        }
        .frame(height: 84)
    }
}

/// Where you are: small dots, with the pearl on the current one gliding from step to step.
private struct StepDots: View {
    let count: Int
    let current: Int

    @Namespace private var space
    @Environment(\.aproposReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<count, id: \.self) { index in
                ZStack {
                    Circle()
                        .fill(index < current ? Brand.mint : Brand.text3.opacity(0.45))
                        .frame(width: 6, height: 6)
                    if index == current {
                        PearlView(size: 8).matchedGeometryEffect(id: "pearl", in: space)
                    }
                }
                .frame(width: 10, height: 10)
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.42, dampingFraction: 0.66), value: current
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// The shared look of a step's words: a large title and a short paragraph.
private struct StepWords<Content: View>: View {
    let title: String
    let lead: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 38, weight: .semibold))
                .tracking(-1.2)
                .foregroundStyle(Brand.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(lead)
                .font(.system(size: 14.5))
                .lineSpacing(4)
                .foregroundStyle(Brand.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
            content
        }
    }
}

private struct WelcomeCopy: View {
    let model: OnboardingModel

    var body: some View {
        StepWords(
            title: "Actions that fit the moment.",
            lead:
                "Apropos reads the app you are in and offers what fits: its menu commands, plus actions for what you have selected. It runs alongside your launcher."
        ) {
            HStack(spacing: 8) {
                Text("Open it from anywhere with")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.text3)
                HotKeyCaps(combo: model.hotKey)
            }
            .padding(.top, 26)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct PermissionCopy: View {
    let model: OnboardingModel

    var body: some View {
        StepWords(
            title: model.permission.isTrusted ? "Accessibility is on." : "Allow Accessibility.",
            lead: model.permission.isTrusted
                ? "Apropos can read menus now. The ring just grew. Carry on."
                : "macOS asks once. Apropos reads the menu bar of the app you are in to list its commands. With context on, it also reads window titles and selections. Nothing leaves this Mac."
        ) {
            HStack {
                status
                Spacer()
                if !model.permission.isTrusted {
                    Button {
                        model.showsHelp.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(model.showsHelp ? 90 : 0))
                            Text("Not in the list?")
                        }
                    }
                    .buttonStyle(BrandButtonStyle(kind: .plain))
                    .accessibilityValue(model.showsHelp ? "Expanded" : "Collapsed")
                }
            }
            .frame(height: 34)
            .padding(.top, 18)
            if model.showsHelp && !model.permission.isTrusted { help }
        }
    }

    @ViewBuilder
    private var status: some View {
        if model.permission.isTrusted {
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Brand.mint)
        } else {
            HStack(spacing: 9) {
                PearlView(size: 6, pulsing: true)
                Text("Waiting for access").font(.system(size: 13)).foregroundStyle(Brand.text2)
            }
        }
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "If Apropos is not listed, press + under the list and choose it, or drag it in. An old entry called Cue can be removed with the minus button."
            )
            .font(.system(size: 12.5))
            .lineSpacing(2)
            .foregroundStyle(Brand.text2)
            .fixedSize(horizontal: false, vertical: true)
            Text(model.bundlePath)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Brand.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.raised))
            HStack(spacing: 8) {
                Button(model.copiedPath ? "Copied" : "Copy path") { model.copyPath() }
                    .buttonStyle(BrandButtonStyle(kind: .secondary))
                Button("Show in Finder") { model.showInFinder() }
                    .buttonStyle(BrandButtonStyle(kind: .secondary))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous).fill(Brand.section))
    }
}

private struct TryItCopy: View {
    let model: OnboardingModel

    var body: some View {
        StepWords(
            title: "Try it in any app.",
            lead: model.panelOpened
                ? "Apropos opened over another app. Press Escape to close it, then continue."
                : "Switch to any app, then press the shortcut. You can change it later in Settings."
        ) {
            HStack(spacing: 9) {
                if model.panelOpened {
                    Label("That is it", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.mint)
                } else {
                    PearlView(size: 6, pulsing: true)
                    Text("Waiting for the shortcut").font(.system(size: 13)).foregroundStyle(Brand.text2)
                }
            }
            .frame(height: 34)
            .padding(.top, 18)
        }
    }
}

private struct DoneCopy: View {
    let model: OnboardingModel

    var body: some View {
        StepWords(
            title: "Apropos is ready.",
            lead:
                "It lives in the menu bar. Click its icon for recent commands and Settings, or press the shortcut from any app. Choose Welcome Guide in that menu to see this again."
        ) {
            VStack(spacing: 0) {
                next("command", "Create your first command", detail: "Commands", first: true)
                next("paperplane", "Choose where Send to goes", detail: "Destinations", first: false)
                next("sparkles", "See what it learns", detail: "Prediction", first: false)
            }
            .background(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous).fill(Brand.section))
            .padding(.top, 24)
        }
    }

    private func next(_ symbol: String, _ title: String, detail: String, first: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Brand.text2).frame(width: 18)
            Text(title).font(.system(size: 13.5)).foregroundStyle(Brand.text).lineLimit(1)
            Spacer(minLength: 8)
            Text(detail).font(.system(size: 12)).foregroundStyle(Brand.text3).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1).opacity(first ? 0 : 1) }
    }
}

// MARK: Pieces

private struct HotKeyCaps: View {
    let combo: HotKeyCombo

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(combo.caps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Brand.text2)
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, cap.count > 1 ? 6 : 0)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.raised))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Brand.line, lineWidth: 1))
            }
        }
    }
}
