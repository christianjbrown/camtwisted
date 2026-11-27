import CamTwistCore
import CoreImage
import Foundation

/// Zooms in on the nearest person and pans to keep them in frame as they
/// move about, the way a camera operator would. The follower it is given
/// steadies the face, so the picture glides rather than jumps. With nobody
/// seen yet it holds on the middle; when they leave it holds where they were.
public final class FollowMeEffect: ImageEffect, FacePosable {
    public static let name = "Follow Me"
    public static let zoomKey = "Zoom"

    private enum Framing {
        /// The frame's middle sits this share of its height below the face,
        /// leaving room for the shoulders rather than cutting at the chin.
        static let headroom: CGFloat = 0.1
        /// Zoomed no further out than the whole picture.
        static let whole: CGFloat = 1
        /// The share of the frame from its edge to its middle.
        static let half: CGFloat = 0.5
    }

    private static let zoom = NumberControl(key: zoomKey, displayName: "Zoom", start: 1.8, range: 1...3)

    public static let parameters = [zoom.parameter]

    private let canvas: CGSize
    private let follower: FaceFollowing
    private var values: [String: EffectValue] = [:]

    init(canvas: CGSize, follower: FaceFollowing) {
        self.canvas = canvas
        self.follower = follower
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        let face = follower.expression(in: image)
        let scale = max(CGFloat(Self.zoom.value(in: values)), Framing.whole)
        let frame = CGSize(width: canvas.width / scale, height: canvas.height / scale)
        // Centred on the face, then kept inside the picture so no edge shows.
        let origin = CGPoint(
            x: min(max(face.centre.x - frame.width * Framing.half, 0), canvas.width - frame.width),
            y: min(max(face.centre.y - frame.height * (Framing.half + Framing.headroom), 0), canvas.height - frame.height)
        )
        return image
            .cropped(to: CGRect(origin: origin, size: frame))
            .transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale)))
            .cropped(to: CGRect(origin: .zero, size: canvas))
    }

    func rest(at expression: FaceExpression) {
        follower.rest(at: expression)
    }
}
