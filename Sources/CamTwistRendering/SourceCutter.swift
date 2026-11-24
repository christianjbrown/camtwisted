import CamTwistCore
import CoreImage
import Foundation

/// Takes out of a source's picture what its cutout says to.
protocol SourceCutting: AnyObject {
    /// The picture of the source with this identity, cut out.
    func cut(_ image: CIImage, by cutout: SourceCutout, forSource id: UUID) -> CIImage
    /// Lets go of what is kept for every source but these.
    func keepOnly(_ ids: Set<UUID>)
}

/// Cuts with the system's person finder and a colour cube per source.
final class SourceCutter: SourceCutting {
    private enum Filter {
        static let cube = CIFilterName.colorCube
        static let cubeDimension = CIInputKey.cubeDimension
        static let cubeData = CIInputKey.cubeData
        static let blendWithMask = CIFilterName.blendWithMask
    }

    private let masker: PersonMasking
    /// Each source's colour cube, with the settings it was made from.
    private var cubes: [UUID: (settings: ChromaKeySettings, data: Data)] = [:]

    init(masker: PersonMasking) {
        self.masker = masker
    }

    func cut(_ image: CIImage, by cutout: SourceCutout, forSource id: UUID) -> CIImage {
        var picture = image
        // With nobody to be found the picture is left as it is.
        if cutout.removesBackground, let mask = masker.mask(for: picture) {
            picture = picture.applyingFilter(Filter.blendWithMask, parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
            ]).cropped(to: image.extent)
        }
        if let key = cutout.chromaKey {
            picture = picture.applyingFilter(Filter.cube, parameters: [
                Filter.cubeDimension: ChromaKey.cubeSize,
                Filter.cubeData: cube(for: key, source: id),
            ])
        }
        return picture
    }

    func keepOnly(_ ids: Set<UUID>) {
        cubes = cubes.filter { ids.contains($0.key) }
    }

    /// The cube is only worked out again when a setting changes.
    private func cube(for settings: ChromaKeySettings, source id: UUID) -> Data {
        if let kept = cubes[id], kept.settings == settings {
            return kept.data
        }
        let data = ChromaKey.cube(for: settings).withUnsafeBufferPointer { Data(buffer: $0) }
        cubes[id] = (settings, data)
        return data
    }
}
