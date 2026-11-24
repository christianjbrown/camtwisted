import XCTest
@testable import CamTwistCore

final class CountdownTests: XCTestCase {
    func testTimesAreReadAsHoursMinutesAndSeconds() {
        XCTAssertEqual(CountdownClock.seconds(fromText: "01:02:03"), 3723)
        XCTAssertEqual(CountdownClock.seconds(fromText: "5:00"), 300)
        XCTAssertEqual(CountdownClock.seconds(fromText: " 45 "), 45)
        XCTAssertEqual(CountdownClock.seconds(fromText: "soon"), 0)
        XCTAssertEqual(CountdownClock.seconds(fromText: "1:-5"), 0)
        XCTAssertEqual(CountdownClock.seconds(fromText: "1::5"), 0)
    }

    func testCountingDownStopsAtZeroUnlessToldToCarryOn() {
        let down = CountdownSettings(length: 10)
        XCTAssertEqual(CountdownClock.secondsShown(elapsed: 0, settings: down), 10)
        XCTAssertEqual(CountdownClock.secondsShown(elapsed: 0.5, settings: down), 10)
        XCTAssertEqual(CountdownClock.secondsShown(elapsed: 10, settings: down), 0)
        XCTAssertEqual(CountdownClock.secondsShown(elapsed: 25, settings: down), 0)
        let onward = CountdownSettings(length: 10, carriesOnPastZero: true)
        XCTAssertEqual(CountdownClock.secondsShown(elapsed: 25.9, settings: onward), 15)
    }

    func testCountingUpStopsAtItsLengthWhenItHasOne() {
        let up = CountdownSettings(length: 10, countsUp: true)
        XCTAssertEqual(CountdownClock.secondsShown(elapsed: 3.9, settings: up), 3)
        XCTAssertEqual(CountdownClock.secondsShown(elapsed: 30, settings: up), 10)
        let endless = CountdownSettings(length: 0, countsUp: true)
        XCTAssertEqual(CountdownClock.secondsShown(elapsed: 30, settings: endless), 30)
    }

    func testSecondsAreWrittenWithHoursOnlyWhenThereAreSome() {
        XCTAssertEqual(CountdownClock.text(forSeconds: 0), "00:00")
        XCTAssertEqual(CountdownClock.text(forSeconds: 305), "05:05")
        XCTAssertEqual(CountdownClock.text(forSeconds: 3723), "1:02:03")
    }

    func testAStopwatchRunsPausesAndIsHeld() {
        var watch = Stopwatch()
        watch.advance(to: 100, isPaused: false, isHeld: false)
        XCTAssertEqual(watch.elapsed, 0, "the first time it is shown starts it")
        watch.advance(to: 103, isPaused: false, isHeld: false)
        XCTAssertEqual(watch.elapsed, 3)
        watch.advance(to: 110, isPaused: true, isHeld: false)
        XCTAssertEqual(watch.elapsed, 3)
        watch.advance(to: 111, isPaused: false, isHeld: false)
        XCTAssertEqual(watch.elapsed, 4)
        watch.advance(to: 105, isPaused: false, isHeld: false)
        XCTAssertEqual(watch.elapsed, 4, "a clock that goes backwards adds nothing")
        watch.advance(to: 120, isPaused: false, isHeld: true)
        XCTAssertEqual(watch.elapsed, 0)
    }
}
