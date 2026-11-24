import XCTest
@testable import CamTwistCore

final class SceneShortcutTests: XCTestCase {
    private static let shortcut = SceneShortcut(keyCode: 18, key: "1", modifiers: [.command, .control])
    private static let other = SceneShortcut(keyCode: 19, key: "2", modifiers: [.option])

    func testShortcutsAreWrittenAsAMacMenuWritesThem() {
        XCTAssertEqual(ShortcutModifiers([.command, .shift, .option, .control]).title, "⌃⌥⇧⌘")
        XCTAssertEqual(ShortcutModifiers().title, "")
        XCTAssertEqual(Self.shortcut.title, "⌃⌘1")
        XCTAssertEqual(ShortcutModifiers.commanding, [.control, .option, .command])
    }

    func testAShortcutBelongsToOneSceneAtATime() {
        let first = StudioButton(name: "Wide", scene: SceneConfiguration())
        let second = StudioButton(name: "Close", scene: SceneConfiguration())
        var studio = StudioSettings(buttons: [first, second])
        studio.assign(Self.shortcut, to: first.id)
        studio.assign(Self.other, to: UUID())
        XCTAssertEqual(studio.shortcuts, [Self.shortcut], "a scene that is not there gets nothing")
        XCTAssertEqual(studio.button(forShortcut: Self.shortcut)?.id, first.id)
        studio.assign(Self.shortcut, to: second.id)
        XCTAssertEqual(studio.buttons.map(\.shortcut), [nil, Self.shortcut])
        XCTAssertNil(studio.button(forShortcut: Self.other))
    }

    func testACopyKeepsItsHandoverButNotItsShortcut() {
        var scene = StudioButton(name: "Wide", scene: SceneConfiguration())
        scene.shortcut = Self.shortcut
        scene.handover = SceneHandover(sceneID: UUID())
        let copy = scene.duplicated()
        XCTAssertNil(copy.shortcut)
        XCTAssertEqual(copy.handover, scene.handover)
    }

    func testRemovingASceneStopsOthersHandingOverToIt() {
        let gone = StudioButton(name: "Gone", scene: SceneConfiguration())
        var handing = StudioButton(name: "Wide", scene: SceneConfiguration())
        handing.handover = SceneHandover(sceneID: gone.id)
        var studio = StudioSettings(buttons: [handing, gone], onAirID: handing.id)
        studio.removeScene(id: gone.id)
        XCTAssertEqual(studio.buttons.map(\.id), [handing.id])
        XCTAssertNil(studio.buttons[0].handover)
    }

    func testScenesSavedBeforeShortcutsStillLoad() throws {
        let scene = StudioButton(name: "Wide", scene: SceneConfiguration())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(scene)) as? [String: Any])
        json.removeValue(forKey: "shortcut")
        json.removeValue(forKey: "handover")
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try JSONDecoder().decode(StudioButton.self, from: old), scene)
    }

    func testAHandoverStartsWithTheUsualTime() {
        let id = UUID()
        XCTAssertEqual(SceneHandover(sceneID: id).seconds, SceneHandover.defaultSeconds)
        XCTAssertTrue(SceneHandover.secondsRange.contains(SceneHandover.defaultSeconds))
    }
}
