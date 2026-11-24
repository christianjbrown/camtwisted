import XCTest
@testable import CamTwistRendering

final class RenderingSystemTests: XCTestCase {
    private static let shortWait: TimeInterval = 0.01
    private static let picks = 20

    func testTheSleeperWaitsAndTheIndexPickerStaysInItsRange() async throws {
        try await RenderingSystem.sleeper(Self.shortWait)

        let range = 3..<7
        for _ in 0..<Self.picks {
            XCTAssertTrue(range.contains(RenderingSystem.indexPicker(range)))
        }
    }

    func testTheMainHopRunsItsWorkOnTheMainThread() {
        let done = expectation(description: "ran")
        RenderingSystem.mainHop {
            XCTAssertTrue(Thread.isMainThread)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testItMakesAFreshPlayerNodeAndPlayer() {
        XCTAssertFalse(RenderingSystem.makePlayerNode() === RenderingSystem.makePlayerNode())
        XCTAssertNil(RenderingSystem.makePlayer().currentItem)
    }
}
