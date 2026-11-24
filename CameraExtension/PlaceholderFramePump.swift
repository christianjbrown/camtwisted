import CamTwistCore
import Foundation

/// Ticks once a frame and sends the placeholder whenever the app is silent.
final class PlaceholderFramePump {
    private let queue: DispatchQueue
    private let interval: TimeInterval
    private let session: CameraSession
    private let frames: PlaceholderFrameMaking
    private let sender: CameraFrameSender
    private let clock: () -> Date
    private var timer: DispatchSourceTimer?

    init(
        queue: DispatchQueue, interval: TimeInterval, session: CameraSession, frames: PlaceholderFrameMaking,
        sender: CameraFrameSender, clock: @escaping () -> Date
    ) {
        self.queue = queue
        self.interval = interval
        self.session = session
        self.frames = frames
        self.sender = sender
        self.clock = clock
    }

    /// Starts ticking. Call on the frame queue.
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    /// Stops ticking. Call on the frame queue.
    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard session.needsPlaceholder(at: clock()), let frame = frames.makeFrame() else { return }
        sender.send(frame)
    }
}
