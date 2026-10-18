import AppKit
import Apropos
import SwiftUI

// The right-hand side of the guide: where the person sees Apropos work before they use it.
//
// One object carries it: the app icon's ring, standing in the glass. The pearl waits in the logo's gap from the first
// step, and the ring closes around it as setup is done, until it is the logo. Inside the ring floats the thing the
// step is about, drawn like the real thing: the palette over real apps, the Accessibility list of System Settings, the
// palette over the app the person actually has open, and finally the menu bar. Under it sits one instrument: a dock to
// switch apps, the path in System Settings, the shortcut keys that light as they are held.

/// The geometry the stage is laid out on, in points of the stage.
enum StageLayout {
    /// Wide enough that the step's object fits inside the ring, so every arc it gains stays in view.
    static let ringDiameter: CGFloat = 412
    /// The centre of the ring, from the stage's top. The finished logo sits a little lower, under the menu bar.
    static func ringCentreY(done: Bool) -> CGFloat { done ? 282 : 236 }
    /// How far below the ring's centre the step's object floats, so it clears the pearl in the gap.
    static let centreDrop: CGFloat = 14
    /// The centre of the instrument strip, from the stage's bottom.
    static let instrumentY: CGFloat = 58
}

struct Stage: View {
    let model: OnboardingModel
    /// Draws the first arc in when the stage appears, from nothing to the welcome's share. Off in previews, which take
    /// their picture at once.
    var drawsIn = false

    @State private var drawn = false
    @State private var pointer: CGSize = .zero
    @State private var pulses = 0
    @State private var dockDrop: CGFloat = 250
    @Environment(\.aproposReduceMotion) private var reduceMotion

    /// How much of the full circle the ring covers. The finished logo is 304 degrees, with the pearl in the gap.
    private var progress: Double {
        switch model.step {
        case .welcome: 0.30
        case .permission: model.permission.isTrusted ? 0.52 : 0.40
        case .tryIt: model.panelOpened ? 0.74 : 0.62
        case .done: LogoRing.span
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if model.step == .done {
                    MenuBarStrip()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                LogoRing(progress: drawsIn && !drawn ? 0 : progress, finished: done, pulses: pulses, pointer: pointer)
                    .offset(x: pointer.width * 4, y: pointer.height * 4)
                    .position(x: geometry.size.width / 2, y: ringY)
                centrepiece
                    .id(model.step)
                    .transition(centreTransition)
                    .offset(x: pointer.width * 11, y: pointer.height * 9)
                    .position(x: geometry.size.width / 2, y: ringY + (done ? 0 : StageLayout.centreDrop))
                instrument
                    .id(model.step)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 6)))
                    .position(x: geometry.size.width / 2, y: geometry.size.height - StageLayout.instrumentY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                dockDrop =
                    geometry.size.height - StageLayout.instrumentY - StageLayout.ringCentreY(done: false)
                    - StageLayout.centreDrop
            }
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : -pointer.height * 6), axis: (x: 1, y: 0, z: 0), perspective: 0.5
            )
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : pointer.width * 6), axis: (x: 0, y: 1, z: 0), perspective: 0.5
            )
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard !reduceMotion else { return }
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
        .animation(.smooth(duration: 0.5), value: pointer)
        .animation(
            reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.55, dampingFraction: 0.86), value: model.step
        )
        .onAppear { model.live.start() }
        .task {
            guard drawsIn, !drawn else { return }
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(350)) }
            drawn = true
        }
        .onChange(of: progress) { old, new in
            if new > old { pulses += 1 }
        }
        .onChange(of: model.permission.isTrusted) { _, allowed in
            if allowed && !AgentMode.isOn { NSSound(named: "Glass")?.play() }
        }
    }

    private var done: Bool { model.step == .done }
    private var ringY: CGFloat { StageLayout.ringCentreY(done: done) }

    private var centreTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.94)).combined(with: .offset(y: 14)),
                removal: .opacity.combined(with: .scale(scale: 1.03)))
    }

    @ViewBuilder
    private var centrepiece: some View {
        switch model.step {
        case .welcome: WelcomeCentre(dockDrop: dockDrop)
        case .permission:
            SettingsMiniature(allowed: model.permission.isTrusted, pointsAtAdd: model.showsHelp)
        case .tryIt: TryItCentre(model: model, live: model.live)
        case .done: DoneCentre(combo: model.hotKey)
        }
    }

    @ViewBuilder
    private var instrument: some View {
        switch model.step {
        case .welcome: Color.clear.frame(height: 1)
        case .permission: SettingsPath(allowed: model.permission.isTrusted)
        case .tryIt: ShortcutKeys(model: model, live: model.live)
        case .done: Color.clear.frame(height: 1)
        }
    }
}

