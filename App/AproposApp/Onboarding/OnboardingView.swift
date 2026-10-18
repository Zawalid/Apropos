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

/// The first-run guide. One idea: the ring of the app icon is drawn as you set up. Each step adds an arc, the pearl rides
/// its tip, and on the last step the pearl settles into the gap and the ring is the logo. The left column talks; the
/// glass stage on the right shows. Keyboard driven; Return acts, arrows move, Escape closes.
struct OnboardingView: View {
    static let size = CGSize(width: 900, height: 580)

    let model: OnboardingModel
    var reduceMotionSetting = false

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            CopyColumn(model: model)
                .frame(width: 430)
            Stage(model: model)
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
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.42, dampingFraction: 0.66), value: current)
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

// MARK: Stage

/// The right-hand glass panel: the ring, tilting a little toward the pointer like an object held up to the light, with
/// what the step is about shown inside it.
private struct Stage: View {
    let model: OnboardingModel

    @State private var pointer: CGSize = .zero
    @Environment(\.aproposReduceMotion) private var reduceMotion

    static let ringSize: CGFloat = 300
    static let lineWidth: CGFloat = 20

    /// How much of the ring is drawn, as a fraction of the full circle. The finished logo is a ring of 304 degrees.
    private var progress: Double {
        switch model.step {
        case .welcome: 0.22
        case .permission: model.permission.isTrusted ? 0.50 : 0.36
        case .tryIt: model.panelOpened ? 0.74 : 0.62
        case .done: 304.0 / 360.0
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RingView(
                    progress: progress, settled: model.step == .done,
                    waiting: (model.step == .permission && !model.permission.isTrusted)
                        || (model.step == .tryIt && !model.panelOpened),
                    pointer: pointer)
                interior
                    .id(model.step)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .offset(x: pointer.width * 7, y: pointer.height * 7)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : -pointer.height * 7), axis: (x: 1, y: 0, z: 0), perspective: 0.6
            )
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : pointer.width * 7), axis: (x: 0, y: 1, z: 0), perspective: 0.6
            )
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    pointer = CGSize(
                        width: min(max((location.x / geometry.size.width - 0.5) * 2, -1), 1),
                        height: min(max((location.y / geometry.size.height - 0.5) * 2, -1), 1))
                case .ended:
                    pointer = .zero
                }
            }
        }
        .animation(.smooth(duration: 0.4), value: pointer)
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.3), value: model.step)
        .onChange(of: model.permission.isTrusted) { _, allowed in
            if allowed && !AgentMode.isOn { NSSound(named: "Glass")?.play() }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var interior: some View {
        switch model.step {
        case .welcome: CompactDemo()
        case .permission: PermissionInterior(allowed: model.permission.isTrusted)
        case .tryIt: TryItInterior(model: model)
        case .done: DoneInterior(combo: model.hotKey)
        }
    }
}

/// The ring and its pearl. The arc is mint with a soft glow and a slow specular sheen that follows the pointer; the pearl
/// rides the tip of the arc and, when the ring is finished, settles into the gap like the logo.
private struct RingView: View {
    let progress: Double
    let settled: Bool
    let waiting: Bool
    let pointer: CGSize

    @Environment(\.aproposReduceMotion) private var reduceMotion

    private var size: CGFloat { Stage.ringSize }
    private var radius: CGFloat { (Stage.ringSize - Stage.lineWidth) / 2 }
    private var startAngle: Double { -12 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let sheen = Angle.degrees(t * 22 + pointer.width * 50 - pointer.height * 50)
            let bob = reduceMotion ? 0 : CGFloat(sin(t * 2.2)) * 2.5
            ZStack {
                Circle()
                    .stroke(Brand.line, lineWidth: Stage.lineWidth)
                arc(Brand.mint)
                    .blur(radius: 16)
                    .opacity(settled ? 0.55 : 0.4)
                arc(Brand.mint)
                .shadow(color: .black.opacity(0.35), radius: 9, y: 7)
                arc(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center))
                arc(
                    AngularGradient(
                        stops: [
                            .init(color: .clear, location: 0), .init(color: .clear, location: 0.38),
                            .init(color: .white.opacity(0.42), location: 0.5), .init(color: .clear, location: 0.62),
                            .init(color: .clear, location: 1),
                        ], center: .center, angle: sheen)
                )
                .blendMode(.plusLighter)
                pearl(bob: bob)
            }
            .frame(width: size, height: size)
        }
    }

    private func arc<S: ShapeStyle>(_ style: S) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(style, style: StrokeStyle(lineWidth: Stage.lineWidth, lineCap: .round))
            .rotationEffect(.degrees(startAngle))
            .animation(.spring(response: 1.0, dampingFraction: 0.82), value: progress)
    }

    private func pearl(bob: CGFloat) -> some View {
        let angle = settled ? 320.0 : startAngle + progress * 360
        return ZStack {
            PearlView(size: 26, pulsing: waiting)
                .offset(x: radius + bob)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
        .animation(.spring(response: 1.0, dampingFraction: 0.78), value: angle)
    }
}

// MARK: Interiors

/// A live picture of the idea inside the ring: the same panel offers different things in different apps.
private struct CompactDemo: View {
    private struct Scene {
        let caption: String
        let rows: [(symbol: String, title: String)]
    }

