import CamTwistCore
import XCTest
@testable import CamTwistControl

final class DragPayloadTests: XCTestCase {
    func testAStepSurvivesTheTripThroughText() {
        let content = ChainItem.Content.effect(name: "Ring", values: ["size": .number(2)])
        XCTAssertEqual(StepPayload.content(from: StepPayload.text(for: content)), content)
    }

    func testTextThatIsNotAStepIsRefused() {
        XCTAssertNil(StepPayload.content(from: "hello"))
        XCTAssertNil(StepPayload.content(from: StepPayload.text(for: .script(source: "x")).replacingOccurrences(of: "{", with: "(")))
    }

    func testAStepThatCannotBeWrittenBecomesAnEmptyPayload() {
        let broken = ChainItem.Content.effect(name: "Ring", values: ["size": .number(.nan)])
        XCTAssertNil(StepPayload.content(from: StepPayload.text(for: broken)))
    }

    func testASceneSurvivesTheTripThroughText() {
        let id = UUID()
        XCTAssertEqual(ScenePayload.id(from: ScenePayload.text(for: id)), id)
    }

    func testTextThatIsNotASceneIsRefused() {
        XCTAssertNil(ScenePayload.id(from: "hello"))
        XCTAssertNil(ScenePayload.id(from: "camtwisted-scene:nonsense"))
        XCTAssertNil(ScenePayload.id(from: StepPayload.text(for: .script(source: "x"))))
    }
}
