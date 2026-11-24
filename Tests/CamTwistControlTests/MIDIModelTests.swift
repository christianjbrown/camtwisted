import CamTwistCore
import XCTest
@testable import CamTwistControl

@MainActor
final class MIDIModelTests: XCTestCase {
    private static let key = 40
    private static let otherKey = 41

    private let state = FakeState()
    private let listener = FakeMIDI()

    private func makeModel() -> MIDIModel {
        MIDIModel(state: state, listener: listener, learner: MIDILearner(), queue: ImmediateQueue())
    }

    func testNothingIsHeardUntilItStarts() {
        let model = makeModel()
        XCTAssertNil(listener.onNote)
        model.start()
        XCTAssertEqual(listener.startCount, 1)
        XCTAssertNotNil(listener.onNote)
    }

    func testANotePutsItsSceneOnAirAndIsRemembered() {
        let scene = StudioButton(name: "Wide", scene: SceneConfiguration(), midiNote: Self.key)
        state.studio.buttons = [scene]
        let model = makeModel()
        model.start()
        listener.onNote?(Self.key)
        XCTAssertEqual(state.wentLive, [scene.id])
        XCTAssertEqual(model.lastNote, Self.key)
        listener.onNote?(Self.otherKey)
        XCTAssertEqual(state.wentLive, [scene.id], "a note no scene owns changes nothing")
        XCTAssertEqual(model.lastNote, Self.otherKey)
    }

    func testTheNextNoteBelongsToTheSceneWaitingForIt() {
        let scene = StudioButton(name: "Wide", scene: SceneConfiguration())
        state.studio.buttons = [scene]
        let model = makeModel()
        model.start()
        model.learningFor = scene.id
        listener.onNote?(Self.key)
        XCTAssertNil(model.learningFor)
        XCTAssertEqual(state.studio.buttons.first?.midiNote, Self.key)
        XCTAssertTrue(state.wentLive.isEmpty, "the note that is learnt does not also play the scene")
    }

    func testAModelThatHasGoneIsNotKeptByTheListener() {
        var model: MIDIModel? = makeModel()
        model?.start()
        weak var probe = model
        model = nil
        XCTAssertNil(probe)
        listener.onNote?(Self.key)
        XCTAssertTrue(state.wentLive.isEmpty)
    }
}
