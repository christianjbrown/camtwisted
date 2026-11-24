import CamTwistCore
import CoreImage
import Foundation

/// Finds the people in a picture.
protocol PersonMasking: AnyObject {
    /// A mask the size of the picture, white where there is a person, or
    /// nil when none can be made.
    func mask(for image: CIImage) -> CIImage?
}

/// Blurs what is behind the people in the picture. Taking the background
/// away altogether is a setting on the source itself.
public final class BackgroundEffect: ImageEffect {
    public static let blurName = "Blur Background"
    public static let amountKey = "Amount"

    private static let defaultAmount = 0.5
    /// The widest blur, as a share of the picture's width.
    private static let widestBlur = 0.04
    private static let blendFilter = CIFilterName.blendWithMask

    public static let blurParameters = [
        EffectParameter(
            key: amountKey, displayName: "Amount", kind: .number, defaultValue: .number(defaultAmount), range: 0...1
        ),
    ]

    private let canvas: CGSize
    private let masker: PersonMasking
    private var values: [String: EffectValue] = [:]

    init(canvas: CGSize, masker: PersonMasking) {
        self.canvas = canvas
        self.masker = masker
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        // With nobody to be found the picture passes through as it is.
        guard let mask = masker.mask(for: image) else { return image }
        let bounds = CGRect(origin: .zero, size: canvas)
        let reach = values.number(Self.amountKey, default: Self.defaultAmount) * Self.widestBlur * canvas.width
        let behind = image.clampedToExtent().applyingGaussianBlur(sigma: reach).cropped(to: bounds)
        return image.applyingFilter(Self.blendFilter, parameters: [
            kCIInputBackgroundImageKey: behind, kCIInputMaskImageKey: mask,
        ]).cropped(to: bounds)
    }
}

extension NativeEffect {
    /// The effect that blurs what is behind a person.
    static func backgrounds(masker: @escaping () -> PersonMasking) -> [NativeEffect] {
        [
            NativeEffect(name: BackgroundEffect.blurName, kind: .filter, parameters: BackgroundEffect.blurParameters) {
                BackgroundEffect(canvas: $0, masker: masker())
            },
        ]
    }
}
