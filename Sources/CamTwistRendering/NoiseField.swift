import CoreImage
import Foundation

/// Grey noise as large as the canvas, for grain, frost and wobble.
enum NoiseField {
    /// - Parameters:
    ///   - cell: how many points wide each speck of noise is.
    ///   - offset: another offset gives other noise, so noise can change
    ///     from frame to frame.
    static func image(canvas: CGSize, cell: CGFloat, offset: CGPoint = .zero) -> CIImage {
        let random = FilterOutput.image(named: CIFilterName.randomGenerator, parameters: [:], fallback: CIImage.empty())
        // Each colour channel is random; one of them is copied to all three
        // so the noise is grey, and the picture is made solid.
        return random
            .transformed(by: CGAffineTransform(translationX: -offset.x, y: -offset.y))
            .applyingFilter(CIFilterName.colorMatrix, parameters: [
                CIInputKey.redVector: CIVector(x: 1, y: 0, z: 0, w: 0),
                CIInputKey.greenVector: CIVector(x: 1, y: 0, z: 0, w: 0),
                CIInputKey.blueVector: CIVector(x: 1, y: 0, z: 0, w: 0),
                CIInputKey.alphaVector: CIVector(x: 0, y: 0, z: 0, w: 0),
                CIInputKey.biasVector: CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .transformed(by: CGAffineTransform(scaleX: cell, y: cell))
            .cropped(to: CGRect(origin: .zero, size: canvas))
    }
}
