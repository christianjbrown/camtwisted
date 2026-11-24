import CamTwistCore
import CoreImage

/// Applies a source's own adjustments to its picture: zoom, flips, noise
/// reduction and colour correction, in that order.
enum SourceLook {
    private enum Filter {
        static let noiseReduction = CIFilterName.noiseReduction
        static let noiseLevel = CIInputKey.noiseLevel
        static let sharpness = CIInputKey.sharpness
        static let colorControls = CIFilterName.colorControls
        static let gamma = CIFilterName.gammaAdjust
        static let power = CIInputKey.power
        static let colorMatrix = CIFilterName.colorMatrix
        static let redVector = CIInputKey.redVector
        static let greenVector = CIInputKey.greenVector
        static let blueVector = CIInputKey.blueVector
    }

    static func apply(_ adjustments: SourceAdjustments?, to image: CIImage) -> CIImage {
        guard let adjustments, !adjustments.isNeutral else { return image }
        let region = adjustments.visibleRegion(of: image.extent)
        var picture = image.cropped(to: region)
        if adjustments.zoom < SourceAdjustments.unchanged {
            // Zoomed out, the picture sits in the middle of a larger, clear frame.
            picture = picture.composited(over: CIImage(color: .clear).cropped(to: region))
        }
        picture = flipped(picture, horizontally: adjustments.flipsHorizontally, vertically: adjustments.flipsVertically)
        if adjustments.reducesNoise {
            picture = FilterOutput.image(named: Filter.noiseReduction, parameters: [
                kCIInputImageKey: picture,
                Filter.noiseLevel: adjustments.noiseReduction,
                Filter.sharpness: adjustments.sharpness,
            ], fallback: picture)
        }
        return adjustments.changesColor ? colored(picture, by: adjustments) : picture
    }

    /// Mirrors a picture about its own middle, so it stays where it was.
    private static func flipped(_ image: CIImage, horizontally: Bool, vertically: Bool) -> CIImage {
        guard horizontally || vertically else { return image }
        let extent = image.extent
        let transform = CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
            .concatenating(CGAffineTransform(scaleX: horizontally ? -1 : 1, y: vertically ? -1 : 1))
            .concatenating(CGAffineTransform(translationX: extent.midX, y: extent.midY))
        return image.transformed(by: transform)
    }

    private static func colored(_ image: CIImage, by adjustments: SourceAdjustments) -> CIImage {
        let controlled = FilterOutput.image(named: Filter.colorControls, parameters: [
            kCIInputImageKey: image,
            kCIInputBrightnessKey: adjustments.brightness,
            kCIInputContrastKey: adjustments.contrast,
            kCIInputSaturationKey: adjustments.saturation,
        ], fallback: image)
        // A gamma above 1 lifts the mid tones, which is a power below 1.
        let lifted = FilterOutput.image(named: Filter.gamma, parameters: [
            kCIInputImageKey: controlled,
            Filter.power: SourceAdjustments.unchanged / max(adjustments.gamma, SourceAdjustments.gammaRange.lowerBound),
        ], fallback: controlled)
        return FilterOutput.image(named: Filter.colorMatrix, parameters: [
            kCIInputImageKey: lifted,
            Filter.redVector: CIVector(x: adjustments.red, y: 0, z: 0, w: 0),
            Filter.greenVector: CIVector(x: 0, y: adjustments.green, z: 0, w: 0),
            Filter.blueVector: CIVector(x: 0, y: 0, z: adjustments.blue, w: 0),
        ], fallback: lifted)
    }
}