// MARK: The ring

/// The logo's ring as an object: a mint ceramic tube with a ridge of light along its top and a soft shadow under it, its
/// faint full path showing what is left to close, and the pearl resting in the gap. Each time the ring grows the pearl
/// gives one small pulse; nothing else moves on its own.
struct LogoRing: View {
    /// The finished ring: 304 of 360 degrees, starting 12 degrees above the right-hand side.
    static let span = 304.0 / 360.0
    static let start = -12.0
    /// Where the pearl sits, in the middle of the gap.
    static let pearlAngle = -40.0

    let progress: Double
    /// The last step: the line thickens and the pearl grows to the proportions of the app icon.
    let finished: Bool
    let pulses: Int
    let pointer: CGSize

    @Environment(\.aproposReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var diameter: CGFloat { StageLayout.ringDiameter }
    private var line: CGFloat { finished ? 36 : 16 }
    private var pearl: CGFloat { finished ? 100 : 50 }

    var body: some View {
        ZStack {
            path(from: 0)
                .stroke(Brand.text.opacity(scheme == .dark ? 0.07 : 0.06), style: stroke(line))
            // Shadow, body, top light, ridge.
            path(from: Self.span - progress)
                .stroke(Color.black.opacity(scheme == .dark ? 0.2 : 0.12), style: stroke(line))
                .blur(radius: 14)
                .offset(y: 12)
            path(from: Self.span - progress)
                .stroke(Brand.mint, style: stroke(line))
            path(from: Self.span - progress)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .clear, .black.opacity(scheme == .dark ? 0.2 : 0.1)],
                        startPoint: .top, endPoint: .bottom),
                    style: stroke(line)
                )
            path(from: Self.span - progress)
                .stroke(
                    AngularGradient(
                        stops: [
                            .init(color: .white.opacity(0.04), location: 0),
                            .init(color: .white.opacity(0.38), location: 0.5),
                            .init(color: .white.opacity(0.04), location: 1),
                        ], center: .center, angle: .degrees(200 + pointer.width * 40 - pointer.height * 30)),
                    style: stroke(line * 0.3)
                )
                .offset(x: -line * 0.06, y: -line * 0.14)
                .blur(radius: line * 0.12)
                .blendMode(.plusLighter)
            RingPearl(size: pearl, pulses: pulses)
                .offset(x: diameter / 2 - line / 2)
                .rotationEffect(.degrees(Self.pearlAngle))
        }
        .frame(width: diameter, height: diameter)
        .animation(
            reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 1.1, dampingFraction: 0.84), value: progress
        )
        .accessibilityHidden(true)
    }

    private func stroke(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round)
    }

    private func path(from: Double) -> some Shape {
        Circle()
            .inset(by: line / 2)
            .trim(from: max(0, from), to: Self.span)
            .rotation(.degrees(Self.start))
    }
}

/// The pearl in the ring's gap: a glossy tangerine bead. It keeps still and pulses once each time the ring grows.
private struct RingPearl: View {
    let size: CGFloat
    let pulses: Int

    @Environment(\.aproposReduceMotion) private var reduceMotion

