import CamTwistCore
import CoreGraphics
import Foundation

/// How gestures on the program picture are read.
public enum PictureGestures {
    /// A point in the view, whose origin is top left, as a fraction of the
    /// picture with its origin at the bottom left.
    public static func unitPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x / size.width, y: 1 - point.y / size.height)
    }

    /// A fraction of the picture with its origin at the bottom left, as a
    /// point in the view, whose origin is top left.
    public static func viewPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
    }

    /// What a drag that starts at a point does: the box's answer when the
    /// selection has a box, and a move when it has none. Nil is a press
    /// outside the box, which lets go of the selection.
    public static func mode(at point: CGPoint, box: SelectionBoxLayout?) -> DragMode? {
        guard let box else { return .move }
        return box.grip(at: point)
    }

    /// The pen of the telestrator a drag is drawing with, if the drag has hold of one.
    public static func pen(target: DragTarget?, in scene: SceneConfiguration) -> TelestratorSettings? {
        guard case .telestrator(let id) = target,
              case .source(.telestrator(let settings)) = scene.item(id: id)?.content
        else { return nil }
        return settings
    }
}

/// Where the box round a selection sits on the picture as shown, in points,
/// and which part of it a press takes hold of: the knob turns, a corner
/// resizes and the middle moves.
public struct SelectionBoxLayout: Equatable {
    /// The side of a corner handle and the width of the knob.
    public static let handleSize: CGFloat = 9
    /// How far the knob stands off the top edge.
    public static let stalkLength: CGFloat = 22
    /// How near a handle a press has to land to take hold of it.
    public static let grabRadius: CGFloat = 12
    private static let degreesInHalfTurn = 180.0
    /// The corners, as signs either side of the middle.
    private static let corners: [(x: CGFloat, y: CGFloat)] = [(-1, -1), (1, -1), (-1, 1), (1, 1)]

    public let size: CGSize
    public let center: CGPoint
    /// Degrees clockwise.
    public let rotation: Double
    public let canTurn: Bool
    public let canResize: Bool
    /// Where the knob is, measured down from the middle of the box along
    /// its own upright. It stands above the top edge, or just inside it
    /// when above would be off the picture.
    public let knobOffset: CGFloat

    /// - Parameter canvas: the size of the picture on screen, in points.
    public init(outline: SelectionOutline, canvas: CGSize) {
        size = CGSize(width: outline.size.width * canvas.width, height: outline.size.height * canvas.height)
        center = PictureGestures.viewPoint(outline.center, in: canvas)
        rotation = outline.rotation
        canTurn = outline.canTurn
        canResize = outline.canResize
        let outside = -(size.height / 2 + Self.stalkLength)
        let knob = Self.turned(CGPoint(x: 0, y: outside), by: outline.rotation)
        let place = CGPoint(x: center.x + knob.x, y: center.y + knob.y)
        let isOnPicture = CGRect(origin: .zero, size: canvas).contains(place)
        knobOffset = isOnPicture ? outside : -(size.height / 2 - Self.stalkLength)
    }

    /// What a press at a point in the view takes hold of, or nil outside the box.
    public func grip(at point: CGPoint) -> DragMode? {
        // The press as the box sees it: from its middle, along its own sides.
        let local = Self.turned(CGPoint(x: point.x - center.x, y: point.y - center.y), by: -rotation)
        func isNear(x: CGFloat, y: CGFloat) -> Bool {
            hypot(local.x - x, local.y - y) <= Self.grabRadius
        }
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        if canTurn, isNear(x: 0, y: knobOffset) { return .turn }
        if canResize, Self.corners.contains(where: { isNear(x: $0.x * halfWidth, y: $0.y * halfHeight) }) {
            return .resize
        }
        return abs(local.x) <= halfWidth && abs(local.y) <= halfHeight ? .move : nil
    }

    /// A point turned clockwise about the origin, in a view whose y runs down.
    private static func turned(_ point: CGPoint, by degrees: Double) -> CGPoint {
        let radians = degrees * .pi / degreesInHalfTurn
        return CGPoint(
            x: point.x * cos(radians) - point.y * sin(radians), y: point.x * sin(radians) + point.y * cos(radians)
        )
    }
}

/// What a key pressed over the window does to the selected step.
public enum PictureKey: Equatable {
    case deselect
    case remove

    private static let escapeKeyCode: UInt16 = 53
    private static let deleteKeyCode: UInt16 = 51
    private static let forwardDeleteKeyCode: UInt16 = 117

    /// The key's job, or nil when it is somebody else's: nothing is
    /// selected, the key is being typed into a field, or a sheet has the keys.
    public static func action(keyCode: UInt16, hasSelection: Bool, isTyping: Bool, isSheetUp: Bool) -> PictureKey? {
        guard hasSelection, !isTyping, !isSheetUp else { return nil }
        switch keyCode {
        case escapeKeyCode: return .deselect
        case deleteKeyCode, forwardDeleteKeyCode: return .remove
        default: return nil
        }
    }
}
