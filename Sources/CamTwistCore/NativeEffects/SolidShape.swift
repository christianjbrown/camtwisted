import Foundation

/// A solid the picture can be wrapped round.
public enum SolidShape: String, CaseIterable, Sendable {
    case cube = "Cube"
    /// A cube stretched to the picture's own shape, so nothing is cut off.
    case box = "Box"
    case sphere = "Sphere"
    case cylinder = "Cylinder"
    case cone = "Cone"
    case pyramid = "Pyramid"

    /// The shape a name means, whatever its case, or a cube for anything else.
    public init(named name: String) {
        self = Self.allCases.first { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame } ?? .cube
    }
}

/// How far a spinning solid has turned.
public enum SolidSpin {
    private static let fullTurn = 360.0

    /// Degrees turned at a moment: a starting angle plus so many full
    /// turns a second. At no turns a second it stays at its starting angle.
    public static func angle(at time: Double, turnsPerSecond: Double, startingAt start: Double) -> Double {
        (start + fullTurn * time * turnsPerSecond).truncatingRemainder(dividingBy: fullTurn)
    }
}