    private struct Beat {
        var swell = 1.0
        var ripple = 1.0
        var rippleOpacity = 0.0
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Brand.pearl)
                .shadow(color: Brand.pearl.opacity(0.45), radius: 12)
                .shadow(color: .black.opacity(0.28), radius: 6, y: 6)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.0), .black.opacity(0.18)], center: .init(x: 0.4, y: 0.35),
                        startRadius: size * 0.2, endRadius: size * 0.62))
            Ellipse()
                .fill(.white.opacity(0.45))
                .frame(width: size * 0.34, height: size * 0.22)
                .blur(radius: size * 0.06)
                .offset(x: -size * 0.15, y: -size * 0.22)
        }
        .frame(width: size, height: size)
        .keyframeAnimator(initialValue: Beat(), trigger: pulses) { content, beat in
            content
                .scaleEffect(beat.swell)
                .background {
                    Circle()
                        .stroke(Brand.pearl, lineWidth: 1.5)
                        .scaleEffect(beat.ripple)
                        .opacity(beat.rippleOpacity)
                }
        } keyframes: { _ in
            KeyframeTrack(\.swell) {
                SpringKeyframe(reduceMotion ? 1 : 1.16, duration: 0.25, spring: .snappy)
                SpringKeyframe(1, duration: 0.6, spring: .bouncy)
            }
            KeyframeTrack(\.ripple) {
                LinearKeyframe(1, duration: 0.05)
                CubicKeyframe(reduceMotion ? 1 : 2.8, duration: 0.9)
            }
            KeyframeTrack(\.rippleOpacity) {
                LinearKeyframe(reduceMotion ? 0 : 0.7, duration: 0.05)
                CubicKeyframe(0, duration: 0.9)
            }
        }
    }
}

// MARK: Welcome

/// The palette over four real apps. It moves to the next app every few seconds until the pointer is on the stage;
/// hovering an app in the dock shows that app at once. Under Reduce Motion it waits for the pointer.
private struct WelcomeCentre: View {
    /// How far below the palette's centre the dock sits: on the stage's instrument line.
    let dockDrop: CGFloat

    @State private var apps = StageSamples.apps()
    @State private var index = 0
    @State private var hovering = false
    @Environment(\.aproposReduceMotion) private var reduceMotion

    var body: some View {
        PaletteMiniature(app: apps[index], selected: 0)
            .animation(reduceMotion ? .easeOut(duration: 0.1) : Motion.easeOut(0.22), value: index)
            .overlay {
                MiniDock(apps: apps, current: index) { picked in
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { index = picked }
                }
                .fixedSize()
                .offset(y: dockDrop)
            }
            .onHover { hovering = $0 }
            .task(id: hovering) {
                guard !reduceMotion, !hovering else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3.6))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { index = (index + 1) % apps.count }
                }
            }
    }
}

/// A row of app icons like a slice of the Dock. The app the palette is showing sits a little higher.
private struct MiniDock: View {
    let apps: [StageApp]
    let current: Int
    let pick: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
                VStack(spacing: 5) {
                    AppIconImage(icon: app.icon, size: 40)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                        .scaleEffect(index == current ? 1.1 : 1, anchor: .bottom)
                        .offset(y: index == current ? -3 : 0)
                    Circle()
                        .fill(Brand.text2)
                        .frame(width: 4, height: 4)
                        .opacity(index == current ? 1 : 0)
                }
                .contentShape(Rectangle())
                .onHover { if $0 { pick(index) } }
                .onTapGesture { pick(index) }
                .accessibilityElement()
                .accessibilityLabel(app.name)
                .accessibilityAddTraits(index == current ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { pick(index) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.chip)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.glassEdge, lineWidth: 1))
        )
    }
}

// MARK: Palette miniature

/// The palette drawn small but true: its search field and app chip, the context it read, the rows with their tiles and
/// keys, the selection, and the footer. Built from the palette's own pieces (`IconTile`, `KeyCap`, `Theme`), so it
/// looks like the panel the person is about to use.
struct PaletteMiniature<Replacement: View>: View {
    let app: StageApp?
    var selected: Int?
    var placeholder: String?
    var opened = false
    @ViewBuilder var replacement: Replacement

