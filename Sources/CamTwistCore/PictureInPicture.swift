import CoreGraphics
import Foundation

/// A corner of the canvas. Coordinates follow Core Image: the origin is the
/// bottom left, so "top" means the larger y.
public enum Corner: String, Codable, CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }
}

/// How a small picture sits on top of the picture so far: where, how big,
/// and at what angle. Every source has the same four settings.
public struct PictureInPictureSettings: Equatable, Sendable {
    public static let defaultScale = 0.3
    public static let defaultMargin = 0.03
    /// Up to three times the canvas, so a picture can be blown up past the edges.
    public static let scaleRange: ClosedRange<Double> = 0.05...3
    public static let rotationRange: ClosedRange<Double> = -180...180
    /// Half a canvas beyond each edge, so a picture can sit partly or
    /// wholly off screen on purpose.
    public static let positionRange: ClosedRange<Double> = -0.5...1.5
    /// Width over height of the camera's picture, used when snapping to a corner.
    public static let cameraAspect = Double(CameraContract.width) / Double(CameraContract.height)

    /// Where the middle of the small picture sits, in fractions of the
    /// canvas from its bottom left.
    public var center: CGPoint
    /// Width of the small picture as a fraction of the canvas width.
    public var scale: Double
    /// Clockwise turn in degrees.
    public var rotation: Double
    /// Turn about the horizontal axis in degrees: the top leans away.
    public var tilt: Double
    /// Turn about the vertical axis in degrees: the right side swings away.
    public var swing: Double

    public init(
        center: CGPoint,
        scale: Double = PictureInPictureSettings.defaultScale,
        rotation: Double = 0,
        tilt: Double = 0,
        swing: Double = 0
    ) {
        self.center = center
        self.scale = scale
        self.rotation = rotation
        self.tilt = tilt
        self.swing = swing
    }

    /// Whether the picture is turned out of its own plane, and so needs
    /// drawing with perspective.
    public var isTurnedInSpace: Bool { tilt != 0 || swing != 0 }

    /// A picture tucked into a corner, a small margin in from the edges.
    public init(
        corner: Corner = .bottomRight,
        scale: Double = PictureInPictureSettings.defaultScale,
        margin: Double = PictureInPictureSettings.defaultMargin,
        canvasAspect: Double = PictureInPictureSettings.cameraAspect
    ) {
        self.init(
            center: Self.center(for: corner, scale: scale, margin: margin, canvasAspect: canvasAspect),
            scale: scale
        )
    }

    /// Sizes the picture by a drag between two points, in fractions of the
    /// canvas: dragging away from its middle grows it, towards shrinks it.
    public mutating func resize(
        draggingFrom start: CGPoint, to end: CGPoint, canvasAspect: Double = PictureInPictureSettings.cameraAspect
    ) {
        let before = Self.offset(of: start, from: center, canvasAspect: canvasAspect)
        let after = Self.offset(of: end, from: center, canvasAspect: canvasAspect)
        let reach = hypot(before.x, before.y)
        // A drag that starts on the middle has no direction to grow in.
        guard reach > Self.minimumDragReach else { return }
        let wanted = scale * hypot(after.x, after.y) / reach
        scale = min(max(wanted, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    /// Turns the picture by a drag between two points round its middle, in
    /// fractions of the canvas with up as positive.
    public mutating func turn(
        draggingFrom start: CGPoint, to end: CGPoint, canvasAspect: Double = PictureInPictureSettings.cameraAspect
    ) {
        let before = Self.offset(of: start, from: center, canvasAspect: canvasAspect)
        let after = Self.offset(of: end, from: center, canvasAspect: canvasAspect)
        // Angles run anticlockwise with up positive; rotation is clockwise.
        let swept = (atan2(after.y, after.x) - atan2(before.y, before.x)) * Self.halfTurn / .pi
        let turned = (rotation - swept).truncatingRemainder(dividingBy: Self.fullTurn)
        if turned > Self.halfTurn {
            rotation = turned - Self.fullTurn
        } else if turned < -Self.halfTurn {
            rotation = turned + Self.fullTurn
        } else {
            rotation = turned
        }
    }

    /// A point's offset from another in square units, the canvas being wider than tall.
    private static func offset(of point: CGPoint, from origin: CGPoint, canvasAspect: Double) -> CGPoint {
        CGPoint(x: (point.x - origin.x) * canvasAspect, y: point.y - origin.y)
    }

    private static let minimumDragReach = 0.01
    private static let halfTurn = 180.0
    private static let fullTurn = 360.0

    /// Moves the picture into a corner, keeping its size and angle.
    public mutating func snap(to corner: Corner, canvasAspect: Double = PictureInPictureSettings.cameraAspect) {
        center = Self.center(for: corner, scale: scale, margin: Self.defaultMargin, canvasAspect: canvasAspect)
    }

    /// The centre that puts a picture of the canvas's own shape into a
    /// corner. The margin is a fraction of the canvas width on both axes.
    static func center(for corner: Corner, scale: Double, margin: Double, canvasAspect: Double) -> CGPoint {
        let half = scale / 2
        let horizontal = margin + half
        let vertical = margin * canvasAspect + half
        return CGPoint(
            x: corner.isLeft ? horizontal : 1 - horizontal,
            y: corner.isBottom ? vertical : 1 - vertical
        )
    }
}

extension PictureInPictureSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case center, scale, rotation, tilt, swing
        // Saved by earlier versions, which placed pictures by corner.
        case corner, margin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? Self.defaultScale
        if let center = try container.decodeIfPresent(CGPoint.self, forKey: .center) {
            self.init(center: center, scale: scale)
        } else {
            let corner = try container.decodeIfPresent(Corner.self, forKey: .corner) ?? .bottomRight
            let margin = try container.decodeIfPresent(Double.self, forKey: .margin) ?? Self.defaultMargin
            self.init(corner: corner, scale: scale, margin: margin)
        }
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        tilt = try container.decodeIfPresent(Double.self, forKey: .tilt) ?? 0
        swing = try container.decodeIfPresent(Double.self, forKey: .swing) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(center, forKey: .center)
        try container.encode(scale, forKey: .scale)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(tilt, forKey: .tilt)
        try container.encode(swing, forKey: .swing)
    }
}

public enum PictureInPictureLayout {
    /// The frame of the small picture before any turn: as wide as the
    /// settings ask, as tall as the content's own shape needs, centred where
    /// the settings say. It may hang off the canvas, or cover more than all
    /// of it: what falls outside is simply not seen.
    public static func frame(
        for content: CGSize,
        in canvas: CGSize,
        settings: PictureInPictureSettings
    ) -> CGRect {
        guard content.width > 0, content.height > 0 else { return .zero }
        let scale = min(
            max(settings.scale, PictureInPictureSettings.scaleRange.lowerBound),
            PictureInPictureSettings.scaleRange.upperBound
        )
        let width = canvas.width * scale
        let height = width * content.height / content.width
        return CGRect(
            x: settings.center.x * canvas.width - width / 2,
            y: settings.center.y * canvas.height - height / 2,
            width: width,
            height: height
        )
    }
}
