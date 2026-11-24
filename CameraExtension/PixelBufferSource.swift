import CoreVideo
import Foundation

/// A pixel buffer could not be had from the pool.
struct PixelBufferFailure: Error {
    let status: CVReturn
}

/// Hands out blank pixel buffers of the camera's size.
protocol PixelBufferSource {
    func makeBuffer() -> Result<CVPixelBuffer, PixelBufferFailure>
}

/// Reuses buffers from a Core Video pool.
final class PixelBufferPoolSource: PixelBufferSource {
    private var pool: CVPixelBufferPool!
    private let auxAttributes: NSDictionary

    /// `threshold` is how many buffers the pool hands out before it starts dropping frames.
    init(width: Int, height: Int, threshold: Int) {
        auxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: threshold]
        let pixelBufferAttributes: NSDictionary = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary,
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes, &pool)
    }

    func makeBuffer() -> Result<CVPixelBuffer, PixelBufferFailure> {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault, pool, auxAttributes, &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return .failure(PixelBufferFailure(status: status)) }
        return .success(pixelBuffer)
    }
}
