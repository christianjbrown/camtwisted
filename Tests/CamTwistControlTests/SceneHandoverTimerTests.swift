import CamTwistCore
import XCTest
@testable import CamTwistControl

@MainActor
final class SceneHandoverTimerTests: XCTestCase {
    private static let seconds = 45.0
    private static let fewerSeconds = 10.0

    private let state = FakeState()
    private let timers = FakeTimers()
    private let first = StudioButton(name: "Sponsor", scene: SceneConfiguration())
    private let second = StudioButton(name: "Show", scene: SceneConfiguration())

    private func makeTimer() -> SceneHandoverTimer {
        SceneHandoverTimer(state: state, timers: timers)
    }

    /// The first scene on air, handing over to the second.
    private func studio(seconds: Double = SceneHandoverTimerTests.seconds) -> StudioSettings {
        var handing = first
        handing.handover = SceneHandover(sceneID: second.id, seconds: seconds)
        return StudioSettings(buttons: [handing, second], onAirID: first.id)
    }

    func testTheSceneOnAirHandsOverOnceItsTimeIsUp() {
        let timer = makeTimer()
        timer.follow(studio())
        XCTAssertEqual(timers.scheduled.map(\.seconds), [Self.seconds])
        timers.fire(0)
        XCTAssertEqual(state.wentLive, [second.id])
    }

    func testNothingCountsDownForASceneThatStaysOnAir() {
        let timer = makeTimer()
        timer.follow(StudioSettings(buttons: [first, second], onAirID: first.id))
        timer.follow(StudioSettings(buttons: [first, second]))
        XCTAssertTrue(timers.scheduled.isEmpty)
    }

    func testTheSameSceneOnAirKeepsItsCountdownGoing() {
        let timer = makeTimer()
        timer.follow(studio())
        timer.follow(studio())
        XCTAssertEqual(timers.scheduled.count, 1)
        XCTAssertFalse(timers.scheduled[0].work.isCancelled)
    }

    func testPuttingAnotherSceneOnAirCallsTheCountdownOff() {
        let timer = makeTimer()
        timer.follow(studio())
        var changed = studio()
        changed.onAirID = second.id
        timer.follow(changed)
        XCTAssertTrue(timers.scheduled[0].work.isCancelled)
        XCTAssertEqual(timers.scheduled.count, 1, "the second scene stays on air")
    }

    func testChangingTheTimeStartsTheCountdownAgain() {
        let timer = makeTimer()
        timer.follow(studio())
        timer.follow(studio(seconds: Self.fewerSeconds))
        XCTAssertTrue(timers.scheduled[0].work.isCancelled)
        XCTAssertEqual(timers.scheduled.map(\.seconds), [Self.seconds, Self.fewerSeconds])
    }

    func testAFinishedCountdownCanRunAgainWhenTheSceneComesBack() {
        let timer = makeTimer()
        timer.follow(studio())
        timers.fire(0)
        timer.follow(studio())
        XCTAssertEqual(timers.scheduled.count, 2, "the fake state did not change scene, so it counts down again")
    }

    func testATimerThatHasGoneDoesNothingWhenItsTimeIsUp() {
        var timer: SceneHandoverTimer? = makeTimer()
        timer?.follow(studio())
        timer = nil
        timers.fire(0)
        XCTAssertTrue(state.wentLive.isEmpty)
    }
}
