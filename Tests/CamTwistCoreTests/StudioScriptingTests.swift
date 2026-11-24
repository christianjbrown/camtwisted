import XCTest
@testable import CamTwistCore

final class StudioScriptingTests: XCTestCase {
    private func settings(_ names: [String]) -> StudioSettings {
        StudioSettings(buttons: names.map { StudioButton(name: $0, scene: SceneConfiguration()) })
    }

    func testRemovingByNameTakesEverySceneCalledThat() {
        var studio = settings(["Wide", "Close", "Wide"])
        studio.removeButtons(named: "Wide")
        XCTAssertEqual(studio.buttons.map(\.name), ["Close"])
        studio.removeButtons(named: "Missing")
        XCTAssertEqual(studio.buttons.count, 1)
    }

    func testDuplicatingByNameAddsACopyAtTheEnd() {
        var studio = settings(["Wide", "Close"])
        studio.appendDuplicate(ofButtonNamed: "Wide")
        XCTAssertEqual(studio.buttons.count, 3)
        XCTAssertNotEqual(studio.buttons[2].id, studio.buttons[0].id)
    }

    func testDuplicatingASceneThatIsNotThereChangesNothing() {
        var studio = settings(["Wide"])
        studio.appendDuplicate(ofButtonNamed: "Missing")
        XCTAssertEqual(studio.buttons.count, 1)
    }
}
