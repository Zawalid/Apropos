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

/// The first-run guide: a rail with the steps and the pearl on the current one, and a main area with one idea per step.
/// Keyboard driven; Return acts, arrows move, Escape closes.
struct OnboardingView: View {
    static let size = CGSize(width: 860, height: 560)

    let model: OnboardingModel
    var reduceMotionSetting = false

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rail(model: model)
            MainArea(model: model)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Brand.window)
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

// MARK: Rail

private struct Rail: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                brandIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text("Apropos")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.15)
                        .foregroundStyle(Brand.text)
                    Text("Set up")
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.text3)
                }
            }
            .padding(.bottom, 34)
            RingStepper(
                titles: model.steps.map(\.title), current: model.index,
                pearlPulses: (model.step == .permission && !model.permission.isTrusted)
                    || (model.step == .tryIt && !model.panelOpened))
            Spacer(minLength: 0)
            Text("Takes about a minute.")
                .font(.system(size: 12))
                .foregroundStyle(Brand.text3)
        }
        .padding(.top, 58)
        .padding(.horizontal, 24)
        .padding(.bottom, 26)
        .frame(width: 236)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Brand.rail)
        .overlay(alignment: .trailing) { Rectangle().fill(Brand.line).frame(width: 1) }
    }

    @ViewBuilder
    private var brandIcon: some View {
        if let image = Brand.image("BrandIcon", file: "app-icon.png") {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: 42, height: 42)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.raised).frame(width: 42, height: 42)
        }
    }
}

// MARK: Main area

private struct MainArea: View {
    let model: OnboardingModel
    @Environment(\.aproposReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.step == .welcome { hero }
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    stepView
                        .id(model.step)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.26), value: model.step)
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

    /// The floating ring and pearl, cropped by the window edge so it reads as an object in a room.
    @ViewBuilder
    private var hero: some View {
        if let image = Brand.image("HeroRing", file: "hero-ring.png") {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 360)
                .offset(x: 330, y: 110)
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }

    private var footer: some View {
        HStack {
            if !model.isFirst {
                Button("Back") { model.back() }
                    .buttonStyle(BrandButtonStyle(kind: .plain))
            }
            Spacer()
            Button(model.primaryTitle) { model.primary() }
                .buttonStyle(BrandButtonStyle(kind: model.primaryIsAccent ? .primary : .secondary))
        }
        .padding(.horizontal, 56)
        .frame(height: 84)
    }
}

// MARK: Step frame

/// The shared frame of a step: a small step count, a large title, a short paragraph, then the step's own content.
private struct StepFrame<Content: View>: View {
    let index: Int
    let count: Int
    let title: String
    let lead: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Step \(index + 1) of \(count)")
                .font(.system(size: 12))
                .foregroundStyle(Brand.text3)
                .padding(.bottom, 14)
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .tracking(-1.0)
                .foregroundStyle(Brand.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Text(lead)
                .font(.system(size: 14.5))
                .lineSpacing(4)
                .foregroundStyle(Brand.text2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380, alignment: .leading)
                .padding(.top, 14)
            content
        }
        .padding(.leading, 56)
        .padding(.top, 58)
    }
}

// MARK: Welcome

private struct WelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
        StepFrame(
            index: model.index, count: model.steps.count, title: "Actions that fit the moment.",
            lead:
                "Apropos reads the app you are in and offers what fits: its menu commands, plus actions for what you have selected. It runs alongside your launcher."
        ) {
            ContextDemo()
                .padding(.top, 28)
            HStack(spacing: 8) {
                Text("Open it from anywhere with")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.text3)
                HotKeyCaps(combo: model.hotKey)
            }
            .padding(.top, 20)
            .accessibilityElement(children: .combine)
        }
    }
}

/// A small, live picture of the idea: the same panel offers different things in different apps.
private struct ContextDemo: View {
    private struct Scene {
        let caption: String
        let rows: [(symbol: String, title: String, keys: String)]
    }

