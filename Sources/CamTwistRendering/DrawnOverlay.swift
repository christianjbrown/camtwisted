import CamTwistCore
import CoreGraphics
import CoreImage
import Foundation

/// An overlay painted with Core Graphics from its control values and the
/// time. Still ones are painted once and kept until a control changes.
final class DrawnOverlay: ImageEffect {
    typealias Painter = (
        _ values: [String: EffectValue], _ time: TimeInterval, _ canvas: CGSize, _ context: CGContext
    ) -> Void

    private let canvas: CGSize
    private let animated: Bool
    private let painter: Painter
    private var values: [String: EffectValue] = [:]
    private var kept: (values: [String: EffectValue], image: CIImage?)?

    /// - Parameter animated: whether the picture depends on the time, so it
    ///   is painted again every frame.
    init(canvas: CGSize, animated: Bool, painter: @escaping Painter) {
        self.canvas = canvas
        self.animated = animated
        self.painter = painter
    }

    func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        let painted: CIImage?
        if !animated, let kept, kept.values == values {
            painted = kept.image
        } else {
            let values = values
            let canvas = canvas
            painted = CanvasDrawing.image(size: canvas) { painter(values, time, canvas, $0) }
            kept = (values, painted)
        }
        return painted.map { $0.composited(over: image) } ?? image
    }
}
