import CoreGraphics

/// Where the palette goes: horizontally centred on the screen the person is using, in the upper part of it.
public enum PanelPlacement {
    public static let size = CGSize(width: 720, height: 520)

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
}