    private let scenes: [Scene] = [
        Scene(
            caption: "In Finder, 3 items selected",
            rows: [
                ("folder.badge.plus", "New folder", "\u{21E7}\u{2318}N"), ("doc.on.doc", "Copy path", ""),
                ("terminal", "Open in Terminal here", ""), ("doc.zipper", "Compress 3 items", ""),
            ]),
        Scene(
            caption: "In Safari, on linear.app",
            rows: [
                ("link", "Copy as Markdown link", ""), ("xmark", "Close other tabs from linear.app", ""),
                ("paperplane", "Send page to Notes", ""), ("arrow.uturn.backward", "Reopen last closed tab", "\u{21E7}\u{2318}T"),
            ]),
        Scene(
            caption: "In Xcode, on branch feat/panel",
            rows: [
                ("play", "Build and run", "\u{2318}R"), ("testtube.2", "Run tests", "\u{2318}U"),
                ("arrow.triangle.branch", "Copy branch name", ""), ("folder.badge.magnifyingglass", "Reveal in Finder", "\u{2325}\u{2318}R"),
            ]),
    ]

    @State private var index = 0
    @Environment(\.aproposReduceMotion) private var reduceMotion

    var body: some View {
        let scene = scenes[index]
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "scope").font(.system(size: 11, weight: .medium))
                Text(scene.caption).font(.system(size: 12))
            }
            .foregroundStyle(Brand.text3)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            ForEach(Array(scene.rows.enumerated()), id: \.offset) { offset, row in
                HStack(spacing: 11) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Brand.text2)
                        .frame(width: 18)
                    Text(row.title).font(.system(size: 13.5)).foregroundStyle(Brand.text)
                    Spacer(minLength: 8)
                    if !row.keys.isEmpty { MiniKeys(text: row.keys) }
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(offset == 0 ? Brand.raised : .clear)
            }
        }
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous).fill(Brand.section))
        .clipShape(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous))
        .id(index)
        .transition(.opacity)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.2))
                withAnimation(.easeOut(duration: 0.22)) { index = (index + 1) % scenes.count }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: Permission

private struct PermissionStep: View {
    let model: OnboardingModel

    var body: some View {
        StepFrame(
            index: model.index, count: model.steps.count,
            title: model.permission.isTrusted ? "Accessibility is on." : "Allow Accessibility.",
            lead: model.permission.isTrusted
                ? "Apropos can read menus now. You can carry on."
                : "macOS asks once. Apropos reads the menu bar of the app you are in to list its commands. With context on, it also reads window titles and selections. Nothing leaves this Mac."
        ) {
            SystemSettingsSketch(allowed: model.permission.isTrusted)
                .padding(.top, 22)
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
            .frame(width: 400, height: 34)
            .padding(.top, 8)
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
            Text("If Apropos is not listed, press + under the list and choose it, or drag it in. An old entry called Cue can be removed with the minus button.")
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
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.raised))
            HStack(spacing: 8) {
                Button(model.copiedPath ? "Copied" : "Copy path") { model.copyPath() }
                    .buttonStyle(BrandButtonStyle(kind: .secondary))
                Button("Show in Finder") { model.showInFinder() }
                    .buttonStyle(BrandButtonStyle(kind: .secondary))
            }
        }
        .padding(14)
        .frame(width: 400, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous).fill(Brand.section))
    }
}

/// A faithful little sketch of the System Settings list, so the person knows what they are looking for.
private struct SystemSettingsSketch: View {
    let allowed: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Privacy and Security, Accessibility")
                .font(.system(size: 12))
                .foregroundStyle(Brand.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 36)
            row("Terminal", on: true, mine: false)
            row("Apropos", on: allowed, mine: true)
            row("Shortcuts", on: true, mine: false)
        }
        .frame(width: 400)
        .background(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous).fill(Brand.section))
        .clipShape(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private func row(_ name: String, on: Bool, mine: Bool) -> some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(mine ? Brand.pearl : Brand.raised)
                .frame(width: 20, height: 20)
            Text(name).font(.system(size: 13.5)).foregroundStyle(Brand.text)
            Spacer()
            Capsule()
                .fill(on ? Brand.mint : Brand.text3.opacity(0.4))
                .frame(width: 34, height: 20)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(on ? Brand.mintInk : Brand.text).frame(width: 16, height: 16).padding(2)
                }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(mine ? Brand.mint.opacity(0.10) : .clear)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
    }
}