    static var width: CGFloat { 300 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.divider).frame(height: 1)
            ZStack(alignment: .top) {
                if Replacement.self == EmptyView.self, let app {
                    rows(app)
                } else {
                    replacement
                }
            }
            .frame(height: 4 * 34 + 12, alignment: .top)
            footer
        }
        .frame(width: Self.width)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.glassTint))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.glassEdgeTop, Theme.glassEdge], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 22, y: 14)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .environment(\.interfaceMetrics, .metrics(for: .compact))
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: opened ? "checkmark.circle.fill" : "magnifyingglass")
                    .font(.system(size: 13, weight: opened ? .semibold : .regular))
                    .foregroundStyle(opened ? Theme.accentText : Theme.text2)
                    .contentTransition(.symbolEffect(.replace))
                Text(headerText)
                    .font(.system(size: 13.5))
                    .foregroundStyle(opened ? Theme.accentText : Theme.text3)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Spacer(minLength: 4)
                if let app {
                    HStack(spacing: 5) {
                        AppIconImage(icon: app.icon, size: 14)
                        Text(app.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(Theme.chip))
                    .id(app.name)
                    .transition(.opacity)
                }
            }
            if let context = app?.context {
                HStack(spacing: 4) {
                    Image(systemName: "scope").font(.system(size: 9.5, weight: .medium))
                    Text(context).font(.system(size: 11)).lineLimit(1)
                }
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(Capsule().fill(Theme.chip))
                .id(context)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerText: String {
        if opened, let app { return "Opened over \(app.name)" }
        if let placeholder { return placeholder }
        return "Search \(app?.name ?? "commands")"
    }

    private func rows(_ app: StageApp) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(app.rows.prefix(4).enumerated()), id: \.element.id) { offset, row in
                MiniRow(row: row)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(offset == selected ? Theme.highlight : .clear)
                    )
                    .modifier(RowRise(index: offset, stagger: 0.035, duration: 0.26, entrance: nil))
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .id(app.name)
        .transition(.opacity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Spacer()
            Text("Run").font(.system(size: 11)).foregroundStyle(Theme.text2)
            KeyCap(text: "↩", small: true)
            Rectangle().fill(Theme.divider).frame(width: 1, height: 12).padding(.horizontal, 3)
            Text("Actions").font(.system(size: 11)).foregroundStyle(Theme.text2)
            KeyCap(text: "⌘", small: true)
            KeyCap(text: "K", small: true)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

extension PaletteMiniature where Replacement == EmptyView {
    init(app: StageApp?, selected: Int? = nil, placeholder: String? = nil, opened: Bool = false) {
        self.init(app: app, selected: selected, placeholder: placeholder, opened: opened) { EmptyView() }
    }
}

/// One palette row at the compact size: tile, title, where it lives, and its keys.
private struct MiniRow: View {
    let row: StageRow

    var body: some View {
        HStack(spacing: 9) {
            IconTile(symbol: row.symbol, accented: row.isAction)
            Text(row.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .layoutPriority(1)
            Text(row.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text3)
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                ForEach(Array(row.caps.enumerated()), id: \.offset) { KeyCap(text: $0.element, small: true) }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
    }
}

// MARK: Permission

/// The Accessibility list of System Settings, as a window behind the guide: grey traffic lights, the page title, the
/// system's own sentence, and the list with Apropos in it. A pointer rests on Apropos's switch until access is given,
/// then the switch turns on. With the help open, the pointer moves to the add button instead.
private struct SettingsMiniature: View {
    let allowed: Bool
    let pointsAtAdd: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            Text("Allow the applications below to control your computer.")
                .font(.system(size: 11))
                .foregroundStyle(Brand.text2)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            VStack(spacing: 0) {
                placeholderRow(width: 74)
                divider
                aproposRow
                divider
                placeholderRow(width: 96)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(group))
            .padding(.horizontal, 12)
            HStack(spacing: 0) {
                Image(systemName: "plus").frame(width: 24, height: 20)
                Rectangle().fill(Brand.line).frame(width: 1, height: 12)
                Image(systemName: "minus").frame(width: 24, height: 20)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Brand.text2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(group))
            .padding(.leading, 12)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .anchorPreference(key: CursorTarget.self, value: .bounds) { ["add": $0] }
        }
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(windowFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 24, y: 14)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .overlayPreferenceValue(CursorTarget.self) { anchors in
            GeometryReader { proxy in
                if !allowed, let anchor = anchors[pointsAtAdd ? "add" : "switch"] {
                    let rect = proxy[anchor]
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.black)
                        .background(
                            Image(systemName: "cursorarrow").font(.system(size: 20, weight: .black))
                                .foregroundStyle(.white)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .position(x: rect.midX + (pointsAtAdd ? 2 : 8), y: rect.midY + 12)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: pointsAtAdd)
        .animation(.easeOut(duration: 0.2), value: allowed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(allowed ? "Apropos is allowed in Accessibility" : "Apropos is off in Accessibility")
    }

    private var windowFill: Color { scheme == .dark ? Color(white: 0.16) : Color(white: 0.97) }
    private var group: Color { scheme == .dark ? Color(white: 1, opacity: 0.05) : Color(white: 0, opacity: 0.04) }

    private var titleBar: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(Brand.text.opacity(0.16)).frame(width: 10, height: 10)
            }
            HStack(spacing: 12) {
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right").opacity(0.4)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Brand.text2)
            .padding(.leading, 12)
            Text("Accessibility")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.text)
                .padding(.leading, 6)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private var divider: some View {
        Rectangle().fill(Brand.line).frame(height: 1).padding(.leading, 42)
    }

    private func placeholderRow(width: CGFloat) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Brand.text.opacity(0.1)).frame(
                width: 20, height: 20)
            Capsule().fill(Brand.text.opacity(0.1)).frame(width: width, height: 7)
            Spacer()
            MiniSwitch(on: true).opacity(0.35)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
    }

    private var aproposRow: some View {
        HStack(spacing: 10) {
            if let image = Brand.image("BrandIcon", file: "app-icon.png") {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: 22, height: 22)
            }
            Text("Apropos").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Brand.text)
            Spacer()
            MiniSwitch(on: allowed)
                .anchorPreference(key: CursorTarget.self, value: .bounds) { ["switch": $0] }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }
}

