import CamTwistCore
import XCTest
@testable import CamTwistControl

/// Takes the keys it is told to, and remembers every key it was offered.
@MainActor
private final class FakeKeys: KeyPressHandling {
    let takes: Bool
    var offered: [KeyPress] = []
    init(takes: Bool) { self.takes = takes }
    func handle(_ press: KeyPress) -> Bool {
        offered.append(press)
        return takes
    }
}

@MainActor
final class KeyPressTests: XCTestCase {
    private static let deleteKey: UInt16 = 51
    private let press = KeyPress(
        keyCode: KeyPressTests.deleteKey, characters: "", modifiers: [], isTyping: false, isSheetUp: false
    )

    func testEachKeyGoesToTheFirstThatTakesIt() {
        let passes = FakeKeys(takes: false)
        let takes = FakeKeys(takes: true)
        let never = FakeKeys(takes: true)
        XCTAssertTrue(KeyPressChain(handlers: [passes, takes, never]).handle(press))
        XCTAssertEqual(passes.offered, [press])
        XCTAssertEqual(takes.offered, [press])
        XCTAssertTrue(never.offered.isEmpty)
        XCTAssertFalse(KeyPressChain(handlers: [passes]).handle(press))
    }

    func testASceneWaitingForItsShortcutKeepsDeleteFromThePicture() {
        let harness = Harness()
        let model = harness.makeModel()
        model.start()
        let card = sourceItem(.testCard)
        model.scene = SceneConfiguration(items: [card])
        model.selectedStepID = card.id
        let waiting = model.studio.buttons[0].id
        model.shortcuts.learningFor = waiting
        XCTAssertTrue(model.keys.handle(press))
        XCTAssertNotNil(model.scene.item(id: card.id), "the step is still there")
        model.shortcuts.learningFor = nil
        XCTAssertTrue(model.keys.handle(press))
        XCTAssertNil(model.scene.item(id: card.id), "with nobody waiting, Delete removes the selected step")
    }
}

@MainActor
final class SceneKeysWiringTests: XCTestCase {
    private static let seconds = 20.0
    private static let shortcut = SceneShortcut(keyCode: 18, key: "1", modifiers: [.command])

    func testAShortcutPressedInAnyAppPutsItsSceneOnAir() {
        let harness = Harness()
        let model = harness.makeModel()
        model.start()
        model.addScene()
        let added = model.studio.buttons[1].id
        model.studio.assign(Self.shortcut, to: added)
        XCTAssertEqual(harness.shortcuts.listenedFor.last, [Self.shortcut])
        harness.shortcuts.onPress?(Self.shortcut)
        XCTAssertEqual(model.studio.onAirID, added)
    }

    func testTheSceneOnAirHandsOverWhenItsTimeIsUp() {
        let harness = Harness()
        let model = harness.makeModel()
        model.start()
        let first = model.studio.buttons[0].id
        model.addScene()
        let second = model.studio.buttons[1].id
        model.studio.buttons[0].handover = SceneHandover(sceneID: second, seconds: Self.seconds)
        XCTAssertEqual(harness.timers.scheduled.map(\.seconds), [Self.seconds])
        harness.timers.fire(0)
        XCTAssertEqual(model.studio.onAirID, second)
        model.goLive(withScene: first)
        XCTAssertEqual(harness.timers.scheduled.count, 2, "coming back on air starts the countdown again")
    }
}
