import CoreGraphics
import Foundation

/// Where the palette goes: horizontally centred on the screen the person is using, in the upper part of it.
public enum PanelPlacement {
    public static let size = CGSize(width: 720, height: 480)

    /// `visibleFrame` is the screen's usable area in AppKit coordinates (origin bottom-left).
    public static func frame(in visibleFrame: CGRect, size: CGSize = PanelPlacement.size) -> CGRect {
        let x = visibleFrame.midX - size.width / 2
        // The top edge of the panel sits about a fifth of the way down, which keeps the search field near eye level.
        let top = visibleFrame.maxY - visibleFrame.height * 0.2
        return CGRect(x: x.rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height)
    }

    /// The screen whose frame contains `point`, falling back to the first one. Generic over the frame list so it can be
    /// tested without real screens.
    public static func index(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) } ?? (frames.isEmpty ? nil : 0)
    }

    // MARK: Position

    /// Where the panel sits when it opens.
    public enum Mode: String, CaseIterable, Sendable {
        case centered, remember, underMenuBar

        public var title: String {
            switch self {
            case .centered: "Centered"
            case .remember: "Where you left it"
            case .underMenuBar: "Under the menu bar"
            }
        }
    }

    /// A position as fractions of a screen's usable area: the panel's horizontal centre and its top edge, measured from
    /// the bottom left. Fractions keep it in the same place when a display changes resolution.
    public struct Anchor: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// The frame for a mode. A remembered anchor is used only in `remember` mode, and the result is always kept on screen.
    public static func frame(
        in visibleFrame: CGRect, size: CGSize = PanelPlacement.size, mode: Mode, anchor: Anchor?
    ) -> CGRect {
        switch mode {
        case .centered:
            return frame(in: visibleFrame, size: size)
        case .underMenuBar:
            let x = visibleFrame.midX - size.width / 2
            return CGRect(x: x.rounded(), y: (visibleFrame.maxY - 12 - size.height).rounded(), width: size.width, height: size.height)
        case .remember:
            guard let anchor else { return frame(in: visibleFrame, size: size) }
            let midX = visibleFrame.minX + visibleFrame.width * anchor.x
            let top = visibleFrame.minY + visibleFrame.height * anchor.y
            let moved = CGRect(x: (midX - size.width / 2).rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height)
            return clamp(moved, to: visibleFrame)
        }
    }

    /// The anchor that reproduces `frame` on `visibleFrame`.
    public static func anchor(for frame: CGRect, in visibleFrame: CGRect) -> Anchor {
        Anchor(
            x: Double((frame.midX - visibleFrame.minX) / max(visibleFrame.width, 1)),
            y: Double((frame.maxY - visibleFrame.minY) / max(visibleFrame.height, 1)))
    }

    /// Moves `frame` the least needed to lie inside `visibleFrame`. A frame larger than the area is pinned to its top left.
    public static func clamp(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        var result = frame
        if result.maxX > visibleFrame.maxX { result.origin.x = visibleFrame.maxX - result.width }
        if result.minX < visibleFrame.minX { result.origin.x = visibleFrame.minX }
        if result.maxY > visibleFrame.maxY { result.origin.y = visibleFrame.maxY - result.height }
        if result.minY < visibleFrame.minY { result.origin.y = visibleFrame.minY }
        return result
    }

    /// A line shown while dragging: the edges of the panel's home place. It is bright while the panel is snapped to it.
    public struct Guide: Equatable, Sendable {
        public enum Axis: Sendable { case vertical, horizontal }
        public let axis: Axis
        /// The x of a vertical line, or the y of a horizontal one, in screen coordinates.
        public let position: CGFloat
        public let isActive: Bool

        public init(axis: Axis, position: CGFloat, isActive: Bool = false) {
            self.axis = axis
            self.position = position
            self.isActive = isActive
        }
    }

    /// Pulls the panel onto its home place when an edge comes within `threshold` points: the left and right edges to the
    /// two vertical lines, the top edge to the horizontal one. All three lines are returned, so they can all be drawn
    /// during the drag, with the ones snapped to marked active.
    public static func snap(
        _ frame: CGRect, in visibleFrame: CGRect, threshold: CGFloat = 12
    ) -> (frame: CGRect, guides: [Guide]) {
        let home = Self.frame(in: visibleFrame, size: frame.size)
        var result = frame
        var leftActive = false
        var topActive = false
        let toLeft = home.minX - frame.minX
        let toRight = home.maxX - frame.maxX
        if abs(toLeft) <= threshold || abs(toRight) <= threshold {
            result.origin.x += abs(toLeft) <= abs(toRight) ? toLeft : toRight
            leftActive = true
        }
        let toTop = home.maxY - frame.maxY
        if abs(toTop) <= threshold {
            result.origin.y += toTop
            topActive = true
        }
        let guides = [
            Guide(axis: .vertical, position: home.minX, isActive: leftActive),
            Guide(axis: .vertical, position: home.maxX, isActive: leftActive),
            Guide(axis: .horizontal, position: home.maxY, isActive: topActive),
        ]
        return (result, guides)
    }
}

/// Where the person left the panel, per display, in a small file.
public final class PanelPositionStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var anchors: [String: PanelPlacement.Anchor]

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
            let stored = try? JSONDecoder().decode([String: PanelPlacement.Anchor].self, from: data)
        {
            anchors = stored
        } else {
            anchors = [:]
        }
    }

    /// `~/Library/Application Support/Apropos/panel-position.json`.
    @MainActor public static var defaultURL: URL {
        UsageStore.defaultURL.deletingLastPathComponent().appendingPathComponent("panel-position.json")
    }

    public func anchor(forDisplay key: String) -> PanelPlacement.Anchor? { lock.withLock { anchors[key] } }

    public func set(_ anchor: PanelPlacement.Anchor, forDisplay key: String) {
        lock.withLock {
            anchors[key] = anchor
            save()
        }
    }

    public func forgetAll() {
        lock.withLock {
            anchors = [:]
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(anchors) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