// MARK: Try it

private struct TryItStep: View {
    let model: OnboardingModel

    var body: some View {
        StepFrame(
            index: model.index, count: model.steps.count, title: "Try it in any app.",
            lead: model.panelOpened
                ? "Apropos opened over another app. Press Escape to close it, then continue."
                : "Switch to an app, then press the shortcut. You can change it later in Settings."
        ) {
            HotKeyCaps(combo: model.hotKey, large: true)
                .padding(.top, 26)
                .accessibilityElement(children: .combine)
            WindowSketch(opened: model.panelOpened)
                .padding(.top, 24)
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
            .padding(.top, 6)
        }
    }
}

private struct WindowSketch: View {
    let opened: Bool

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach([0.38, 0.72, 0.55], id: \.self) { fraction in
                    Capsule().fill(Brand.raised).frame(width: 400 * fraction - 36, height: 9)
                }
            }
            .padding(18)
            .frame(width: 400, height: 150, alignment: .topLeading)
            if opened {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search Finder commands")
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.text3)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 4)
                    sketchRow("folder.badge.plus", "New folder", selected: true)
                    sketchRow("doc.on.doc", "Copy path", selected: false)
                }
                .padding(8)
                .frame(width: 320)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.window))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                .padding(.top, 20)
                .transition(.opacity)
            }
        }
        .frame(width: 400, height: 150)
        .background(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous).fill(Brand.section))
        .clipShape(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private func sketchRow(_ symbol: String, _ title: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Brand.text2).frame(width: 16)
            Text(title).font(.system(size: 13)).foregroundStyle(Brand.text)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Brand.raised : .clear))
    }
}

// MARK: Done

private struct DoneStep: View {
    let model: OnboardingModel

    var body: some View {
        StepFrame(
            index: model.index, count: model.steps.count, title: "Apropos is ready.",
            lead:
                "It lives in the menu bar. Click its icon for recent commands and Settings, or press the shortcut from any app. Choose Welcome Guide in that menu to see this again."
        ) {
            HStack(spacing: 18) {
                ForEach(["Finder", "File", "Edit"], id: \.self) { Text($0).font(.system(size: 12.5)).foregroundStyle(Brand.text2) }
                Spacer()
                BrandGlyph()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Brand.text)
                Text("Sun 9:41").font(.system(size: 12.5)).foregroundStyle(Brand.text2)
            }
            .padding(.horizontal, 14)
            .frame(width: 400, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.section))
            .padding(.top, 26)
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                next("command", "Create your first command", detail: "Settings, Commands")
                next("paperplane", "Choose Send to destinations", detail: "Settings, Destinations")
                next("sparkles", "See what Apropos learns", detail: "Settings, Prediction")
            }
            .frame(width: 400)
            .background(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous).fill(Brand.section))
            .padding(.top, 14)
        }
    }

    private func next(_ symbol: String, _ title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Brand.text2).frame(width: 18)
            Text(title).font(.system(size: 13.5)).foregroundStyle(Brand.text)
            Spacer()
            Text(detail).font(.system(size: 12)).foregroundStyle(Brand.text3)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1).opacity(symbol == "command" ? 0 : 1) }
    }
}

// MARK: Pieces

/// Shortcut glyphs as small keys, one per character.
private struct MiniKeys: View {
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Brand.text3)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Brand.line, lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HotKeyCaps: View {
    let combo: HotKeyCombo
    var large = false

    var body: some View {
        HStack(spacing: large ? 8 : 5) {
            ForEach(Array(combo.caps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(.system(size: large ? 20 : 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(large ? Brand.text : Brand.text2)
                    .frame(minWidth: large ? 56 : 22, minHeight: large ? 56 : 22)
                    .padding(.horizontal, cap.count > 1 ? (large ? 16 : 6) : 0)
                    .background(
                        RoundedRectangle(cornerRadius: large ? 12 : 6, style: .continuous).fill(large ? Brand.section : Brand.raised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: large ? 12 : 6, style: .continuous).strokeBorder(Brand.line, lineWidth: 1)
                    )
                    .shadow(color: Brand.raised, radius: 0, y: large ? 3 : 0)
            }
        }
    }
}
