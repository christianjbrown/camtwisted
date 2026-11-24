import Foundation

/// A short tape of the last few moments, played back slower than it was
/// recorded. Playing slowly falls behind what is happening, so once it is
/// too far behind it cuts forward to now and starts again.
public struct SlowMotionTape<Frame> {
    /// What to show at a moment: two neighbouring frames of the tape and
    /// how far the playback is from the first to the second, 0 to 1.
    public struct Showing {
        public let from: Frame
        public let to: Frame
        public let mix: Double
    }

    private let captureInterval: TimeInterval
    private let longestLag: TimeInterval
    private var frames: [(time: TimeInterval, frame: Frame)] = []
    /// The moment of the tape being shown, and when that was last moved on.
    private var playhead: TimeInterval?
    private var lastPlayed: TimeInterval?

    /// - Parameters:
    ///   - captureInterval: seconds between the frames kept.
    ///   - longestLag: how far behind playback may fall before it cuts to now.
    public init(captureInterval: TimeInterval, longestLag: TimeInterval) {
        self.captureInterval = captureInterval
        self.longestLag = longestLag
    }

    /// How many frames are being kept.
    public var count: Int { frames.count }

    /// Empties the tape, as when the effect is switched to full speed.
    public mutating func clear() {
        frames.removeAll()
        playhead = nil
        lastPlayed = nil
    }

    /// Moves on to a moment and says what to show. A frame is asked for
    /// when it is time to keep another. Speed is a share of real time: a
    /// half plays every second of tape over two.
    public mutating func advance(to time: TimeInterval, speed: Double, capture: () -> Frame) -> Showing {
        if let newest = frames.last?.time, time < newest {
            // Time running backwards means the clock was started again.
            clear()
        }
        if frames.last.map({ time - $0.time >= captureInterval }) ?? true {
            frames.append((time, capture()))
        }
        let elapsed = max(time - (lastPlayed ?? time), 0)
        lastPlayed = time
        var position = min((playhead ?? frames[0].time) + elapsed * speed, time)
        if time - position > longestLag {
            // Too far behind: cut to the newest frame and carry on from there.
            position = time
            frames.removeFirst(frames.count - 1)
        }
        playhead = position
        // Frames the playback has passed are let go.
        while frames.count > 1, frames[1].time <= position {
            frames.removeFirst()
        }
        let from = frames[0]
        guard frames.count > 1 else { return Showing(from: from.frame, to: from.frame, mix: 0) }
        let to = frames[1]
        let mix = min(max((position - from.time) / (to.time - from.time), 0), 1)
        return Showing(from: from.frame, to: to.frame, mix: mix)
    }
}

/// Decides when a stop motion film takes its next picture.
public struct StopMotionClock {
    private let interval: TimeInterval
    private var lastShot: TimeInterval?

    /// - Parameter picturesPerSecond: how many pictures are taken a second.
    public init(picturesPerSecond: Double) {
        interval = 1 / picturesPerSecond
    }

    /// Whether a new picture is due at this moment. Saying yes counts as
    /// taking it.
    public mutating func isDue(at time: TimeInterval) -> Bool {
        if let lastShot, time >= lastShot, time - lastShot < interval { return false }
        lastShot = time
        return true
    }
}
