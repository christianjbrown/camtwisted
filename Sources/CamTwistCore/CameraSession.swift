import Foundation

/// What the frame pump has to do after a reader starts or stops.
public enum CameraPumpChange: Equatable {
    case startPump
    /// Nobody has the picture open any more: forget the watchers and stop the pump.
    case closeDown
    case leaveAlone
}

/// What to do with the answer to a request for the app's next frame.
public enum CameraSinkStep: Equatable {
    /// The sink had nothing: ask again after a pause.
    case retryLater
    /// A frame came and goes on to the readers.
    case passOn
    /// A frame came but nobody is watching, so it is not passed on.
    case holdBack
}

/// The decisions of the virtual camera's frame queue: when the pump runs,
/// what to do with the sink's answers and when the placeholder shows.
/// Used from the extension's frame queue only.
public final class CameraSession {
    private var feed: CameraFeedState
    private var pumpRunning = false
    /// Whether the app's sink stream is being read.
    public private(set) var isSinkRunning = false

    public init(silenceTimeout: TimeInterval) {
        feed = CameraFeedState(silenceTimeout: silenceTimeout)
    }

    /// A reader opened the picture.
    public func sourceStarted() -> CameraPumpChange {
        feed.clientArrived()
        guard !pumpRunning else { return .leaveAlone }
        pumpRunning = true
        return .startPump
    }

    /// A reader let go.
    public func sourceStopped() -> CameraPumpChange {
        feed.clientLeft()
        guard !feed.hasClients else { return .leaveAlone }
        pumpRunning = false
        return .closeDown
    }

    public func sinkStarted() {
        isSinkRunning = true
    }

    public func sinkStopped() {
        isSinkRunning = false
        feed.sinkStopped()
    }

    /// The sink answered, with a frame or without one.
    public func sinkAnswered(withFrame hasFrame: Bool, at time: Date) -> CameraSinkStep {
        guard hasFrame else { return .retryLater }
        return feed.sinkFrameArrived(at: time) ? .passOn : .holdBack
    }

    /// Whether the placeholder goes out on this tick.
    public func needsPlaceholder(at time: Date) -> Bool {
        feed.needsPlaceholder(at: time)
    }
}
