import Foundation

/// What a countdown counts: how long, and which way.
public struct CountdownSettings: Equatable, Sendable {
    /// Seconds to count down from, or up to. Counting up with no length
    /// carries on for ever.
    public var length: Double
    public var countsUp: Bool
    /// Counting down, whether to carry on upwards after reaching zero.
    public var carriesOnPastZero: Bool

    public init(length: Double, countsUp: Bool = false, carriesOnPastZero: Bool = false) {
        self.length = length
        self.countsUp = countsUp
        self.carriesOnPastZero = carriesOnPastZero
    }
}

/// Works out what a countdown shows.
public enum CountdownClock {
    private static let secondsPerMinute = 60
    private static let minutesPerHour = 60
    private static let separator: Character = ":"
    private static let twoDigits = "%02d"

    /// The seconds in a time written as hours, minutes and seconds, minutes
    /// and seconds, or seconds alone. Anything else counts as nothing.
    public static func seconds(fromText text: String) -> Double {
        var total = 0.0
        for part in text.split(separator: separator, omittingEmptySubsequences: false) {
            guard let value = Double(part.trimmingCharacters(in: .whitespaces)), value >= 0 else { return 0 }
            total = total * Double(secondsPerMinute) + value
        }
        return total
    }

    /// The whole seconds on show after some time has run.
    public static func secondsShown(elapsed: Double, settings: CountdownSettings) -> Int {
        if settings.countsUp {
            let reached = settings.length > 0 ? min(elapsed, settings.length) : elapsed
            return Int(reached.rounded(.down))
        }
        let remaining = settings.length - elapsed
        if remaining >= 0 {
            // Rounded up, so the full length shows at the start and zero
            // only once the time is really up.
            return Int(remaining.rounded(.up))
        }
        return settings.carriesOnPastZero ? Int((-remaining).rounded(.down)) : 0
    }

    /// Seconds as minutes and seconds, with hours in front once there are any.
    public static func text(forSeconds seconds: Int) -> String {
        let minutes = seconds / secondsPerMinute
        let tail = String(format: twoDigits, minutes % minutesPerHour)
            + String(separator) + String(format: twoDigits, seconds % secondsPerMinute)
        let hours = minutes / minutesPerHour
        return hours > 0 ? String(hours) + String(separator) + tail : tail
    }
}

/// Adds up running time from the clock times it is shown, and can be
/// paused or held at nothing.
public struct Stopwatch: Equatable, Sendable {
    public private(set) var elapsed = 0.0
    private var last: Double?

    public init() {}

    public mutating func advance(to time: Double, isPaused: Bool, isHeld: Bool) {
        if isHeld {
            elapsed = 0
        } else if let last, !isPaused, time > last {
            elapsed += time - last
        }
        last = time
    }
}