private struct CursorTarget: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A small switch in the system's shape, on in mint.
private struct MiniSwitch: View {
    let on: Bool

    var body: some View {
        Capsule()
            .fill(on ? Brand.mint : Brand.text.opacity(0.16))
            .frame(width: 30, height: 18)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                    .frame(width: 14, height: 14)
                    .padding(2)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: on)
    }
}

/// Where the list lives in System Settings, so it can be found by hand.
private struct SettingsPath: View {
    let allowed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "gearshape").font(.system(size: 11))
            Text("System Settings")
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
            Text("Privacy & Security")
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
            Text("Accessibility")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Brand.text3)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Try it

/// The palette over the app the person really has open, with a few of its real menu commands. With only Finder open,
/// it says so and offers to open TextEdit. Once the shortcut has opened the panel, it says where.
private struct TryItCentre: View {
    let model: OnboardingModel
    let live: OnboardingLive

    private var hasRealApp: Bool { live.othersOpen && live.target != nil }

    var body: some View {
        Group {
            if !hasRealApp && !model.panelOpened {
                PaletteMiniature(app: live.target, placeholder: "Search") {
                    NothingOpen(launching: live.launching) { live.openHelper() }
                }
            } else if let app = live.target, model.permission.isTrusted, app.rows.isEmpty {
                PaletteMiniature(app: app, opened: model.panelOpened) {
                    if live.reading { LoadingRows().padding(.horizontal, -6) } else { ReadNote(app: app.name) }
                }
            } else if let app = live.target, model.permission.isTrusted {
                PaletteMiniature(app: app, selected: 0, opened: model.panelOpened)
            } else {
                PaletteMiniature(app: live.target, opened: model.panelOpened) {
                    ReadNote(app: live.target?.name, needsAccess: true)
                }
            }
        }
        .animation(.easeOut(duration: 0.24), value: live.target)
        .animation(.easeOut(duration: 0.24), value: model.panelOpened)
        .task(id: "\(live.target?.pid ?? 0)-\(model.permission.isTrusted)") {
            await live.readRows(trusted: model.permission.isTrusted)
        }
    }
}

/// The body of the miniature when there is nothing worth trying it in.
private struct NothingOpen: View {
    let launching: Bool
    let open: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("Only Finder is open")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Apropos lists the menus of the app you are in. Open one to try it there.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 230)
            Button(action: open) {
                HStack(spacing: 6) {
                    AppIconImage(icon: NSWorkspace.shared.icon(forFile: OnboardingLive.helperURL.path), size: 16)
                    Text(launching ? "Opening TextEdit" : "Open TextEdit")
                }
            }
            .buttonStyle(BrandButtonStyle(kind: .secondary))
            .disabled(launching)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The body of the miniature when the commands cannot be shown.
