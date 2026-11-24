import CamTwistCore
import CoreImage
import Foundation

/// A bulge in the picture that can be placed anywhere, with a size and a
/// strength.
public final class BumpEffect: ImageEffect {
    public static let name = "Bump"
    public static let xKey = EffectParameterKey.xPosition
    public static let yKey = EffectParameterKey.yPosition
    public static let sizeKey = EffectParameterKey.size
    public static let amountKey = "Amount"

    private static let filterName = CIFilterName.bumpDistortion
    private static let defaultSize = 0.35
    private static let defaultAmount = 0.5

    private let canvas: CGSize
    private var x = 0.0
    private var y = 0.0
    private var size = BumpEffect.defaultSize
    private var amount = BumpEffect.defaultAmount

    public init(canvas: CGSize) {
        self.canvas = canvas
    }

    /// Positions use the same units as the other overlays, across the
    /// picture from -1 to 1, so a bump drags about just as they do.
    public static let parameters = [
        EffectParameter(key: xKey, displayName: "X Position", kind: .number, defaultValue: .number(0), range: OverlayRange.position),
        EffectParameter(key: yKey, displayName: "Y Position", kind: .number, defaultValue: .number(0), range: OverlayRange.position),
        EffectParameter(
            key: sizeKey, displayName: "Size", kind: .number, defaultValue: .number(defaultSize), range: 0.05...1
        ),
        EffectParameter(
            key: amountKey, displayName: "Amount", kind: .number, defaultValue: .number(defaultAmount), range: -1...1
        ),
    ]

    public func setValues(_ values: [String: EffectValue]) {
        func number(_ key: String, default fallback: Double) -> Double {
            if case .number(let value) = values[key] { return value }
            return fallback
        }
        x = number(Self.xKey, default: 0)
        y = number(Self.yKey, default: 0)
        size = number(Self.sizeKey, default: Self.defaultSize)
        amount = number(Self.amountKey, default: Self.defaultAmount)
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        // Both axes are measured in half picture widths from the middle.
        let halfWidth = canvas.width / 2
        let center = CIVector(x: halfWidth + x * halfWidth, y: canvas.height / 2 + y * halfWidth)
        return image.clampedToExtent().applyingFilter(Self.filterName, parameters: [
            kCIInputCenterKey: center,
            kCIInputRadiusKey: size * canvas.width / 2,
            kCIInputScaleKey: amount,
        ]).cropped(to: CGRect(origin: .zero, size: canvas))
    }
}

public extension NativeEffect {
    /// A bulge that can be placed anywhere in the picture.
    static var bump: NativeEffect {
        NativeEffect(name: BumpEffect.name, kind: .filter, parameters: BumpEffect.parameters) {
            BumpEffect(canvas: $0)
        }
    }
}
