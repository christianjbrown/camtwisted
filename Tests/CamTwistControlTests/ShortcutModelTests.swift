import CamTwistCore
import XCTest
@testable import CamTwistControl

@MainActor
final class ShortcutModelTests: XCTestCase {
    // Where these keys are on a Mac keyboard.
    private static let oneKey: UInt16 = 18
    private static let escapeKey: UInt16 = 53
    private static let deleteKey: UInt16 = 51

    private static let shortcut = SceneShortcut(keyCode: Int(oneKey), key: "1", modifiers: [.control, .option])
    private static let other = SceneShortcut(keyCode: Int(oneKey), key: "1", modifiers: [.command])

    private let state = FakeState()
    private let listener = FakeShortcuts()

    private func makeModel() -> ShortcutModel {
        ShortcutModel(state: state, listener: listener, recorder: ShortcutRecorder())
    }

    private func press(_ keyCode: UInt16, _ characters: String, _ modifiers: ShortcutModifiers = []) -> KeyPress {
        KeyPress(keyCode: keyCode, characters: characters, modifiers: modifiers, isTyping: false, isSheetUp: false)
    }

    func testStartingListensForTheShortcutsTheScenesHave() {
        var scene = StudioButton(name: "Wide", scene: SceneConfiguration())
        scene.shortcut = Self.shortcut
        state.studio.buttons = [scene, StudioButton(name: "Close", scene: SceneConfiguration())]
        let model = makeModel()
        XCTAssertNil(listener.onPress)
        model.start()
        XCTAssertNotNil(listener.onPress)
        XCTAssertEqual(listener.listenedFor, [[Self.shortcut]])
    }

    func testTheListenerIsOnlyToldWhenTheShortcutsChange() {
        let model = makeModel()
        model.follow(state.studio)
        model.follow(state.studio)
        XCTAssertEqual(listener.listenedFor, [[]])
        var scene = StudioButton(name: "Wide", scene: SceneConfiguration())
        scene.shortcut = Self.shortcut
        state.studio.buttons = [scene]
        model.follow(state.studio)
        XCTAssertEqual(listener.listenedFor, [[], [Self.shortcut]])
    }

    func testAShortcutPutsItsSceneOnAir() {
        var scene = StudioButton(name: "Wide", scene: SceneConfiguration())
        scene.shortcut = Self.shortcut
        state.studio.buttons = [scene]
        let model = makeModel()
        model.start()
        listener.onPress?(Self.shortcut)
        XCTAssertEqual(state.wentLive, [scene.id])
        listener.onPress?(Self.other)
        XCTAssertEqual(state.wentLive, [scene.id], "a shortcut no scene owns changes nothing")
        XCTAssertNil(model.learningFor)
    }

    func testAShortcutPressedWhileASceneWaitsBecomesItsOwn() {
        var owner = StudioButton(name: "Wide", scene: SceneConfiguration())
        owner.shortcut = Self.shortcut
        let waiting = StudioButton(name: "Close", scene: SceneConfiguration())
        state.studio.buttons = [owner, waiting]
        let model = makeModel()
        model.start()
        model.learningFor = waiting.id
        listener.onPress?(Self.shortcut)
        XCTAssertNil(model.learningFor)
        XCTAssertEqual(state.studio.buttons.map(\.shortcut), [nil, Self.shortcut], "it moves from the other scene")
        XCTAssertTrue(state.wentLive.isEmpty, "the shortcut that is learnt does not also play a scene")
    }

    func testWhileASceneWaitsEveryKeyGoesToIt() {
        let scene = StudioButton(name: "Wide", scene: SceneConfiguration())
        state.studio.buttons = [scene]
        let model = makeModel()
        XCTAssertFalse(model.handle(press(Self.deleteKey, "")), "nobody is waiting, so the key is somebody else's")
        model.learningFor = scene.id
        XCTAssertTrue(model.handle(press(Self.deleteKey, "")), "not a shortcut, but it is kept from the picture")
        XCTAssertEqual(model.learningFor, scene.id, "it keeps waiting")
        XCTAssertTrue(model.handle(press(Self.escapeKey, "")))
        XCTAssertNil(model.learningFor, "Escape stops it waiting")
        XCTAssertNil(state.studio.buttons.first?.shortcut)
        model.learningFor = scene.id
        XCTAssertTrue(model.handle(press(Self.oneKey, "1", [.control, .option])))
        XCTAssertNil(model.learningFor)
        XCTAssertEqual(state.studio.buttons.first?.shortcut, Self.shortcut)
    }

    func testAModelThatHasGoneIsNotKeptByTheListener() {
        var model: ShortcutModel? = makeModel()
        model?.start()
        weak var gone = model
        model = nil
        XCTAssertNil(gone)
        listener.onPress?(Self.shortcut)
        XCTAssertTrue(state.wentLive.isEmpty)
    }
}
