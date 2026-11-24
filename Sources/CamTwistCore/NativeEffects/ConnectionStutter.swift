import Foundation

/// Decides when a picture on a bad connection is stuck: live for a while,
/// then frozen for a moment, at random.
public struct ConnectionStutter<Random: RandomSource> {
    /// Chance is taken in steps this fine.
    private static var steps: Int { 1000 }
    /// The gap between freezes varies from half to one and a half times its average.
    private static var shortestGapShare: Double { 0.5 }
    /// No freeze is shorter than this many seconds: less would not be seen.
    private static var shortestFreeze: Double { 0.15 }
    private static var secondsPerMinute: Double { 60 }

    private var random: Random
    private var isFrozen = false
    private var changesAt: Double?

    public init(random: Random) {
        self.random = random
    }

    /// Whether the picture is stuck at this moment. `freezesPerMinute` is
    /// how often it sticks on average, and `longestFreeze` the most seconds
    /// it stays stuck. With no freezes asked for it never sticks.
    public mutating func isFrozen(at time: Double, freezesPerMinute: Double, longestFreeze: Double) -> Bool {
        guard freezesPerMinute > 0 else {
            isFrozen = false
            changesAt = nil
            return false
        }
        let averageGap = Self.secondsPerMinute / freezesPerMinute
        guard let due = changesAt else {
            changesAt = time + gap(around: averageGap)
            return false
        }
        if time >= due {
            isFrozen.toggle()
            changesAt = time + (isFrozen ? freeze(upTo: longestFreeze) : gap(around: averageGap))
        }
        return isFrozen
    }

    /// A share of the way from nothing to everything, at random.
    private mutating func chance() -> Double {
        Double(random.below(Self.steps)) / Double(Self.steps)
    }

    private mutating func gap(around average: Double) -> Double {
        average * (Self.shortestGapShare + chance())
    }

    private mutating func freeze(upTo longest: Double) -> Double {
        let longest = max(longest, Self.shortestFreeze)
        return Self.shortestFreeze + (longest - Self.shortestFreeze) * chance()
    }
}
