import XCTest
@testable import CamTwistCore

final class CameraFeedStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)

    func testThePlaceholderShowsBeforeTheAppHasSentAnything() {
        XCTAssertTrue(CameraFeedState().needsPlaceholder(at: start))
    }

    func testTheAppGetsTheTimeoutBeforeThePlaceholderReturns() {
        var state = CameraFeedState()
        _ = state.sinkFrameArrived(at: start)
        XCTAssertFalse(state.needsPlaceholder(at: start.addingTimeInterval(Pacing.usual.cameraSilenceTimeout)))
        XCTAssertTrue(state.needsPlaceholder(at: start.addingTimeInterval(Pacing.usual.cameraSilenceTimeout + 0.1)))
    }

    func testALongerTimeoutKeepsTheAppFramesUpLonger() {
        var state = CameraFeedState(silenceTimeout: 10)
        _ = state.sinkFrameArrived(at: start)
        XCTAssertFalse(state.needsPlaceholder(at: start.addingTimeInterval(5)))
        XCTAssertTrue(state.needsPlaceholder(at: start.addingTimeInterval(10.1)))
    }

    func testStoppingTheSinkBringsThePlaceholderBackAtOnce() {
        var state = CameraFeedState()
        _ = state.sinkFrameArrived(at: start)
        state.sinkStopped()
        XCTAssertTrue(state.needsPlaceholder(at: start))
    }

    func testAppFramesGoOnOnlyWhileSomebodyIsWatching() {
        var state = CameraFeedState()
        XCTAssertFalse(state.sinkFrameArrived(at: start))
        state.clientArrived()
        XCTAssertTrue(state.hasClients)
        XCTAssertTrue(state.sinkFrameArrived(at: start))
    }

    func testTheClientCountNeverGoesBelowNone() {
        var state = CameraFeedState()
        state.clientArrived()
        state.clientArrived()
        state.clientLeft()
        XCTAssertEqual(state.clients, 1)
        state.clientLeft()
        state.clientLeft()
        XCTAssertEqual(state.clients, 0)
        XCTAssertFalse(state.hasClients)
    }
}

final class CameraWatcherRegistryTests: XCTestCase {
    func testWatchersComeAndGo() {
        let registry = CameraWatcherRegistry()
        XCTAssertEqual(registry.propertyText, CameraWatchers.text(for: []))
        registry.add(10)
        registry.add(20)
        registry.add(10)
        XCTAssertEqual(CameraWatchers.processes(in: registry.propertyText).sorted(), [10, 20])
        registry.remove(10)
        XCTAssertEqual(CameraWatchers.processes(in: registry.propertyText), [20])
        registry.removeAll()
        XCTAssertEqual(registry.propertyText, CameraWatchers.text(for: []))
    }

    func testHostTimeIsInNanoseconds() {
        XCTAssertEqual(HostTime.nanoseconds(forSeconds: 1.5), 1_500_000_000)
    }
}
