import CamTwistCore
import CamTwistRendering
import CoreGraphics
import Foundation

/// Working on the picture: dragging the step in focus about, drawing on a
/// telestrator, and taking the step in focus away.
@MainActor
public final class PictureModel {
    /// The model owns this, so it is not held on to from here.
    private unowned let state: PictureState
    private let dragging: PictureDragHandling
    private let pictureSizes: SourcePictureSizing
    private let overlayMeasurer: OverlayMeasuring

    init(
        state: PictureState, dragging: PictureDragHandling, pictureSizes: SourcePictureSizing,
        overlayMeasurer: OverlayMeasuring
    ) {
        self.state = state
        self.dragging = dragging
        self.pictureSizes = pictureSizes
        self.overlayMeasurer = overlayMeasurer
    }

    public var dragTarget: DragTarget? { dragging.target(in: state.scene, selected: state.selectedStepID) }

    /// A line telling the user what dragging on the picture will do.
    public var dragHint: String? {
        dragging.hint(in: state.scene, selected: state.selectedStepID)
    }

    /// The box to draw round the selected step while it is resized or turned.
    public var selectionOutline: SelectionOutline? {
        dragging.outline(
            in: state.scene, selected: state.selectedStepID, pictureSize: pictureSizes.pictureSize(ofSource:),
            overlayBounds: overlayMeasurer.bounds(ofEffectNamed:values:)
        )
    }

    /// The box round the selected step as it sits on the picture as shown,
    /// when it has one.
    /// - Parameter size: the size of the picture on screen, in points.
    public func selectionBox(in size: CGSize) -> SelectionBoxLayout? {
        selectionOutline.map { SelectionBoxLayout(outline: $0, canvas: size) }
    }

    /// The pen of the telestrator a drag would draw with, if it has hold of one.
    public var pen: TelestratorSettings? { PictureGestures.pen(target: dragTarget, in: state.scene) }

    /// Lets go of the step in focus.
    public func deselect() {
        state.selectedStepID = nil
    }

    /// Takes the selected step out of the scene being changed, unless that
    /// scene is locked.
    public func removeSelectedStep() {
        guard let id = state.selectedStepID, !state.isEditedSceneLocked else { return }
        state.editedScene.remove(id: id)
        state.selectedStepID = nil
    }

    /// Carries out a drag between two points on the picture, in fractions
    /// of it with up as positive: a move, or a resize or turn of a placed source.
    public func drag(from start: CGPoint, to end: CGPoint, mode: DragMode) {
        dragging.drag(from: start, to: end, mode: mode, in: &state.scene, selected: state.selectedStepID)
    }

    /// Moves the selected step by a drag, given in fractions of the picture
    /// with up as positive.
    public func drag(by delta: CGPoint) {
        dragging.drag(by: delta, in: &state.scene, selected: state.selectedStepID)
    }

    /// Adds a stroke to a telestrator step, in unit coordinates.
    public func addStroke(_ points: [CGPoint], to id: UUID) {
        dragging.addStroke(points, to: id, in: &state.scene)
    }

    /// The telestrator step that drawing on the picture goes to.
    public var activeTelestrator: UUID? { dragging.activeTelestrator(in: state.scene) }
}

extension PictureModel {
    /// Escape lets go of the selected step and Delete removes it. False
    /// when the key is somebody else's.
    func keyPressed(_ keyCode: UInt16, isTyping: Bool, isSheetUp: Bool) -> Bool {
        let action = PictureKey.action(
            keyCode: keyCode, hasSelection: state.selectedStepID != nil, isTyping: isTyping, isSheetUp: isSheetUp
        )
        switch action {
        case .deselect: deselect()
        case .remove: removeSelectedStep()
        case nil: return false
        }
        return true
    }
}
