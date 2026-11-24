import CamTwistCore
import CoreImage

/// Changes a canvas-sized picture into another canvas-sized picture.
public protocol ImageEffect: AnyObject {
    func setValues(_ values: [String: EffectValue])
    func apply(to image: CIImage, time: TimeInterval) -> CIImage
}

/// One step of a chain, resolved to what it draws.
public enum CompositorLayer {
    /// A source's picture. With placement it sits in a corner; without, it
    /// covers the canvas in the way `fit` says. Nil when the source has
    /// nothing to show.
    case picture(CIImage?, placement: PictureInPictureSettings?, fit: SourceFit = .fill)
    case effect(ImageEffect)
}

/// Builds one frame by running a chain from top to bottom.
public struct Compositor {
    public let canvas: CGSize

    public init(canvas: CGSize) {
        self.canvas = canvas
    }

    private var bounds: CGRect { CGRect(origin: .zero, size: canvas) }

    /// The finished picture: the layers over black.
    public func compose(_ layers: [CompositorLayer], time: TimeInterval) -> CIImage {
        run(layers, over: .black, time: time)
    }

    /// A picture of some layers alone, clear wherever they draw nothing, so
    /// it can be laid over other things afterwards.
    public func composeClear(_ layers: [CompositorLayer], time: TimeInterval) -> CIImage {
        run(layers, over: .clear, time: time)
    }

    private func run(_ layers: [CompositorLayer], over background: CIColor, time: TimeInterval) -> CIImage {
        let ground = CIImage(color: background).cropped(to: bounds)
        var frame = ground
        for layer in layers {
            switch layer {
            case .picture(let image, let placement, let fit):
                guard let image else { continue }
                frame = placed(image, by: placement, fit: fit).composited(over: frame).cropped(to: bounds)
            case .effect(let effect):
                // Over the ground again, so an effect that leaves part of the
                // picture empty, as a crop does, still gives a whole frame.
                frame = effect.apply(to: frame, time: time).cropped(to: bounds).composited(over: ground)
            }
        }
        return frame
    }

    /// Puts a source's picture where it belongs: covering the canvas, or,
    /// with a placement, at its place, size and angle.
    private func placed(_ image: CIImage, by placement: PictureInPictureSettings?, fit: SourceFit) -> CIImage {
        guard let placement else {
            return place(image, in: AspectFitter.frame(for: image.extent.size, in: canvas, fit: fit))
        }
        let target = PictureInPictureLayout.frame(for: image.extent.size, in: canvas, settings: placement)
        guard placement.isTurnedInSpace else {
            return turn(place(image, in: target), by: placement.rotation, about: target)
        }
        // Turned out of its own plane, the picture is drawn with
        // perspective: each corner goes where the turn puts it.
        let corners = Perspective.corners(
            of: target, rotation: placement.rotation, tilt: placement.tilt, swing: placement.swing,
            canvasWidth: canvas.width
        )
        return FilterOutput.image(named: Self.perspectiveFilter, parameters: [
            kCIInputImageKey: image,
            CIInputKey.topLeft: CIVector(cgPoint: corners.topLeft),
            CIInputKey.topRight: CIVector(cgPoint: corners.topRight),
            CIInputKey.bottomRight: CIVector(cgPoint: corners.bottomRight),
            CIInputKey.bottomLeft: CIVector(cgPoint: corners.bottomLeft),
        ], fallback: image)
    }

    private static let perspectiveFilter = CIFilterName.perspectiveTransform

    /// Turns an image clockwise by a number of degrees about a frame's middle.
    private func turn(_ image: CIImage, by degrees: Double, about frame: CGRect) -> CIImage {
        guard degrees != 0 else { return image }
        // Core Image's angles run anticlockwise, so the turn is negated.
        let radians = -degrees * .pi / Self.halfTurnDegrees
        let transform = CGAffineTransform(translationX: -frame.midX, y: -frame.midY)
            .concatenating(CGAffineTransform(rotationAngle: radians))
            .concatenating(CGAffineTransform(translationX: frame.midX, y: frame.midY))
        return image.transformed(by: transform)
    }

    private static let halfTurnDegrees = 180.0

    /// Moves and scales an image so it exactly covers a rectangle.
    private func place(_ image: CIImage, in target: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return image }
        let transform = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: target.width / extent.width, y: target.height / extent.height))
            .concatenating(CGAffineTransform(translationX: target.minX, y: target.minY))
        return image.transformed(by: transform)
    }
}
