import CamTwistCore
import CoreImage
import Foundation

/// An effect that is one recipe of Core Image filters, driven by its values.
final class RecipeEffect: ImageEffect {
    typealias Recipe = (_ image: CIImage, _ values: [String: EffectValue], _ canvas: CGSize, _ time: TimeInterval) -> CIImage

    private let canvas: CGSize
    private let recipe: Recipe
    private var values: [String: EffectValue] = [:]

    init(canvas: CGSize, recipe: @escaping Recipe) {
        self.canvas = canvas
        self.recipe = recipe
    }

    func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        recipe(image, values, canvas, time).cropped(to: CGRect(origin: .zero, size: canvas))
    }
}

/// The filters streaming software usually has.
enum StudioFilter {
    static let unit: ClosedRange<Double> = 0...1
    private static let amountName = "Amount"

    enum Blur {
        static let name = "Blur"
        static let amountKey = "Amount"
        static let amount = NumberControl(key: amountKey, displayName: amountName, start: 0.1, range: unit)
        /// The widest blur, as a share of the picture's width.
        static let widest = 0.04
    }

    enum Sharpen {
        static let name = "Sharpen"
        static let amountKey = "Amount"
        static let amount = NumberControl(key: amountKey, displayName: amountName, start: 0.4, range: unit)
        /// Core Image's sharpness at full strength.
        static let strongest = 4.0
    }

    enum Crop {
        static let name = "Crop"
        static let leftKey = "Left"
        static let rightKey = "Right"
        static let topKey = "Top"
        static let bottomKey = "Bottom"
        /// The most that can come off one side, leaving something to see.
        static let range: ClosedRange<Double> = 0...0.95
        static let none = 0.0
        static let left = NumberControl(key: leftKey, displayName: "Left", start: none, range: range)
        static let right = NumberControl(key: rightKey, displayName: "Right", start: none, range: range)
        static let top = NumberControl(key: topKey, displayName: "Top", start: none, range: range)
        static let bottom = NumberControl(key: bottomKey, displayName: "Bottom", start: none, range: range)
    }

    enum Scroll {
        static let name = "Scroll"
        static let horizontalKey = "Horizontal_Speed"
        static let verticalKey = "Vertical_Speed"
        /// Speeds are in pictures a second, either way.
        static let range: ClosedRange<Double> = -2...2
        static let horizontal = NumberControl(key: horizontalKey, displayName: "Speed across", start: 0.2, range: range)
        static let vertical = NumberControl(key: verticalKey, displayName: "Speed up", start: 0, range: range)
    }

    enum Pixelate {
        static let name = "Pixelate"
        static let sizeKey = "Block_Size"
        static let size = NumberControl(key: sizeKey, displayName: "Block size", start: 0.2, range: unit)
        /// The largest blocks, as a share of the picture's width.
        static let largest = 0.1
        /// Blocks this small or smaller leave the picture as it was.
        static let smallestBlock = 1.0
    }

    enum Vignette {
        static let name = "Vignette"
        static let amountKey = "Amount"
        static let amount = NumberControl(key: amountKey, displayName: amountName, start: 0.5, range: unit)
        static let strongest = 2.0
        /// The falloff radius Core Image is given, which suits any amount.
        static let radius = 2.0
    }

    enum LumaKey {
        static let name = "Luma Key"
        static let thresholdKey = "Threshold"
        static let smoothnessKey = "Smoothness"
        static let brightKey = "Key_Out_Bright"
        static let threshold = NumberControl(key: thresholdKey, displayName: "Threshold", start: 0.2, range: unit)
        static let smoothness = NumberControl(key: smoothnessKey, displayName: "Smoothness", start: 0.1, range: unit)
        static let bright = SwitchControl(key: brightKey, displayName: "Key out the bright parts")
        /// A fade narrower than this would divide by next to nothing.
        static let narrowestFade = 0.001
        /// How much each colour adds to brightness (Rec. 601).
        static let redWeight = 0.299
        static let greenWeight = 0.587
        static let blueWeight = 0.114
    }

    static func blur(_ image: CIImage, _ values: [String: EffectValue], _ canvas: CGSize, _ time: TimeInterval) -> CIImage {
        let amount = Blur.amount.value(in: values)
        guard amount > 0 else { return image }
        return image.clampedToExtent().applyingGaussianBlur(sigma: amount * Blur.widest * canvas.width)
    }

    static func sharpen(_ image: CIImage, _ values: [String: EffectValue], _ canvas: CGSize, _ time: TimeInterval) -> CIImage {
        image.applyingFilter(CIFilterName.sharpenLuminance, parameters: [
            kCIInputSharpnessKey: Sharpen.amount.value(in: values) * Sharpen.strongest,
        ])
    }

