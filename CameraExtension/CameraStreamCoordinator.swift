import CamTwistCore
import CoreMediaIO
import Foundation

/// Turns the streams' start and stop requests into work on the frame queue.
final class CameraStreamCoordinator: CameraStreamController {
    private let queue: DispatchQueue
    private let session: CameraSession
    private let watchers: CameraWatcherRegistry
    private let pump: PlaceholderFramePump
    private let consumer: SinkFrameConsumer

    init(
        queue: DispatchQueue, session: CameraSession, watchers: CameraWatcherRegistry, pump: PlaceholderFramePump,
        consumer: SinkFrameConsumer
    ) {
        self.queue = queue
        self.session = session
        self.watchers = watchers
        self.pump = pump
        self.consumer = consumer
    }

    func sourceWanted(byProcess process: pid_t) {
        watchers.add(process)
    }

    func startSource() {
        queue.async {
            if self.session.sourceStarted() == .startPump { self.pump.start() }
        }
    }

    func stopSource() {
        queue.async {
            guard self.session.sourceStopped() == .closeDown else { return }
            // Nobody has the picture open any more.
            self.watchers.removeAll()
            self.pump.stop()
        }
    }

    func startSink(client: CMIOExtensionClient) {
        queue.async {
            self.session.sinkStarted()
            self.consumer.consumeNextFrame(from: client)
        }
    }

    func stopSink() {
        queue.async { self.session.sinkStopped() }
    }
}
