import CamTwistCore
import CoreGraphics
import CoreImage
import Foundation

/// A glowing ring to float over somebody's head, drawn as a shape at the
/// canvas's own resolution, so it is smooth at any size.
public final class HaloEffect: ImageEffect {
    public static let name = "Halo"
    public static let xKey = EffectParameterKey.xPosition
    public static let yKey = EffectParameterKey.yPosition
    public static let sizeKey = EffectParameterKey.size
    public static let rotationKey = EffectParameterKey.rotation
    public static let glowKey = "Glow"
    public static let colorKey = "Color"

    private enum Shape {
        /// The ring's height as a share of its width: seen from just above.
        static let aspect: CGFloat = 0.3
        /// The ring's thickness, and how far its glow reaches at full
        /// strength, as shares of its width.
        static let thickness: CGFloat = 0.05
        static let glow: CGFloat = 0.25
        /// The glow is laid down this many times to make it bright.
        static let glowPasses = 2
    }

    private static let defaultY = 0.3
    private static let defaultSize = 0.3
    private static let sizeRange: ClosedRange<Double> = 0.05...1.5
    private static let rotationRange: ClosedRange<Double> = -180...180
    private static let defaultGlow = 0.35
    private static let glowRange: ClosedRange<Double> = 0...1
    private static let defaultColor = CGColor(srgbRed: 1, green: 0.95, blue: 0.7, alpha: 1)
    private static let halfTurnDegrees = 180.0

    public static let parameters = [
        EffectParameter(key: xKey, displayName: "X Position", kind: .number, defaultValue: .number(0), range: OverlayRange.position),
        EffectParameter(
            key: yKey, displayName: "Y Position", kind: .number, defaultValue: .number(defaultY), range: OverlayRange.position
        ),
        EffectParameter(
            key: sizeKey, displayName: "Size", kind: .number, defaultValue: .number(defaultSize), range: sizeRange
        ),
        EffectParameter(
            key: rotationKey, displayName: "Rotation", kind: .number, defaultValue: .number(0), range: rotationRange
        ),
        EffectParameter(key: glowKey, displayName: "Glow", kind: .number, defaultValue: .number(defaultGlow), range: glowRange),
        EffectParameter(
            key: colorKey, displayName: "Color", kind: .color, defaultValue: .color(red: 1, green: 0.95, blue: 0.7, alpha: 1)
        ),
    ]

    private let canvas: CGSize
    private var values: [String: EffectValue] = [:]
    private var drawn: (values: [String: EffectValue], image: CIImage)?

    public init(canvas: CGSize) {
        self.canvas = canvas
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        // The ring is only redrawn when one of its settings changes.
        if drawn?.values != values {
            drawn = ring().map { (values, $0) }
        }
        return drawn.map { $0.image.composited(over: image) } ?? image
    }

    private func ring() -> CIImage? {
        let centre = OverlayPlacement.point(
            x: values.number(Self.xKey, default: 0), y: values.number(Self.yKey, default: Self.defaultY), canvas: canvas
        )
        let width = CGFloat(values.number(Self.sizeKey, default: Self.defaultSize)) * canvas.width
        // Rotation is clockwise; Core Graphics turns anticlockwise.
        let angle = -CGFloat(values.number(Self.rotationKey, default: 0) * .pi / Self.halfTurnDegrees)
        let color = values.color(Self.colorKey, default: Self.defaultColor)
        let glow = CGFloat(values.number(Self.glowKey, default: Self.defaultGlow))
        return CanvasDrawing.image(size: canvas) { context in
            context.translateBy(x: centre.x, y: centre.y)
            context.rotate(by: angle)
            context.setStrokeColor(color)
            context.setLineWidth(width * Shape.thickness)
            if glow > 0 {
                context.setShadow(offset: .zero, blur: width * Shape.glow * glow, color: color)
            }
            let outline = CGRect(
                x: -width / 2, y: -width * Shape.aspect / 2, width: width, height: width * Shape.aspect
            )
            for _ in 0..<Shape.glowPasses {
                context.strokeEllipse(in: outline)
            }
        }
    }
}

public extension NativeEffect {
    /// A smooth glowing halo.
    static var halo: NativeEffect {
        NativeEffect(name: HaloEffect.name, kind: .overlay, parameters: HaloEffect.parameters) {
            HaloEffect(canvas: $0)
        }
    }
}
