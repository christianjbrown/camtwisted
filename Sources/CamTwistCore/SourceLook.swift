import CoreGraphics
import Foundation

/// How one source's own picture is treated before it is placed: colour
/// correction, zooming in, and flipping. Every source can have its own.
public struct SourceAdjustments: Codable, Equatable, Sendable {
    /// Below 1 the picture is zoomed out: all of it shows, smaller, with
    /// nothing around it.
    public static let zoomRange: ClosedRange<Double> = 0.05...8
    public static let noiseReductionRange: ClosedRange<Double> = 0...0.1
    public static let sharpnessRange: ClosedRange<Double> = 0...2
    /// How much noise reduction sharpens what it has smoothed, unless told otherwise.
    public static let defaultSharpness = 0.4
    public static let brightnessRange: ClosedRange<Double> = -1...1
    public static let contrastRange: ClosedRange<Double> = 0...4
    public static let saturationRange: ClosedRange<Double> = 0...2
    public static let gammaRange: ClosedRange<Double> = 0.1...3
    public static let gainRange: ClosedRange<Double> = 0...2
    /// The value of every multiplying control when it changes nothing.
    public static let unchanged = 1.0

    /// Added to every colour: 0 leaves the picture as it is.
    public var brightness: Double
    public var contrast: Double
    public var saturation: Double
    public var gamma: Double
    public var red: Double
    public var green: Double
    public var blue: Double
    /// How far the picture is magnified about its middle: 1 shows all of it.
    public var zoom: Double
    public var flipsHorizontally: Bool
    public var flipsVertically: Bool
    /// How much grain is smoothed away: 0 leaves the picture as it is.
    public var noiseReduction: Double
    /// How much the smoothed picture is sharpened again. Only matters
    /// while noise reduction is on.
    public var sharpness: Double

    public init(
        brightness: Double = 0,
        contrast: Double = SourceAdjustments.unchanged,
        saturation: Double = SourceAdjustments.unchanged,
        gamma: Double = SourceAdjustments.unchanged,
        red: Double = SourceAdjustments.unchanged,
        green: Double = SourceAdjustments.unchanged,
        blue: Double = SourceAdjustments.unchanged,
        zoom: Double = SourceAdjustments.unchanged,
        flipsHorizontally: Bool = false,
        flipsVertically: Bool = false,
        noiseReduction: Double = 0,
        sharpness: Double = SourceAdjustments.defaultSharpness
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.gamma = gamma
        self.red = red
        self.green = green
        self.blue = blue
        self.zoom = zoom
        self.flipsHorizontally = flipsHorizontally
        self.flipsVertically = flipsVertically
        self.noiseReduction = noiseReduction
        self.sharpness = sharpness
    }

    /// Whether grain is being smoothed away at all.
    public var reducesNoise: Bool { noiseReduction > 0 }

    /// Whether the picture comes out exactly as it went in.
    public var isNeutral: Bool { self == SourceAdjustments() }

    /// Whether any of the colour controls has been moved.
    public var changesColor: Bool {
        var plain = self
        plain.zoom = Self.unchanged
        plain.flipsHorizontally = false
        plain.flipsVertically = false
        plain.noiseReduction = 0
        plain.sharpness = Self.defaultSharpness
        return !plain.isNeutral
    }

    /// The part of a picture that stays in view once zoomed: a rectangle
    /// of the picture's own shape about its middle. Zoomed out, it is
    /// larger than the picture, which then sits in the middle of it.
    public func visibleRegion(of extent: CGRect) -> CGRect {
        let magnification = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let width = extent.width / magnification
        let height = extent.height / magnification
        return CGRect(x: extent.midX - width / 2, y: extent.midY - height / 2, width: width, height: height)
    }
}

/// What about a source's placement an animation moves.
public enum AnimatedProperty: String, Codable, CaseIterable, Sendable {
    case positionX
    case positionY
    case size
    case rotation
    case tilt
    case swing
}

/// How an animation carries on once it reaches its end.
public enum AnimationMode: String, Codable, CaseIterable, Sendable {
    /// Plays through and stays at the end.
    case once
    /// Jumps back to the start and plays again.
    case loop
    /// Plays forwards, then backwards, for ever.
    case backAndForth
}

/// One property of a source's placement changing over time.
public struct SourceAnimation: Codable, Equatable, Identifiable, Sendable {
    public static let defaultDuration = 2.0
    public static let durationRange: ClosedRange<Double> = 0.1...60

    public let id: UUID
    public var property: AnimatedProperty
    public var from: Double
    public var to: Double
    /// Seconds from start to end.
    public var duration: Double
    public var mode: AnimationMode

    public init(
        id: UUID = UUID(),
        property: AnimatedProperty,
        from: Double,
        to: Double,
        duration: Double = SourceAnimation.defaultDuration,
        mode: AnimationMode = .loop
    ) {
        self.id = id
        self.property = property
        self.from = from
        self.to = to
        self.duration = duration
        self.mode = mode
    }

