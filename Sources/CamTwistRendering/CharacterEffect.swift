import CamTwistCore
import CoreGraphics
import CoreImage
import Foundation

/// Finds the face in a picture.
protocol FaceTracking: AnyObject {
    /// The parts of the nearest face, or nil when there is none to be found.
    func face(in image: CIImage) -> FaceLandmarks?
}

/// Follows the nearest face from frame to frame.
protocol FaceFollowing: AnyObject {
    /// Whether there is a face to draw on: one seen lately, or one a
    /// preview has posed.
    var isInSight: Bool { get }
    /// What the face is doing in this picture. With nobody in sight, the
    /// last face seen is held.
    func expression(in image: CIImage) -> FaceExpression
    /// Stands the face somewhere by hand until a real one is seen.
    func rest(at expression: FaceExpression)
}

/// Follows a face by finding it, reading what it is doing and steadying
/// the answer. Shared by everything that draws on or in place of a face.
final class FaceFollower: FaceFollowing {
    private let tracker: FaceTracking
    private let smoother: ExpressionSmoothing
    private let reader: FaceReading
    private let patience: Int
    private var framesUnseen = 0
    private var isPosed = false

    /// - Parameter patience: how many frames a face may go unseen, as it
    ///   does for a moment in a quick turn, before it counts as gone.
    init(tracker: FaceTracking, smoother: ExpressionSmoothing, reader: FaceReading, patience: Int) {
        self.tracker = tracker
        self.smoother = smoother
        self.reader = reader
        self.patience = patience
    }

    var isInSight: Bool { isPosed || framesUnseen <= patience }

    func expression(in image: CIImage) -> FaceExpression {
        let seen = tracker.face(in: image).flatMap(reader.expression(of:))
        if seen == nil {
            framesUnseen += 1
        } else {
            framesUnseen = 0
            isPosed = false
        }
        return smoother.settle(on: seen)
    }

    func rest(at expression: FaceExpression) {
        smoother.rest(at: expression)
        isPosed = true
    }
}

/// An effect that follows a face and can be shown one by hand, so its
/// preview has a face to work on.
protocol FacePosable: AnyObject {
    func rest(at expression: FaceExpression)
}

/// How big something fitted to a face is drawn, against the face's own
/// size. One control, shared by every effect that has it.
enum FittedSize {
    static let control = NumberControl(key: EffectParameterKey.size, displayName: "Size", start: 1, range: 0.5...2)
}

/// A character that can act out an expression. A new character is a new
/// type that draws itself: the finding and steadying of the face is shared.
protocol CharacterDrawing {
    /// The character where the expression says the face is, clear around
    /// it, the size of the picture. Nil when it cannot be drawn.
    func picture(of expression: FaceExpression) -> CIImage?
}

/// Puts a character over the person in the picture, copying their expression.
public final class CharacterEffect: ImageEffect, FacePosable {
    public static let sizeKey = FittedSize.control.key
    public static let plainBackdropKey = "Plain_Backdrop"
    public static let backdropColorKey = "Backdrop_Color"

    private static let plainBackdrop = SwitchControl(key: plainBackdropKey, displayName: "Plain backdrop")
    /// A pale sky blue.
    private static let backdropColor = ColorControl(
        key: backdropColorKey, displayName: "Backdrop color", red: 0.45, green: 0.75, blue: 0.95
    )

    public static let parameters = [FittedSize.control.parameter, plainBackdrop.parameter, backdropColor.parameter]

    private let canvas: CGSize
    private let follower: FaceFollowing
    private let character: CharacterDrawing
    private var values: [String: EffectValue] = [:]

    init(canvas: CGSize, follower: FaceFollowing, character: CharacterDrawing) {
        self.canvas = canvas
        self.follower = follower
        self.character = character
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        var expression = follower.expression(in: image)
        expression.height *= CGFloat(FittedSize.control.value(in: values))
        let behind = backdrop(for: image)
        // A character that cannot be drawn still leaves the backdrop.
        return character.picture(of: expression).map { $0.composited(over: behind) } ?? behind
    }

    func rest(at expression: FaceExpression) {
        follower.rest(at: expression)
    }

    private func backdrop(for image: CIImage) -> CIImage {
        guard Self.plainBackdrop.isOn(in: values) else { return image }
        return CIImage(color: CIColor(cgColor: Self.backdropColor.value(in: values)))
            .cropped(to: CGRect(origin: .zero, size: canvas))
    }
}
