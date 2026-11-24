import Foundation

/// Makes the queues the sources and outputs do their work on. The
/// composition root hands one in, so nothing makes a queue for itself.
public protocol QueueMaking {
    func makeQueue(label: String, qos: DispatchQoS) -> DispatchQueue
}

/// Makes the system's own dispatch queues.
public struct DispatchQueues: QueueMaking {
    public init() {}

    public func makeQueue(label: String, qos: DispatchQoS) -> DispatchQueue {
        DispatchQueue(label: label, qos: qos)
    }
}

/// The two clocks the outputs read: one that only goes forward, for
/// timing frames, and the one on the wall, for naming files and markers.
public struct Clocks {
    /// Seconds since the Mac started, which never jumps.
    public let uptime: () -> Double
    /// The time by the clock on the wall.
    public let today: () -> Date

    public init(uptime: @escaping () -> Double, today: @escaping () -> Date) {
        self.uptime = uptime
        self.today = today
    }

    /// The system's own, which is what the app runs with.
    public static let system = Clocks(uptime: SteadyClock.uptime, today: Date.init)
}
