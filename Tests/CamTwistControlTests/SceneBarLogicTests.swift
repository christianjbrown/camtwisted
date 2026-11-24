import CamTwistCore
import XCTest
@testable import CamTwistControl

final class SceneBarLogicTests: XCTestCase {
    private let id = UUID()
    private let other = UUID()

    private func state(
        onAir: UUID? = nil, editingOnAir: Bool = false, folded: Bool = false, edited: UUID? = nil, peeked: UUID? = nil
    ) -> SceneBarState {
        SceneBarState(
            sceneID: id, onAirID: onAir, isEditingOnAir: editingOnAir, isOnAirFolded: folded, editedSceneID: edited,
            peekedID: peeked
        )
    }

    private func scene(locked: Bool = false, items: [ChainItem] = []) -> StudioButton {
        var button = StudioButton(name: "Main", scene: SceneConfiguration(items: items))
        button.isLocked = locked
        return button
    }

    func testTheSceneOnAirIsOpenOnlyWhileBeingEditedAndNotFolded() {
        XCTAssertTrue(state(onAir: id, editingOnAir: true).isOpen)
        XCTAssertFalse(state(onAir: id, editingOnAir: true, folded: true).isOpen)
        XCTAssertFalse(state(onAir: id, editingOnAir: false).isOpen)
        XCTAssertTrue(state(onAir: id).isOnAir)
    }

    func testOtherScenesAreOpenWhenEditedAndPeekedOnlyWhileFolded() {
        XCTAssertTrue(state(onAir: other, edited: id).isOpen)
        XCTAssertFalse(state(onAir: other, edited: other).isOpen)
        XCTAssertTrue(state(onAir: other, peeked: id).isPeeked)
        XCTAssertFalse(state(onAir: other, edited: id, peeked: id).isPeeked)
        XCTAssertFalse(state(onAir: id, peeked: id).isPeeked)
    }

    func testAFoldedSceneOffersPeekingGoLiveAndASummary() {
        let items = [ChainItem(content: .source(.colorBars)), ChainItem(content: .effect(name: "Ring", values: [:]))]
        let content = SceneBarContent(scene: scene(items: items), state: state(onAir: other), isTransitioning: false)
        XCTAssertEqual(content.foldHelp, "Open to change it")
        XCTAssertTrue(content.showsPeek)
        XCTAssertEqual(content.peekHelp, "Look at it live without opening it")
        XCTAssertTrue(content.showsGoLive)
        XCTAssertEqual(content.goLiveTitle, "Go live")
        XCTAssertTrue(content.showsSummary)
        XCTAssertEqual(content.summary, "Colour bars")
        XCTAssertEqual(content.lockHelp, "Lock, so nothing in it can be changed")
        XCTAssertEqual(content.removalHelp, "Remove")
        XCTAssertTrue(content.canRemove)
    }

    func testAPeekedSceneOffersToStopLooking() {
        let content = SceneBarContent(scene: scene(), state: state(onAir: other, peeked: id), isTransitioning: true)
        XCTAssertEqual(content.peekHelp, "Stop looking")
        XCTAssertEqual(content.goLiveTitle, "Switching")
    }

    func testTheSceneOnAirCannotBeRemovedOrSentLive() {
        let content = SceneBarContent(scene: scene(), state: state(onAir: id, editingOnAir: true), isTransitioning: false)
        XCTAssertEqual(content.foldHelp, "Fold away")
        XCTAssertFalse(content.showsPeek)
        XCTAssertFalse(content.showsGoLive)
        XCTAssertFalse(content.showsSummary)
        XCTAssertFalse(content.canRemove)
        XCTAssertEqual(content.removalHelp, "The scene on air cannot be removed")
    }

    func testALockedSceneCannotBeRemoved() {
        let content = SceneBarContent(scene: scene(locked: true), state: state(onAir: other), isTransitioning: false)
        XCTAssertEqual(content.lockHelp, "Unlock, so it can be changed or removed")
        XCTAssertEqual(content.removalHelp, "Unlock it first to remove it")
        XCTAssertFalse(content.canRemove)
    }

    func testPressingTheChevronOnTheSceneOnAirFoldsItOrOpensItAndClosesTheOthers() {
        let editing = SceneFolding(isOnAir: true, isOpen: true, isEditingOnAir: true, isOnAirFolded: false, isEmpty: true)
        XCTAssertTrue(editing.isOnAirFolded)
        XCTAssertEqual(editing.edit, .leaveAlone)
        XCTAssertFalse(editing.opensSourcePicker)
        let elsewhere = SceneFolding(isOnAir: true, isOpen: false, isEditingOnAir: false, isOnAirFolded: true, isEmpty: false)
        XCTAssertFalse(elsewhere.isOnAirFolded)
        XCTAssertEqual(elsewhere.edit, .closeAll)
    }

