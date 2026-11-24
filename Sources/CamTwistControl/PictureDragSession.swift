import CamTwistCore
import CoreGraphics
import Foundation
import Observation

/// What a drag on the picture works on: what has hold of the drag, the box
/// round the step in focus, and the changes a drag makes.
@MainActor
protocol PictureDragActing: AnyObject {
    var dragTarget: DragTarget? { get }
    func selectionBox(in size: CGSize) -> SelectionBoxLayout?
    func drag(from start: CGPoint, to end: CGPoint, mode: DragMode)
    func addStroke(_ points: [CGPoint], to id: UUID)
    func deselect()
}

extension PictureModel: PictureDragActing {}

/// One drag on the picture, from the press to the mouse coming up. The
/// press decides the whole drag: on a telestrator it draws, and otherwise
/// the knob turns, a corner resizes, the middle moves and outside lets go.
@MainActor
@Observable
public final class PictureDragSession {
    /// The stroke being drawn, in the view's own points, shown until the
    /// mouse comes up and the stroke joins the picture.
    public private(set) var stroke: [CGPoint] = []
    @ObservationIgnored private var lastLocation: CGPoint?
    /// What the drag under way has hold of, decided where it started. Nil
    /// while no drag is under way, and for one that began outside the box.
    @ObservationIgnored private var grip: DragMode?

    private let picture: PictureDragActing

    init(picture: PictureDragActing) {
        self.picture = picture
    }

    /// The pointer has gone down or moved.
    /// - Parameters:
    ///   - location: where the pointer is, in the view's points.
    ///   - start: where it went down.
    ///   - size: the size of the picture as shown.
    public func changed(to location: CGPoint, start: CGPoint, in size: CGSize) {
        if case .telestrator = picture.dragTarget {
            stroke.append(location)
        } else if let last = lastLocation {
            guard let grip else { return }
            picture.drag(
                from: PictureGestures.unitPoint(last, in: size), to: PictureGestures.unitPoint(location, in: size),
                mode: grip
            )
        } else {
            grip = PictureGestures.mode(at: start, box: picture.selectionBox(in: size))
            if grip == nil { picture.deselect() }
        }
        lastLocation = location
    }

    /// The mouse has come up: a stroke that was drawn joins the picture.
    public func ended(in size: CGSize) {
        if case .telestrator(let id) = picture.dragTarget, !stroke.isEmpty {
            picture.addStroke(stroke.map { PictureGestures.unitPoint($0, in: size) }, to: id)
        }
        stroke = []
        lastLocation = nil
        grip = nil
    }
}