    static func crop(_ image: CIImage, _ values: [String: EffectValue], _ canvas: CGSize, _ time: TimeInterval) -> CIImage {
        func side(_ control: NumberControl) -> Double {
            min(max(control.value(in: values), Crop.range.lowerBound), Crop.range.upperBound)
        }
        let left = side(Crop.left) * canvas.width
        let bottom = side(Crop.bottom) * canvas.height
        return image.cropped(to: CGRect(
            x: left, y: bottom,
            width: max(canvas.width - left - side(Crop.right) * canvas.width, 0),
            height: max(canvas.height - bottom - side(Crop.top) * canvas.height, 0)
        ))
    }

    static func scroll(_ image: CIImage, _ values: [String: EffectValue], _ canvas: CGSize, _ time: TimeInterval) -> CIImage {
        func offset(_ control: NumberControl, _ length: CGFloat) -> CGFloat {
            // Wrapped to one picture, so the numbers stay small however long it runs.
            (CGFloat(control.value(in: values) * time) * length).truncatingRemainder(dividingBy: length)
        }
        return image.cropped(to: CGRect(origin: .zero, size: canvas))
            .applyingFilter(CIFilterName.affineTile, parameters: [kCIInputTransformKey: CGAffineTransform.identity])
            .transformed(by: CGAffineTransform(
                translationX: -offset(Scroll.horizontal, canvas.width),
                y: -offset(Scroll.vertical, canvas.height)
            ))
    }

    static func pixelate(_ image: CIImage, _ values: [String: EffectValue], _ canvas: CGSize, _ time: TimeInterval) -> CIImage {
        let size = Pixelate.size.value(in: values) * Pixelate.largest * canvas.width
        guard size > Pixelate.smallestBlock else { return image }
        return image.clampedToExtent().applyingFilter(CIFilterName.pixellate, parameters: [
            kCIInputScaleKey: size, kCIInputCenterKey: CIVector(x: 0, y: 0),
        ])
    }

    static func vignette(_ image: CIImage, _ values: [String: EffectValue], _ canvas: CGSize, _ time: TimeInterval) -> CIImage {
        image.applyingFilter(CIFilterName.vignette, parameters: [
            kCIInputIntensityKey: Vignette.amount.value(in: values) * Vignette.strongest,
            kCIInputRadiusKey: Vignette.radius,
        ])
    }

    static func lumaKey(_ image: CIImage, _ values: [String: EffectValue], _ canvas: CGSize, _ time: TimeInterval) -> CIImage {
        let threshold = LumaKey.threshold.value(in: values)
        let fade = max(LumaKey.smoothness.value(in: values), LumaKey.narrowestFade)
        // The mask is white where the picture is kept: brightness run
        // through a ramp that starts at the threshold, turned over when it
        // is the bright parts that go.
        let keysOutBright = LumaKey.bright.isOn(in: values)
        let direction: CGFloat = keysOutBright ? -1 : 1
        let slope = direction / fade
        let start = keysOutBright ? (1 - threshold) / fade : -threshold / fade
        let ramp = CIVector(x: LumaKey.redWeight * slope, y: LumaKey.greenWeight * slope, z: LumaKey.blueWeight * slope, w: 0)
        let mask = image.applyingFilter(CIFilterName.colorMatrix, parameters: [
            CIInputKey.redVector: ramp, CIInputKey.greenVector: ramp, CIInputKey.blueVector: ramp,
            CIInputKey.alphaVector: CIVector(x: 0, y: 0, z: 0, w: 1),
            CIInputKey.biasVector: CIVector(x: start, y: start, z: start, w: 0),
        ]).applyingFilter(CIFilterName.colorClamp)
        return image.applyingFilter(CIFilterName.blendWithMask, parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
        ])
    }
}

public extension NativeEffect {
    /// The filters streaming software usually has: a luma key, blur, sharpen,
    /// crop, scroll, pixelate, vignette and a mask.
    static var studioFilters: [NativeEffect] {
        func recipe(_ name: String, _ controls: [EffectParameter], _ recipe: @escaping RecipeEffect.Recipe) -> NativeEffect {
            NativeEffect(name: name, kind: .filter, parameters: controls) { RecipeEffect(canvas: $0, recipe: recipe) }
        }
        typealias Filter = StudioFilter
        return [
            recipe(Filter.LumaKey.name, [
                Filter.LumaKey.threshold.parameter, Filter.LumaKey.smoothness.parameter, Filter.LumaKey.bright.parameter,
            ], Filter.lumaKey),
            recipe(Filter.Blur.name, [Filter.Blur.amount.parameter], Filter.blur),
            recipe(Filter.Sharpen.name, [Filter.Sharpen.amount.parameter], Filter.sharpen),
            recipe(Filter.Crop.name, [
                Filter.Crop.left.parameter, Filter.Crop.right.parameter,
                Filter.Crop.top.parameter, Filter.Crop.bottom.parameter,
            ], Filter.crop),
            recipe(Filter.Scroll.name, [
                Filter.Scroll.horizontal.parameter, Filter.Scroll.vertical.parameter,
            ], Filter.scroll),
            recipe(Filter.Pixelate.name, [Filter.Pixelate.size.parameter], Filter.pixelate),
            recipe(Filter.Vignette.name, [Filter.Vignette.amount.parameter], Filter.vignette),
            .mask,
        ]
    }
}
