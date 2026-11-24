import CoreMedia
import CoreMediaIO
import Foundation

/// A frame and the host time it is stamped with.
struct TimedFrame {
    let sampleBuffer: CMSampleBuffer
    let time: CMTime
}

/// Puts frames into the stream other apps read.
protocol CameraFrameSender {
    func send(_ frame: TimedFrame)
}

/// Takes frames from the stream the host app writes.
protocol CameraSinkReading {
    /// Asks for the next frame. The answer has no frame when the sink is empty.
    func consumeFrame(from client: CMIOExtensionClient, completion: @escaping (CMSampleBuffer?, UInt64) -> Void)
    /// Tells the app the frame with this number has been used.
    func announceOutput(sequenceNumber: UInt64, at time: CMTime)
}

/// Makes the frames of the camera's placeholder.
protocol PlaceholderFrameMaking {
    func makeFrame() -> TimedFrame?
}