private struct ReadNote: View {
    let app: String?
    var needsAccess = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: needsAccess ? "lock" : "menubar.rectangle")
                .font(.system(size: 15))
                .foregroundStyle(Theme.text2)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.tile))
            Text(
                needsAccess
                    ? "With Accessibility on, \(app ?? "the app")'s commands show here."
                    : "\(app ?? "This app") has no menu commands to show."
            )
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.text3)
            .multilineTextAlignment(.center)
            .frame(width: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The shortcut as real keys. Each modifier lights while it is held, the whole shortcut lights once it has opened the
/// panel, and the line under the keys says what to do next.
private struct ShortcutKeys: View {
    let model: OnboardingModel
    let live: OnboardingLive

    private static let symbols: [String: ModifierSet] = ["⌃": .control, "⌥": .option, "⇧": .shift, "⌘": .command]

    var body: some View {
        let combo = model.hotKey
        let caps = combo.caps
        let allHeld = !combo.modifiers.isEmpty && live.held.isSuperset(of: combo.modifiers)
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Array(caps.enumerated()), id: \.offset) { index, cap in
                    let isKey = index == caps.count - 1
                    let lit = model.panelOpened || (!isKey && Self.symbols[cap].map { live.held.contains($0) } == true)
                    BigKeyCap(text: cap, wide: isKey && cap.count > 1, lit: lit)
                }
            }
            Text(caption(allHeld: allHeld, key: caps.last ?? ""))
                .font(.system(size: 12))
                .foregroundStyle(model.panelOpened ? Brand.mint : Brand.text3)
                .contentTransition(.opacity)
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: live.held)
        .animation(.easeOut(duration: 0.2), value: model.panelOpened)
        .onAppear { live.watchKeys(trusted: model.permission.isTrusted) }
        .onDisappear { live.stopWatchingKeys() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shortcut \(combo.display)")
    }

    private func caption(allHeld: Bool, key: String) -> String {
        if model.panelOpened { return "Works the same from any app" }
        if allHeld { return "Now press \(key)" }
        return "Press it here or in any app"
    }
}

/// A full-size key, raised until it is pressed.
struct BigKeyCap: View {
    let text: String
    var wide = false
    var lit = false

    var body: some View {
        Text(text)
            .font(.system(size: wide ? 14 : 17, weight: .medium))
            .foregroundStyle(lit ? Theme.accentText : Brand.text)
            .frame(width: wide ? 132 : 46, height: 46)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(lit ? Theme.accentSoft : Brand.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(lit ? Theme.accentText.opacity(0.5) : Brand.line, lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.22))
                    .offset(y: lit ? 0.5 : 3)
            )
            .offset(y: lit ? 2.5 : 0)
    }
}

// MARK: Done

/// The finished logo holds the one thing to remember: the shortcut.
private struct DoneCentre: View {
    let combo: HotKeyCombo

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(Array(combo.caps.enumerated()), id: \.offset) { index, cap in
                    BigKeyCap(text: cap, wide: index == combo.caps.count - 1 && cap.count > 1)
                }
            }
            Text("From any app")
                .font(.system(size: 12))
                .foregroundStyle(Brand.text3)
        }
    }
}

/// A slice of the menu bar across the top of the stage, with Apropos's icon picked out where it really lives. The
/// clock is the real time.
private struct MenuBarStrip: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo").font(.system(size: 12))
            Text("Finder").font(.system(size: 12, weight: .semibold))
            ForEach(["File", "Edit", "View"], id: \.self) { Text($0).font(.system(size: 12)) }
            Spacer(minLength: 8)
            BrandGlyph()
                .frame(width: 14, height: 14)
                .foregroundStyle(Brand.text)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Brand.text.opacity(0.14)))
                .overlay(alignment: .bottom) {
                    Text("Apropos")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Brand.text2)
                        .fixedSize()
                        .offset(y: 22)
                }
            Image(systemName: "wifi").font(.system(size: 12))
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 12))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(Brand.text.opacity(0.85))
        .padding(.horizontal, 22)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background {
            Brand.text.opacity(0.05)
                .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
                .clipShape(
                    UnevenRoundedRectangle(topLeadingRadius: Brand.panelRadius, topTrailingRadius: Brand.panelRadius))
        }
        .accessibilityHidden(true)
    }
}
