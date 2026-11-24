import XCTest
@testable import CamTwistCore

final class SlowMotionTapeTests: XCTestCase {
    /// A tape that keeps a frame every half second and may fall two seconds behind.
    private func makeTape() -> SlowMotionTape<String> {
        SlowMotionTape(captureInterval: 0.5, longestLag: 2)
    }

    func testTheFirstMomentShowsTheFrameJustTaken() {
        var tape = makeTape()
        let showing = tape.advance(to: 10, speed: 0.5) { "a" }
        XCTAssertEqual(showing.from, "a")
        XCTAssertEqual(showing.to, "a")
        XCTAssertEqual(showing.mix, 0)
        XCTAssertEqual(tape.count, 1)
    }

    func testFramesAreKeptOnlyAsOftenAsAsked() {
        var tape = makeTape()
        var taken = 0
        for step in 0...8 {
            _ = tape.advance(to: Double(step) * 0.125, speed: 0.5) {
                taken += 1
                return "frame"
            }
        }
        XCTAssertEqual(taken, 3, "at 0, a half and one second")
    }

    func testPlaybackRunsAtAShareOfRealTimeAndBlendsBetweenFrames() {
        var tape = makeTape()
        _ = tape.advance(to: 0, speed: 0.5) { "a" }
        _ = tape.advance(to: 0.5, speed: 0.5) { "b" }
        // Half a second has passed, so the tape has played a quarter: half way from a to b.
        let half = tape.advance(to: 0.5, speed: 0.5) { "unused" }
        XCTAssertEqual(half.from, "a")
        XCTAssertEqual(half.to, "b")
        XCTAssertEqual(half.mix, 0.5, accuracy: 1e-9)

        // A second in, the tape is at a half second: frame b, and a is let go.
        let whole = tape.advance(to: 1, speed: 0.5) { "c" }
        XCTAssertEqual(whole.from, "b")
        XCTAssertEqual(whole.to, "c")
        XCTAssertEqual(whole.mix, 0, accuracy: 1e-9)
        XCTAssertEqual(tape.count, 2)
    }

    func testPlaybackNeverRunsAheadOfNow() {
        var tape = makeTape()
        _ = tape.advance(to: 0, speed: 3) { "a" }
        let showing = tape.advance(to: 0.5, speed: 3) { "b" }
        XCTAssertEqual(showing.from, "b", "three times real time would be the future")
        XCTAssertEqual(showing.mix, 0)
    }

    func testFallingTooFarBehindCutsForwardToNow() {
        var tape = makeTape()
        var showing = tape.advance(to: 0, speed: 0.1) { "0" }
        for step in 1...5 {
            let time = Double(step) * 0.5
            showing = tape.advance(to: time, speed: 0.1) { "\(time)" }
        }
        // At two and a half seconds the tape has played a quarter of one: more than two behind.
        XCTAssertEqual(showing.from, "2.5", "cut to the newest frame")
        XCTAssertEqual(showing.mix, 0)
        XCTAssertEqual(tape.count, 1)
    }

    func testAClockStartedAgainStartsTheTapeAgain() {
        var tape = makeTape()
        _ = tape.advance(to: 100, speed: 0.5) { "old" }
        _ = tape.advance(to: 100.5, speed: 0.5) { "older" }
        let showing = tape.advance(to: 1, speed: 0.5) { "new" }
        XCTAssertEqual(showing.from, "new")
        XCTAssertEqual(tape.count, 1)

        tape.clear()
        XCTAssertEqual(tape.count, 0)
        XCTAssertEqual(tape.advance(to: 2, speed: 0.5) { "fresh" }.from, "fresh")
    }

    func testAStopMotionFilmTakesItsPicturesAtASteadyRate() {
        var clock = StopMotionClock(picturesPerSecond: 4)
        XCTAssertTrue(clock.isDue(at: 10), "the first moment always takes one")
        XCTAssertFalse(clock.isDue(at: 10.1))
        XCTAssertFalse(clock.isDue(at: 10.24))
        XCTAssertTrue(clock.isDue(at: 10.25))
        XCTAssertFalse(clock.isDue(at: 10.3))
        XCTAssertTrue(clock.isDue(at: 3), "a clock started again takes one straight away")
    }
}
