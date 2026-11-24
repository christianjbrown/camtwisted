import XCTest
@testable import CamTwistCore

final class CameraSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)
    private let timeout: TimeInterval = 2

    private func session() -> CameraSession {
        CameraSession(silenceTimeout: timeout)
    }

    func testTheFirstReaderStartsThePumpAndLaterOnesLeaveItBe() {
        let session = session()
        XCTAssertEqual(session.sourceStarted(), .startPump)
        XCTAssertEqual(session.sourceStarted(), .leaveAlone)
    }

    func testThePumpStopsOnlyWhenTheLastReaderLeaves() {
        let session = session()
        _ = session.sourceStarted()
        _ = session.sourceStarted()
        XCTAssertEqual(session.sourceStopped(), .leaveAlone)
        XCTAssertEqual(session.sourceStopped(), .closeDown)
        XCTAssertEqual(session.sourceStarted(), .startPump)
    }

    func testClosingDownHappensEvenWithNoReadersToBeginWith() {
        XCTAssertEqual(session().sourceStopped(), .closeDown)
    }

    func testTheSinkRunsBetweenItsStartAndStop() {
        let session = session()
        XCTAssertFalse(session.isSinkRunning)
        session.sinkStarted()
        XCTAssertTrue(session.isSinkRunning)
        session.sinkStopped()
        XCTAssertFalse(session.isSinkRunning)
    }

    func testAnEmptyAnswerIsTriedAgainLater() {
        XCTAssertEqual(session().sinkAnswered(withFrame: false, at: start), .retryLater)
    }

    func testAFramePassesOnOnlyWhileSomebodyWatches() {
        let session = session()
        XCTAssertEqual(session.sinkAnswered(withFrame: true, at: start), .holdBack)
        _ = session.sourceStarted()
        XCTAssertEqual(session.sinkAnswered(withFrame: true, at: start), .passOn)
    }

    func testThePlaceholderWaitsForTheTimeoutAndReturnsWhenTheSinkStops() {
        let session = session()
        XCTAssertTrue(session.needsPlaceholder(at: start))
        _ = session.sinkAnswered(withFrame: true, at: start)
        XCTAssertFalse(session.needsPlaceholder(at: start.addingTimeInterval(timeout)))
        XCTAssertTrue(session.needsPlaceholder(at: start.addingTimeInterval(timeout + 0.1)))
        _ = session.sinkAnswered(withFrame: true, at: start)
        session.sinkStopped()
        XCTAssertTrue(session.needsPlaceholder(at: start))
    }
}