    /// The property's value a number of seconds after the animation began.
    public func value(at elapsed: TimeInterval) -> Double {
        from + (to - from) * AnimationClock.progress(elapsed: elapsed, duration: duration, mode: mode)
    }

    /// A sensible start and end for a property, to begin editing from:
    /// a full turn for the three rotations, a short slide or swell otherwise.
    public static func starter(for property: AnimatedProperty, around current: Double) -> SourceAnimation {
        switch property {
        case .rotation, .tilt, .swing:
            return SourceAnimation(property: property, from: 0, to: Self.fullTurn)
        case .positionX, .positionY:
            return SourceAnimation(property: property, from: current - Self.slide, to: current + Self.slide, mode: .backAndForth)
        case .size:
            return SourceAnimation(property: property, from: current, to: current * Self.swell, mode: .backAndForth)
        }
    }

    private static let fullTurn = 360.0
    private static let slide = 0.1
    private static let swell = 1.5
}

public enum AnimationClock {
    /// How far through an animation is, from 0 at its start to 1 at its end.
    public static func progress(elapsed: TimeInterval, duration: TimeInterval, mode: AnimationMode) -> Double {
        guard duration > 0, elapsed > 0 else { return elapsed > 0 ? 1 : 0 }
        let laps = elapsed / duration
        switch mode {
        case .once:
            return min(laps, 1)
        case .loop:
            return laps.truncatingRemainder(dividingBy: 1)
        case .backAndForth:
            let phase = laps.truncatingRemainder(dividingBy: 2)
            return phase <= 1 ? phase : 2 - phase
        }
    }
}

public extension PictureInPictureSettings {
    /// These settings as they stand a number of seconds into their
    /// animations: each animation overrides the one property it moves.
    func animated(by animations: [SourceAnimation], elapsed: TimeInterval) -> PictureInPictureSettings {
        var settings = self
        for animation in animations {
            let value = animation.value(at: elapsed)
            switch animation.property {
            case .positionX: settings.center.x = value
            case .positionY: settings.center.y = value
            case .size: settings.scale = value
            case .rotation: settings.rotation = value
            case .tilt: settings.tilt = value
            case .swing: settings.swing = value
            }
        }
        return settings
    }

    /// The current value of a property, for starting an animation from.
    func value(of property: AnimatedProperty) -> Double {
        switch property {
        case .positionX: return center.x
        case .positionY: return center.y
        case .size: return scale
        case .rotation: return rotation
        case .tilt: return tilt
        case .swing: return swing
        }
    }
}

/// The four corners of a picture once it has been turned in space.
public struct Quadrilateral: Equatable, Sendable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint

    public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }
}

/// Works out where a flat picture's corners land when it is turned about
/// its middle and seen with perspective. Coordinates have y going up.
public enum Perspective {
    private static let halfTurnDegrees = 180.0
    /// The eye sits this many canvas widths in front of the picture. Closer
    /// would exaggerate the perspective, further would flatten it.
    private static let eyeDistanceInWidths: CGFloat = 2
    /// A corner may come no nearer the eye than this share of the distance,
    /// so a huge picture swung round cannot pass through the eye.
    private static let nearestApproach: CGFloat = 0.1

    /// - Parameters:
    ///   - rotation: clockwise turn in the picture's own plane, in degrees.
    ///   - tilt: turn about the horizontal axis; positive leans the top away.
    ///   - swing: turn about the vertical axis; positive swings the right side away.
    public static func corners(
        of frame: CGRect, rotation: Double, tilt: Double, swing: Double, canvasWidth: CGFloat
    ) -> Quadrilateral {
        let eye = max(canvasWidth, 1) * eyeDistanceInWidths
        func place(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            // Turn in the plane (clockwise, so the angle is negated), then
            // lean back about the horizontal axis, then swing about the vertical.
            let spin = -radians(rotation)
            var point = (x: x * cos(spin) - y * sin(spin), y: x * sin(spin) + y * cos(spin), z: CGFloat(0))
            let lean = radians(tilt)
            point = (point.x, point.y * cos(lean) - point.z * sin(lean), point.y * sin(lean) + point.z * cos(lean))
            let turn = radians(swing)
            point = (point.x * cos(turn) - point.z * sin(turn), point.y, point.x * sin(turn) + point.z * cos(turn))
            // Things further from the eye (larger z) are drawn smaller.
            let scale = eye / max(eye + point.z, eye * nearestApproach)
            return CGPoint(x: frame.midX + point.x * scale, y: frame.midY + point.y * scale)
        }
        let halfWidth = frame.width / 2
        let halfHeight = frame.height / 2
        return Quadrilateral(
            topLeft: place(-halfWidth, halfHeight),
            topRight: place(halfWidth, halfHeight),
            bottomRight: place(halfWidth, -halfHeight),
            bottomLeft: place(-halfWidth, -halfHeight)
        )
    }

    private static func radians(_ degrees: Double) -> CGFloat {
        CGFloat(degrees * .pi / halfTurnDegrees)
    }
}
