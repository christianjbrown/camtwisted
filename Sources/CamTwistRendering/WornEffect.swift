import CamTwistCore
import CoreGraphics
import CoreImage
import Foundation

/// Something a person can wear on their head or face: antennae, glasses, a
/// hat. A new one is a new type that says where it hangs and draws itself;
/// the following of the face and the fitting to it are shared.
protocol Wearable {
    /// The settings it has, besides its size.
    var parameters: [EffectParameter] { get }
    /// How far its drawing reaches from where it hangs, in its own units.
    var reach: CGFloat { get }
    /// The point on the face it hangs from, in the picture's points.
    func anchor(on face: FaceExpression) -> CGPoint
    /// The length it is measured in, in points: one unit of its drawing.
    func unit(on face: FaceExpression) -> CGFloat
    /// Draws it. The context starts where it hangs, upright along the
    /// head's own lean, with one unit as above.
    func draw(on face: FaceExpression, time: TimeInterval, values: [String: EffectValue], in context: CGContext)
}

/// Puts something on the head or face of the nearest person and keeps it
/// there as they move. With nobody in the picture nothing is drawn.
public final class WornEffect: ImageEffect, FacePosable {
    public static let sizeKey = FittedSize.control.key

    private let canvas: CGSize
    private let follower: FaceFollowing
    private let item: Wearable
    private var values: [String: EffectValue] = [:]

    init(canvas: CGSize, follower: FaceFollowing, item: Wearable) {
        self.canvas = canvas
        self.follower = follower
        self.item = item
    }

    /// The settings an item is shown with: its size, then its own.
    static func parameters(for item: Wearable) -> [EffectParameter] {
        [FittedSize.control.parameter] + item.parameters
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        let face = follower.expression(in: image)
        // Nobody there, nobody to wear it.
        guard follower.isInSight else { return image }
        let unit = item.unit(on: face) * CGFloat(FittedSize.control.value(in: values))
        let anchor = item.anchor(on: face)
        // Only the part of the picture the item can reach is drawn.
        let reach = unit * item.reach
        let box = CGRect(x: anchor.x - reach, y: anchor.y - reach, width: reach * 2, height: reach * 2)
            .intersection(CGRect(origin: .zero, size: canvas)).integral
        let item = item
        let values = values
        let drawn = CanvasDrawing.image(size: box.size) { context in
            context.translateBy(x: anchor.x - box.minX, y: anchor.y - box.minY)
            context.rotate(by: face.roll)
            context.scaleBy(x: unit, y: unit)
            item.draw(on: face, time: time, values: values, in: context)
        }
        // A head wholly outside the picture has nothing to show.
        return drawn.map {
            $0.transformed(by: CGAffineTransform(translationX: box.minX, y: box.minY)).composited(over: image)
        } ?? image
    }

    func rest(at expression: FaceExpression) {
        follower.rest(at: expression)
    }
}
