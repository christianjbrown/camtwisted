import CamTwistCore
import CoreMediaIO
import Foundation

/// Takes frames from the app's sink stream one at a time and hands them on.
final class SinkFrameConsumer {
    private let queue: DispatchQueue
    private let session: CameraSession
    private let reader: CameraSinkReading
    private let sender: CameraFrameSender
    /// Pause before asking the sink again after an empty answer.
    private let retryDelay: TimeInterval
    private let clock: () -> Date
    private let hostTime: () -> CMTime

    init(
        queue: DispatchQueue, session: CameraSession, reader: CameraSinkReading, sender: CameraFrameSender,
        retryDelay: TimeInterval, clock: @escaping () -> Date, hostTime: @escaping () -> CMTime
    ) {
        self.queue = queue
        self.session = session
        self.reader = reader
        self.sender = sender
        self.retryDelay = retryDelay
        self.clock = clock
        self.hostTime = hostTime
    }

    /// Asks for the next frame. Call on the frame queue.
    func consumeNextFrame(from client: CMIOExtensionClient) {
        guard session.isSinkRunning else { return }
        reader.consumeFrame(from: client) { [weak self] sampleBuffer, sequenceNumber in
            guard let self else { return }
            self.queue.async { self.handle(sampleBuffer, sequenceNumber: sequenceNumber, client: client) }
        }
    }

    private func handle(_ sampleBuffer: CMSampleBuffer?, sequenceNumber: UInt64, client: CMIOExtensionClient) {
        let step = session.sinkAnswered(withFrame: sampleBuffer != nil, at: clock())
        guard step != .retryLater else {
            queue.asyncAfter(deadline: .now() + retryDelay) { self.consumeNextFrame(from: client) }
            return
        }
        let now = hostTime()
        if step == .passOn, let sampleBuffer { sender.send(TimedFrame(sampleBuffer: sampleBuffer, time: now)) }
        reader.announceOutput(sequenceNumber: sequenceNumber, at: now)
        consumeNextFrame(from: client)
    }
}
