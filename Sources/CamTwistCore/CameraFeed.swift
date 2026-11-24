import Foundation

// The bookkeeping of the virtual camera inside its extension, which can
// only link this library: who is watching, and which frame goes out when.

/// Decides when the camera shows the host app's frames and when its
/// placeholder. Used from the extension's frame queue only.
public struct CameraFeedState: Equatable {
    /// How many readers have the picture open.
    public private(set) var clients = 0
    private var lastSinkFrame = Date.distantPast
    /// How long the app may be silent before the placeholder returns.
    private let silenceTimeout: TimeInterval

    public init(silenceTimeout: TimeInterval = Pacing.usual.cameraSilenceTimeout) {
        self.silenceTimeout = silenceTimeout
    }

    public var hasClients: Bool { clients > 0 }

    public mutating func clientArrived() {
        clients += 1
    }

    /// A reader let go. There are never fewer than none.
    public mutating func clientLeft() {
        clients = max(clients - 1, 0)
    }

    /// The app sent a frame. Returns whether it goes on to the readers.
    public mutating func sinkFrameArrived(at time: Date) -> Bool {
        lastSinkFrame = time
        return hasClients
    }

    /// The app stopped sending, so the placeholder may return at once.
    public mutating func sinkStopped() {
        lastSinkFrame = .distantPast
    }

    /// Whether the app has been silent long enough for the placeholder to show.
    public func needsPlaceholder(at time: Date) -> Bool {
        time.timeIntervalSince(lastSinkFrame) > silenceTimeout
    }
}

/// The processes that have asked for the picture and not yet gone, which
/// is what the app is told about who is watching. Changed and read on
/// different queues, so it guards itself.
public final class CameraWatcherRegistry {
    private let lock = NSLock()
    private var processes: Set<Int32> = []

    public init() {}

    public func add(_ process: Int32) {
        locked { _ = $0.insert(process) }
    }

    public func remove(_ process: Int32) {
        locked { _ = $0.remove(process) }
    }

    public func removeAll() {
        locked { $0.removeAll() }
    }

    /// What the property carries to the app.
    public var propertyText: String {
        CameraWatchers.text(for: locked { Array($0) })
    }

    private func locked<Result>(_ change: (inout Set<Int32>) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return change(&processes)
    }
}

/// Core Media I/O stamps frames with the host clock in nanoseconds.
public enum HostTime {
    private static let nanosecondsPerSecond = 1_000_000_000.0

    public static func nanoseconds(forSeconds seconds: Double) -> UInt64 {
        UInt64(seconds * nanosecondsPerSecond)
    }
}
