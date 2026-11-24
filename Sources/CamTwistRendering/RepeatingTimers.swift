import Foundation

/// Something that can be stopped.
public protocol Cancelling {
    func cancel()
}

/// Makes timers that repeat. Abstracted so what happens on each tick can be
/// tested without waiting.
public protocol RepeatingTimers {
    /// Runs the action every interval, until the result is cancelled.
    func every(_ interval: TimeInterval, _ action: @escaping () -> Void) -> Cancelling
}

/// Repeating timers on the current run loop, so callers use them on the
/// main queue.
public struct RunLoopTimers: RepeatingTimers {
    public init() {}

    public func every(_ interval: TimeInterval, _ action: @escaping () -> Void) -> Cancelling {
        TimerCancelling(timer: Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in action() })
    }
}

/// Stops a run loop timer.
struct TimerCancelling: Cancelling {
    let timer: Timer

    func cancel() {
        timer.invalidate()
    }
}
