import CoreVideo

/// Hands out blank frames to draw into.
public protocol PixelBufferProviding {
    /// A frame, or nil when none can be had.
    func makeBuffer() -> CVPixelBuffer?
}

/// Reuses frame memory between frames, which is much cheaper than
/// allocating a fresh frame thirty times a second.
public final class PixelBufferPool: PixelBufferProviding {
    private var pool: CVPixelBufferPool?

    public init(width: Int, height: Int) {
        let attributes: NSDictionary = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes, &pool)
    }

    public func makeBuffer() -> CVPixelBuffer? {
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }
}
