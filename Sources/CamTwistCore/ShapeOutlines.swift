import CoreGraphics
import Foundation

/// How one shape is named and drawn: the shape of its box, whether it is an
/// ellipse, and its corners if it has straight sides. Each shape is its own
/// type, so a new shape is a new type and one line in `ShapeOutlines`.
public protocol ShapeOutline: Sendable {
    /// What the shape is called where shapes are chosen.
    var name: String { get }
    /// Width over height of the box the shape is drawn in.
    func aspect(canvasAspect: Double) -> Double
    /// Round shapes are ellipses and have no corners.
    var isRound: Bool { get }
    /// The corners of a straight-sided shape, as fractions of its box, in drawing order.
    var corners: [CGPoint] { get }
}

/// The unit square's own positions, which shapes are drawn on.
enum UnitSquare {
    static let centre = 0.5
    static let bottomLeft = CGPoint(x: 0, y: 0)
    static let bottomRight = CGPoint(x: 1, y: 0)
    static let topRight = CGPoint(x: 1, y: 1)
    static let topLeft = CGPoint(x: 0, y: 1)
    static let bottomMiddle = CGPoint(x: centre, y: 0)
    static let rightMiddle = CGPoint(x: 1, y: centre)
    static let topMiddle = CGPoint(x: centre, y: 1)
    static let leftMiddle = CGPoint(x: 0, y: centre)
}

/// A shape as wide as it is tall.
private protocol SquareBoxOutline: ShapeOutline {}

extension SquareBoxOutline {
    func aspect(canvasAspect: Double) -> Double { 1 }
}

/// A shape that takes the picture's shape.
private protocol PictureBoxOutline: ShapeOutline {}

extension PictureBoxOutline {
    func aspect(canvasAspect: Double) -> Double { canvasAspect }
}

/// A shape with straight sides.
private protocol StraightSidedOutline: ShapeOutline {}

extension StraightSidedOutline {
    var isRound: Bool { false }
}

/// A shape that is an ellipse.
private protocol RoundOutline: ShapeOutline {}

extension RoundOutline {
    var isRound: Bool { true }
    var corners: [CGPoint] { [] }
}

struct RectangleOutline: PictureBoxOutline, StraightSidedOutline {
    var name: String { "Rectangle" }
    var corners: [CGPoint] { [UnitSquare.bottomLeft, UnitSquare.bottomRight, UnitSquare.topRight, UnitSquare.topLeft] }
}

struct SquareOutline: SquareBoxOutline, StraightSidedOutline {
    var name: String { "Square" }
    var corners: [CGPoint] { RectangleOutline().corners }
}

struct CircleOutline: SquareBoxOutline, RoundOutline {
    var name: String { "Circle" }
}

struct EllipseOutline: PictureBoxOutline, RoundOutline {
    var name: String { "Ellipse" }
}

struct TriangleOutline: PictureBoxOutline, StraightSidedOutline {
    var name: String { "Triangle" }
    var corners: [CGPoint] { [UnitSquare.bottomLeft, UnitSquare.bottomRight, UnitSquare.topMiddle] }
}

struct DiamondOutline: SquareBoxOutline, StraightSidedOutline {
    var name: String { "Diamond" }
    var corners: [CGPoint] {
        [UnitSquare.bottomMiddle, UnitSquare.rightMiddle, UnitSquare.topMiddle, UnitSquare.leftMiddle]
    }
}

struct StarOutline: SquareBoxOutline, StraightSidedOutline {
    private static let tips = 5

    var name: String { "Star" }
    /// How far in the star's inner corners sit, as a share of its radius.
    private static let innerRadius = 0.4

    var corners: [CGPoint] {
        let centre = UnitSquare.centre
        return (0..<(Self.tips * 2)).map { index in
            // Points alternate between the tips and the inner corners,
            // starting from the tip at the top.
            let radius = index.isMultiple(of: 2) ? centre : centre * Self.innerRadius
            let angle = Double.pi / 2 + Double(index) * Double.pi / Double(Self.tips)
            return CGPoint(x: centre + radius * cos(angle), y: centre + radius * sin(angle))
        }
    }
}

/// The one place a kind of shape is matched to how it is drawn.
public enum ShapeOutlines {
    public static func outline(for kind: ShapeKind) -> ShapeOutline {
        switch kind {
        case .rectangle: return RectangleOutline()
        case .square: return SquareOutline()
        case .circle: return CircleOutline()
        case .ellipse: return EllipseOutline()
        case .triangle: return TriangleOutline()
        case .diamond: return DiamondOutline()
        case .star: return StarOutline()
        }
    }
}
