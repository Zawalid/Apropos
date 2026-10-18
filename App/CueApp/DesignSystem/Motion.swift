import SwiftUI

/// The only motion in the palette. Opening and closing have none (the panel is used hundreds of times a day); motion is
/// kept for things that explain a change: the selection moving, rows arriving for a new app, the actions popover.
enum Motion {
    /// A strong ease-out: fast start, long gentle settle.
    static func easeOut(_ duration: Double) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    static let selection = easeOut(0.16)
    static let popover = easeOut(0.16)
    static let rowRise: CGFloat = 4
    static let rowDuration = 0.2
    static let rowStagger = 0.014
    /// Staggering more rows than fit on screen only delays the ones that are visible.
    static let rowStaggerLimit = 14
}

/// Arms the row entrance for a short window after the target app changes, so that rows created by scrolling or by
/// typing a query appear at once while a new app's list rises in.
@MainActor
final class RowEntrance {
    private var until = Date.distantPast
    private var armedFor: pid_t?

    func arm(for pid: pid_t?) {
        guard pid != armedFor else { return }
        armedFor = pid
        until = Date().addingTimeInterval(0.7)
    }

    var isArmed: Bool { Date() < until }
}

/// Rises a view by a few points while fading it in, staggered by its position. Skipped under Reduce Motion. With an
/// `entrance` it only animates while that gate is armed; without one it always does.
struct RowRise: ViewModifier {
    let index: Int
    let stagger: Double
    let duration: Double
    let entrance: RowEntrance?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : Motion.rowRise)
            .onAppear {
                guard !shown else { return }
                if reduceMotion || !(entrance?.isArmed ?? true) {
                    shown = true
                    return
                }
                let delay = Double(min(index, Motion.rowStaggerLimit)) * stagger
                withAnimation(Motion.easeOut(duration).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func rowRise(index: Int, entrance: RowEntrance) -> some View {
        modifier(RowRise(index: index, stagger: Motion.rowStagger, duration: Motion.rowDuration, entrance: entrance))
    }

    /// Context chips rise in a little slower than rows, one after the other.
    func chipRise(index: Int) -> some View {
        modifier(RowRise(index: index, stagger: 0.035, duration: 0.22, entrance: nil))
    }
}
