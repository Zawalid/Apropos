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

    /// A line to show while dragging: where the panel's centre would line up with the screen's centre or a third.
    public struct Guide: Equatable, Sendable {
        public enum Axis: Sendable { case vertical, horizontal }
        public let axis: Axis
        /// The x of a vertical line, or the y of a horizontal one, in screen coordinates.
        public let position: CGFloat
    }

    /// Pulls the panel's centre onto the nearest centre or third line of the screen when it is within `threshold` points,
    /// and returns the lines it snapped to.
    public static func snap(
        _ frame: CGRect, in visibleFrame: CGRect, threshold: CGFloat = 10
    ) -> (frame: CGRect, guides: [Guide]) {
        var result = frame
        var guides: [Guide] = []
        let xs = [1.0 / 3, 0.5, 2.0 / 3].map { visibleFrame.minX + visibleFrame.width * $0 }
        let ys = [1.0 / 3, 0.5, 2.0 / 3].map { visibleFrame.minY + visibleFrame.height * $0 }
        if let x = xs.min(by: { abs($0 - frame.midX) < abs($1 - frame.midX) }), abs(x - frame.midX) <= threshold {
            result.origin.x += x - frame.midX
            guides.append(Guide(axis: .vertical, position: x))
        }
        if let y = ys.min(by: { abs($0 - frame.midY) < abs($1 - frame.midY) }), abs(y - frame.midY) <= threshold {
            result.origin.y += y - frame.midY
            guides.append(Guide(axis: .horizontal, position: y))
        }
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