    private let scenes: [Scene] = [
        Scene(
            caption: "In Finder, 3 selected",
            rows: [("folder.badge.plus", "New folder"), ("doc.on.doc", "Copy path"), ("doc.zipper", "Compress 3 items")]),
        Scene(
            caption: "In Safari, on linear.app",
            rows: [("link", "Copy as Markdown link"), ("paperplane", "Send page to Notes"), ("xmark", "Close other tabs")]),
        Scene(
            caption: "In Xcode, on feat/panel",
            rows: [("play", "Build and run"), ("testtube.2", "Run tests"), ("arrow.triangle.branch", "Copy branch name")]),
    ]

    @State private var index = 0
    @Environment(\.aproposReduceMotion) private var reduceMotion

    var body: some View {
        let scene = scenes[index]
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "scope").font(.system(size: 10, weight: .medium))
                Text(scene.caption).font(.system(size: 11.5))
            }
            .foregroundStyle(Brand.text3)
            .padding(.horizontal, 12)
            .padding(.bottom, 7)
            ForEach(Array(scene.rows.enumerated()), id: \.offset) { offset, row in
                HStack(spacing: 9) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.text2)
                        .frame(width: 16)
                    Text(row.title).font(.system(size: 12.5)).foregroundStyle(Brand.text)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(offset == 0 ? Brand.raised : .clear))
            }
        }
        .frame(width: 214)
        .id(index)
        .transition(.opacity)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.2))
                withAnimation(.easeOut(duration: 0.24)) { index = (index + 1) % scenes.count }
            }
        }
    }
}

/// The Accessibility row of System Settings, with its switch. It turns on by itself the moment access is granted.
private struct PermissionInterior: View {
    let allowed: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text("Privacy and Security, Accessibility")
                .font(.system(size: 11.5))
                .foregroundStyle(Brand.text3)
            HStack(spacing: 10) {
                icon
                Text("Apropos").font(.system(size: 14, weight: .medium)).foregroundStyle(Brand.text)
                Spacer(minLength: 8)
                Capsule()
                    .fill(allowed ? Brand.mint : Brand.text3.opacity(0.4))
                    .frame(width: 38, height: 22)
                    .overlay(alignment: allowed ? .trailing : .leading) {
                        Circle().fill(allowed ? Brand.mintInk : Brand.text).frame(width: 18, height: 18).padding(2)
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: allowed)
            }
            .padding(.horizontal, 14)
            .frame(width: 220, height: 50)
            .background(Capsule().fill(Brand.raised))
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = Brand.image("BrandIcon", file: "app-icon.png") {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: 28, height: 28)
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.pearl).frame(width: 28, height: 28)
        }
    }
}

/// The app in front, live, and the keys to press. It follows whichever app you switch to.
private struct TryItInterior: View {
    let model: OnboardingModel

    @State private var front = FrontApp()

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                if front.icon != nil {
                    AppIconImage(icon: front.icon, size: 52)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Brand.text3)
                        .frame(width: 52, height: 52)
                }
                Text(front.name ?? "Switch to any app")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(front.name == nil ? Brand.text3 : Brand.text)
            }
            if model.panelOpened {
                Label("Opened", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.mint)
                    .frame(height: 44)
            } else {
                PressingCaps(combo: model.hotKey)
            }
        }
        .animation(.easeOut(duration: 0.2), value: front.name)
        .animation(.easeOut(duration: 0.2), value: model.panelOpened)
    }
}

/// The shortcut as keys that press down in turn, to show what to do.
private struct PressingCaps: View {
    let combo: HotKeyCombo

    @Environment(\.aproposReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2)
            HStack(spacing: 7) {
                ForEach(Array(combo.caps.enumerated()), id: \.offset) { index, cap in
                    let pressed = t > 0.2 && t < 0.2 + 0.7 && (index == 0 || t > 0.2 + 0.18 * Double(index))
                    Text(cap)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(Brand.text)
                        .frame(minWidth: 46, minHeight: 46)
                        .padding(.horizontal, cap.count > 1 ? 12 : 0)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.raised))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.line, lineWidth: 1)
                        )
                        .offset(y: pressed ? 3 : 0)
                        .shadow(color: .black.opacity(pressed ? 0.05 : 0.22), radius: 0, y: pressed ? 0 : 3)
                }
            }
        }
    }
}

/// The finished ring holds the one thing to remember: the shortcut.
private struct DoneInterior: View {
    let combo: HotKeyCombo

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(Array(combo.caps.enumerated()), id: \.offset) { _, cap in
                    Text(cap)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundStyle(Brand.text)
                        .frame(minWidth: 52, minHeight: 52)
                        .padding(.horizontal, cap.count > 1 ? 14 : 0)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Brand.raised))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Brand.line, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.22), radius: 0, y: 3)
                }
            }
            Text("From any app")
                .font(.system(size: 12.5))
                .foregroundStyle(Brand.text3)
        }
    }
}

/// Tracks the app in front, ignoring Apropos itself, so the Try it step can show the app the person switched to.
@MainActor
@Observable
private final class FrontApp {
    private(set) var name: String?
    private(set) var icon: NSImage?

    @ObservationIgnored nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.adopt(app) }
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func adopt(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier, app.activationPolicy == .regular else {
            return
        }
        name = app.localizedName
        icon = app.icon
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
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Brand.line, lineWidth: 1))
            }
        }
    }
}
