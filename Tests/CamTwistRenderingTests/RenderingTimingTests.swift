@testable import CamTwistRendering
import XCTest

final class RenderingTimingTests: XCTestCase {
    func testTheQueuesAreMadeWithTheLabelAndPriorityAskedFor() {
        let queue = DispatchQueues().makeQueue(label: "test.queue", qos: .userInteractive)

        XCTAssertEqual(queue.label, "test.queue")
        XCTAssertEqual(queue.qos, .userInteractive)
    }

    func testTheSystemClocksReadTheMachineAndTheWall() {
        let before = Date()

        XCTAssertGreaterThan(Clocks.system.uptime(), 0)
        XCTAssertGreaterThanOrEqual(Clocks.system.today(), before)
    }

    func testClocksHandBackWhatTheyAreGiven() {
        let moment = Date(timeIntervalSince1970: 0)
        let clocks = Clocks(uptime: { 42 }, today: { moment })

        XCTAssertEqual(clocks.uptime(), 42)
        XCTAssertEqual(clocks.today(), moment)
    }
}
