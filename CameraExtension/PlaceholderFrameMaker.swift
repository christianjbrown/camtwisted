import CoreMedia
import CoreVideo
import Foundation

/// Draws the placeholder into a pooled buffer and wraps it as a frame.
final class PlaceholderFrameMaker: PlaceholderFrameMaking {
    private let pool: PixelBufferSource
    private let placeholder: PlaceholderFrameProvider
    private let formatDescription: CMFormatDescription
    private let frameDuration: CMTime
    private let hostTime: () -> CMTime
    private let log: CameraLogger

    init(
        pool: PixelBufferSource, placeholder: PlaceholderFrameProvider, formatDescription: CMFormatDescription,
        frameDuration: CMTime, hostTime: @escaping () -> CMTime, log: CameraLogger
    ) {
        self.pool = pool
        self.placeholder = placeholder
        self.formatDescription = formatDescription
        self.frameDuration = frameDuration
        self.hostTime = hostTime
        self.log = log
    }

    func makeFrame() -> TimedFrame? {
        let pixelBuffer: CVPixelBuffer
        switch pool.makeBuffer() {
        case .success(let buffer): pixelBuffer = buffer
        case .failure(let failure):
            log.error("No pixel buffer for the placeholder frame: \(failure.status)")
            return nil
        }
        placeholder.draw(into: pixelBuffer)

        let now = hostTime()
        var timing = CMSampleTimingInfo(duration: frameDuration, presentationTimeStamp: now, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else { return nil }
        return TimedFrame(sampleBuffer: sampleBuffer, time: now)
    }
}
