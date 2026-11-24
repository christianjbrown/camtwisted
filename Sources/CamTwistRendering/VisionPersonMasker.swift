import CoreImage
import Foundation
import Vision

/// Finds people with the system's own person finder.
final class VisionPersonMasker: PersonMasking {
    private let request: VNGeneratePersonSegmentationRequest

    init() {
        request = VNGeneratePersonSegmentationRequest()
        // Good edges at a speed that keeps up with live video.
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func mask(for image: CIImage) -> CIImage? {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let buffer = request.results?.first?.pixelBuffer else {
            return nil
        }
        // The mask comes back small; it is stretched to the picture's size.
        let mask = CIImage(cvPixelBuffer: buffer)
        guard mask.extent.width > 0, mask.extent.height > 0 else { return nil }
        return mask.transformed(by: CGAffineTransform(
            scaleX: image.extent.width / mask.extent.width, y: image.extent.height / mask.extent.height
        ).concatenating(CGAffineTransform(translationX: image.extent.minX, y: image.extent.minY)))
    }
}