    func testPressingTheChevronOnAnotherSceneOpensOrClosesIt() {
        let closing = SceneFolding(isOnAir: false, isOpen: true, isEditingOnAir: false, isOnAirFolded: false, isEmpty: false)
        XCTAssertTrue(closing.isOnAirFolded)
        XCTAssertEqual(closing.edit, .closeAll)
        let opening = SceneFolding(isOnAir: false, isOpen: false, isEditingOnAir: true, isOnAirFolded: false, isEmpty: true)
        XCTAssertFalse(opening.isOnAirFolded)
        XCTAssertEqual(opening.edit, .open)
        XCTAssertTrue(opening.opensSourcePicker)
        let filled = SceneFolding(isOnAir: false, isOpen: false, isEditingOnAir: false, isOnAirFolded: true, isEmpty: false)
        XCTAssertFalse(filled.opensSourcePicker)
    }

    func testTheStartingPickerFollowsTheLaunchOptionsAndTheCamera() {
        func choose(_ afresh: Bool, _ picker: Bool, _ effects: Bool, _ onAir: Bool, _ camera: Bool) -> StartingPicker {
            StartingPicker.choose(startsAfresh: afresh, opensPicker: picker, showsEffects: effects, isOnAir: onAir, hasCamera: camera)
        }
        XCTAssertEqual(choose(false, false, false, true, true), .none)
        XCTAssertEqual(choose(true, false, false, false, true), .none)
        XCTAssertEqual(choose(true, false, false, true, true), .effects)
        XCTAssertEqual(choose(true, false, false, true, false), .sources)
        XCTAssertEqual(choose(true, true, false, true, true), .sources)
        XCTAssertEqual(choose(false, true, false, true, false), .sources)
        XCTAssertEqual(choose(false, false, true, true, false), .effects)
    }

    func testTheMIDIRowShowsTheKeyAndTheLearningButton() {
        let none = MIDIKeyRow(note: nil, isLearning: false)
        XCTAssertEqual(none.title, "No MIDI key")
        XCTAssertEqual(none.buttonTitle, "Record MIDI key")
        XCTAssertFalse(none.showsClear)
        let learning = MIDIKeyRow(note: 60, isLearning: true)
        XCTAssertEqual(learning.title, "MIDI key: 60")
        XCTAssertEqual(learning.buttonTitle, "Play a key")
        XCTAssertTrue(learning.showsClear)
        XCTAssertEqual(MIDIKeyRow.learning(after: id, current: nil), id)
        XCTAssertNil(MIDIKeyRow.learning(after: id, current: id))
        XCTAssertEqual(MIDIKeyRow.learning(after: id, current: other), id)
    }

    func testTransitionPanelsFallBackToASymbol() {
        XCTAssertEqual(TransitionPanel.fallbackSymbol(for: StudioSettings.cutName), "scissors")
        XCTAssertEqual(TransitionPanel.fallbackSymbol(for: "Dissolve"), "rectangle.2.swap")
        XCTAssertEqual(TransitionPanel.scenesOwnSymbol, "rectangle.stack")
    }
}

final class SceneKeyRowTests: XCTestCase {
    private static let seconds = 12.0
    private static let shortcut = SceneShortcut(keyCode: 18, key: "1", modifiers: [.control, .option])

    func testTheShortcutRowSaysWhatTheShortcutIs() {
        let none = ShortcutKeyRow(shortcut: nil, isLearning: false)
        XCTAssertEqual(none.title, "No keyboard shortcut")
        XCTAssertEqual(none.buttonTitle, "Record shortcut")
        XCTAssertFalse(none.showsClear)
        let learning = ShortcutKeyRow(shortcut: Self.shortcut, isLearning: true)
        XCTAssertEqual(learning.title, "Keyboard shortcut: ⌃⌥1")
        XCTAssertEqual(learning.buttonTitle, "Press keys")
        XCTAssertTrue(learning.showsClear)
        XCTAssertFalse(ShortcutKeyRow.learningHelp.isEmpty)
    }

    func testPressingTheButtonAgainStopsTheWait() {
        let id = UUID()
        XCTAssertEqual(KeyLearning.learning(after: id, current: nil), id)
        XCTAssertNil(KeyLearning.learning(after: id, current: id))
    }

    func testASceneCanHandOverToAnyOtherSceneButItself() {
        let other = StudioButton(name: "Show", scene: SceneConfiguration())
        var scene = StudioButton(name: "Sponsor", scene: SceneConfiguration())
        XCTAssertEqual(HandoverChoices(for: scene, among: [scene, other]), HandoverChoices(for: scene, among: [other]))
        XCTAssertEqual(HandoverChoices(for: scene, among: [scene, other]).scenes, [other])
        XCTAssertNil(HandoverChoices(for: scene, among: [scene, other]).chosen)
        scene.handover = SceneHandover(sceneID: other.id)
        XCTAssertEqual(HandoverChoices(for: scene, among: [scene, other]).chosen, other.id)
        XCTAssertNil(HandoverChoices(for: scene, among: [scene]).chosen, "a scene that has gone is not chosen")
    }

    func testPickingASceneKeepsTheTimeAlreadySet() {
        let id = UUID()
        let other = UUID()
        XCTAssertNil(HandoverChoices.picking(nil, current: SceneHandover(sceneID: id)))
        XCTAssertEqual(HandoverChoices.picking(id, current: nil), SceneHandover(sceneID: id))
        XCTAssertEqual(
            HandoverChoices.picking(other, current: SceneHandover(sceneID: id, seconds: Self.seconds)),
            SceneHandover(sceneID: other, seconds: Self.seconds)
        )
    }
}
