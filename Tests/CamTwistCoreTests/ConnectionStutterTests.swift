import XCTest
@testable import CamTwistCore

/// Hands back the same number every time, so gaps and freezes are known.
private struct SteadyRandom: RandomSource {
    let value: UInt32
    mutating func next() -> UInt32 { value }
}

final class ConnectionStutterTests: XCTestCase {
    func testItRunsLiveThenFreezesThenRunsAgain() {
        // Chance comes out as a half every time: gaps are the average
        // (5 seconds at 12 a minute), freezes are midway to the longest.
        var stutter = ConnectionStutter(random: SteadyRandom(value: 500))
        func frozen(_ time: Double) -> Bool {
            stutter.isFrozen(at: time, freezesPerMinute: 12, longestFreeze: 2.15)
        }
        XCTAssertFalse(frozen(0), "it starts live")
        XCTAssertFalse(frozen(4.9))
        XCTAssertTrue(frozen(5), "the first gap is up")
        XCTAssertTrue(frozen(6.1), "the freeze lasts 1.15 seconds")
        XCTAssertFalse(frozen(6.2))
        XCTAssertFalse(frozen(11.1))
        XCTAssertTrue(frozen(11.2), "and it sticks again a gap later")
    }

    func testWithNoFreezesAskedForItNeverSticksAndStartsAfresh() {
        var stutter = ConnectionStutter(random: SteadyRandom(value: 0))
        XCTAssertFalse(stutter.isFrozen(at: 0, freezesPerMinute: 60, longestFreeze: 0))
        XCTAssertTrue(stutter.isFrozen(at: 0.5, freezesPerMinute: 60, longestFreeze: 0), "the shortest gap is half the average")
        XCTAssertFalse(stutter.isFrozen(at: 0.6, freezesPerMinute: 0, longestFreeze: 0))
        XCTAssertFalse(stutter.isFrozen(at: 100, freezesPerMinute: 60, longestFreeze: 0), "switched back on, it starts live")
        XCTAssertTrue(stutter.isFrozen(at: 100.5, freezesPerMinute: 60, longestFreeze: 0))
        XCTAssertFalse(
            stutter.isFrozen(at: 100.66, freezesPerMinute: 60, longestFreeze: 0),
            "even with no length asked for, a freeze is long enough to see and then ends"
        )
    }
}
