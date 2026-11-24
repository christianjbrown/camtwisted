import CamTwistCore
import CoreImage
import Foundation

/// Makes the eyes of the nearest person bigger, by bulging the picture
/// around each one. With nobody in the picture nothing is changed.
public final class BigEyesEffect: ImageEffect, FacePosable {
    public static let name = "Big Eyes"
    public static let amountKey = "Amount"

    private enum Bulge {
        /// How far round each eye the picture is stretched, as a share of
        /// the distance between the eyes: just short of half, so the two
        /// bulges never run into each other.
        static let reach: CGFloat = 0.45
        /// How hard the picture is pushed outwards at the most.
        static let strongest = 0.8
        /// The eyes, left and right of the point between them.
        static let sides: [CGFloat] = [-1, 1]
    }

    private static let amount = NumberControl(key: amountKey, displayName: "Amount", start: 0.5, range: 0...1)

    public static let parameters = [amount.parameter]

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
        // Nobody there, no eyes to enlarge.
        guard follower.isInSight else { return image }
        let strength = Self.amount.value(in: values) * Bulge.strongest
        let half = face.eyeSpan / 2
        var picture = image
        for side in Bulge.sides {
            // Along the line between the eyes, which leans with the head.
            let eye = CIVector(
                x: face.eyeLine.x + side * half * cos(face.roll), y: face.eyeLine.y + side * half * sin(face.roll)
            )
            picture = picture.applyingFilter(CIFilterName.bumpDistortion, parameters: [
                kCIInputCenterKey: eye, kCIInputRadiusKey: face.eyeSpan * Bulge.reach, kCIInputScaleKey: strength,
            ])
        }
        return picture.cropped(to: CGRect(origin: .zero, size: canvas))
    }

    func rest(at expression: FaceExpression) {
        follower.rest(at: expression)
    }
}
