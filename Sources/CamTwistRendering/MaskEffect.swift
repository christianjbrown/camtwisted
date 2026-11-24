import CamTwistCore
import CoreGraphics
import CoreImage
import Foundation

/// Keeps the picture inside a shape and clears the rest, or the other way
/// round. On a source's own branch what is cleared shows whatever is
/// beneath that source.
public final class MaskEffect: ImageEffect {
    public static let name = "Mask"
    public static let shapeKey = "Shape"
    public static let xKey = EffectParameterKey.xPosition
    public static let yKey = EffectParameterKey.yPosition
    public static let sizeKey = EffectParameterKey.size
    public static let rotationKey = EffectParameterKey.rotation
    public static let softnessKey = "Softness"
    public static let reverseKey = "Reverse"

    private static let defaultShape = ShapeKind.circle
    private static let defaultSize = 0.5
    private static let defaultSoftness = 0.0
    private static let sizeRange: ClosedRange<Double> = 0.05...2
    private static let rotationRange: ClosedRange<Double> = -180...180
    private static let softnessRange: ClosedRange<Double> = 0...0.3
    private static let halfTurnDegrees = 180.0
    private static let blendFilter = CIFilterName.blendWithMask
    private static let invertFilter = CIFilterName.colorInvert

    /// The shapes on offer, named as they are shown.
    private static let shapeNames = ShapeKind.allCases.map { $0.rawValue.capitalized }

    public static let parameters = [
        EffectParameter(
            key: shapeKey, displayName: "Shape", kind: .string, defaultValue: .string(defaultShape.rawValue.capitalized),
            choices: shapeNames
        ),
        EffectParameter(key: xKey, displayName: "X Position", kind: .number, defaultValue: .number(0), range: OverlayRange.position),
        EffectParameter(key: yKey, displayName: "Y Position", kind: .number, defaultValue: .number(0), range: OverlayRange.position),
        EffectParameter(key: sizeKey, displayName: "Size", kind: .number, defaultValue: .number(defaultSize), range: sizeRange),
        EffectParameter(
            key: rotationKey, displayName: "Rotation", kind: .number, defaultValue: .number(0), range: rotationRange
        ),
        EffectParameter(
            key: softnessKey, displayName: "Softness", kind: .number, defaultValue: .number(defaultSoftness),
            range: softnessRange
        ),
        EffectParameter(
            key: reverseKey, displayName: "Reverse: hide the inside", kind: .boolean, defaultValue: .boolean(false)
        ),
    ]

    private let canvas: CGSize
    private var values: [String: EffectValue] = [:]
    /// The mask for the values it was drawn from: white where the picture is kept.
    private var drawn: (values: [String: EffectValue], mask: CIImage)?

    public init(canvas: CGSize) {
        self.canvas = canvas
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        // The mask is only redrawn when one of its settings changes.
        if drawn?.values != values {
            drawn = mask().map { (values, $0) }
        }
        guard let mask = drawn?.mask else { return image }
        return image.applyingFilter(Self.blendFilter, parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
        ]).cropped(to: CGRect(origin: .zero, size: canvas))
    }

    private func mask() -> CIImage? {
        let name = values.string(Self.shapeKey, default: Self.defaultShape.rawValue)
        let kind = ShapeKind(rawValue: name.lowercased()) ?? Self.defaultShape
        let centre = OverlayPlacement.point(
            x: values.number(Self.xKey, default: 0), y: values.number(Self.yKey, default: 0), canvas: canvas
        )
        let width = CGFloat(values.number(Self.sizeKey, default: Self.defaultSize)) * canvas.width
        let height = width / CGFloat(ShapeGeometry.aspect(of: kind, canvasAspect: canvas.width / canvas.height))
        // Rotation is clockwise; Core Graphics turns anticlockwise.
        let angle = -CGFloat(values.number(Self.rotationKey, default: 0) * .pi / Self.halfTurnDegrees)
        let bounds = CGRect(origin: .zero, size: canvas)

        let shape = CanvasDrawing.image(size: canvas) { context in
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(bounds)
            context.translateBy(x: centre.x, y: centre.y)
            context.rotate(by: angle)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            let box = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            if ShapeGeometry.isRound(kind) {
                context.fillEllipse(in: box)
            } else {
                context.addLines(between: ShapeGeometry.corners(of: kind).map {
                    CGPoint(x: box.minX + $0.x * box.width, y: box.minY + $0.y * box.height)
                })
                context.closePath()
                context.fillPath()
            }
        }
        let softness = values.number(Self.softnessKey, default: Self.defaultSoftness) * canvas.width
        return shape.map { drawn in
            var mask = drawn
            if softness > 0 {
                mask = mask.clampedToExtent().applyingGaussianBlur(sigma: softness).cropped(to: bounds)
            }
            return values.boolean(Self.reverseKey) ? mask.applyingFilter(Self.invertFilter) : mask
        }
    }
}

public extension NativeEffect {
    /// A mask in a choice of shapes, either way round.
    static var mask: NativeEffect {
        NativeEffect(name: MaskEffect.name, kind: .filter, parameters: MaskEffect.parameters) {
            MaskEffect(canvas: $0)
        }
    }
}
