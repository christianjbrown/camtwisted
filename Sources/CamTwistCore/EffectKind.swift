import CoreGraphics
import Foundation

/// What an effect does to the picture.
public enum EffectKind: String, Codable, Sendable {
    /// Takes the picture in and hands a changed picture back.
    case filter
    /// Blends from the picture to a second, target picture over time.
    case transition
    /// Draws by itself, on top of the picture.
    case overlay
}

/// Moves things that sit on top of the picture, as dragging them does.
public enum OverlayPosition {
    /// Overlays are placed across the picture from -1 to 1.
    private static let unitsAcross = 2.0

    /// An overlay's X and Y position after a drag. `delta` is the drag in
    /// fractions of the picture's width and height, with up as positive.
    /// Both axes are measured in units of the picture's width, so the
    /// vertical part is scaled by the picture's shape.
    public static func moved(x: Double, y: Double, by delta: CGPoint, canvas: CGSize) -> (x: Double, y: Double) {
        guard canvas.width > 0 else { return (x, y) }
        return (
            x + delta.x * unitsAcross,
            y + delta.y * unitsAcross * canvas.height / canvas.width
        )
    }

    /// Where an overlay's X and Y position puts it, in fractions of the
    /// picture with up as positive.
    public static func unitPoint(x: Double, y: Double, canvas: CGSize) -> CGPoint {
        guard canvas.height > 0 else { return CGPoint(x: Self.middle, y: Self.middle) }
        return CGPoint(
            x: middle + x / unitsAcross,
            y: middle + y / unitsAcross * canvas.width / canvas.height
        )
    }

    private static let middle = 0.5

    /// The middle of a picture in picture after a drag. It is free to leave
    /// the canvas: part of a picture may be off screen on purpose.
    public static func moved(center: CGPoint, by delta: CGPoint) -> CGPoint {
        CGPoint(x: center.x + delta.x, y: center.y + delta.y)
    }
}
