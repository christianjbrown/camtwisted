import CamTwistCore
import CamTwistRendering
import XCTest
@testable import CamTwistControl

@MainActor
final class SceneBookTests: XCTestCase {
    private let state = FakeState()
    private let renderer = FakeRenderer()
    private lazy var book = SceneBook(state: state, transitions: TransitionRunner(state: state, renderer: renderer))
    private let bars = SceneConfiguration(items: [sourceItem(.colorBars)])
    private let card = SceneConfiguration(items: [sourceItem(.testCard)])
    private lazy var wide = StudioButton(name: "Wide", scene: bars)
    private lazy var close = StudioButton(name: "Close", scene: card)

    override func setUp() async throws {
        state.scene = bars
        state.studio = StudioSettings(buttons: [wide, close], onAirID: wide.id)
    }

    func testGoingLiveWithACutSwitchesAtOnce() {
        book.goLive(with: close.id)
        XCTAssertEqual(state.scene, card)
        XCTAssertEqual(state.studio.onAirID, close.id)
        XCTAssertTrue(renderer.transitions.isEmpty)
    }

    func testGoingLiveWithATransitionArrivesWhenItLands() {
        state.studio.buttons[1].switchName = "Wipe"
        state.studio.buttons[1].switchTime = 2.5
        book.goLive(with: close.id)
        XCTAssertTrue(state.isTransitioning)
        XCTAssertEqual(renderer.transitions.first?.scene, card)
        XCTAssertEqual(renderer.transitions.first?.name, "Wipe")
        XCTAssertEqual(renderer.transitions.first?.duration, 2.5)
        XCTAssertEqual(state.studio.onAirID, wide.id)
        book.landed(on: card)
        XCTAssertEqual(state.studio.onAirID, close.id)
        XCTAssertEqual(state.scene, card)
        XCTAssertFalse(state.isTransitioning)
    }

    func testAFadeToASceneSinceRemovedLandsOnWhicheverShowsThePicture() {
        state.studio.buttons[1].switchName = "Wipe"
        book.goLive(with: close.id)
        let twin = StudioButton(name: "Twin", scene: card)
        state.studio.buttons = [wide, twin]
        book.landed(on: card)
        XCTAssertEqual(state.studio.onAirID, twin.id)
        // And a fade nobody here started is matched by its picture too.
        book.landed(on: bars)
        XCTAssertEqual(state.studio.onAirID, wide.id)
    }

    func testGoingLiveIsIgnoredForAnUnknownSceneTheOneOnAirOrMidFade() {
        book.goLive(with: UUID())
        book.goLive(with: wide.id)
        state.isTransitioning = true
        book.goLive(with: close.id)
        XCTAssertTrue(renderer.transitions.isEmpty)
        XCTAssertEqual(state.scene, bars)
        XCTAssertEqual(state.studio.onAirID, wide.id)
    }

    func testTheSceneBeingChangedIsTheOneOnAirUnlessAnotherIsOpened() {
        XCTAssertTrue(book.isEditingOnAir)
        XCTAssertEqual(book.edited, bars)
        book.edited = card
        XCTAssertEqual(state.scene, card, "changes to the scene on air go on air")

        book.edit(close.id)
        XCTAssertFalse(book.isEditingOnAir)
        XCTAssertEqual(state.studioPreview, card)
        let changed = SceneConfiguration(items: [sourceItem(.testCard), sourceItem(.colorBars)])
        book.edited = changed
        XCTAssertEqual(state.studio.buttons[1].scene, changed)
        XCTAssertEqual(state.studioPreview, changed)
        XCTAssertEqual(state.scene, card, "what is on air is untouched")
        XCTAssertEqual(book.edited, changed)

        // Opening the one on air, an unknown one or none goes back to the one on air.
        book.edit(wide.id)
        XCTAssertNil(state.editedSceneID)
        XCTAssertNil(state.studioPreview)
        book.edit(UUID())
        XCTAssertTrue(book.isEditingOnAir)
        // A scene that vanished while open leaves the one on air being changed.
        state.editedSceneID = UUID()
        XCTAssertTrue(book.isEditingOnAir)
    }

    func testGoingLiveWithTheSceneBeingChangedStopsPreviewingIt() {
        book.edit(close.id)
        book.goLive(with: close.id)
        XCTAssertNil(state.editedSceneID)
        XCTAssertNil(state.studioPreview)
        XCTAssertEqual(state.studio.onAirID, close.id)
    }

    func testScenesAreAddedCopiedAndRemoved() {
        let added = book.add(card)
        XCTAssertEqual(state.studio.buttons.map(\.name), ["Wide", "Close", "Scene 3"])
        XCTAssertEqual(state.editedSceneID, added)
        book.duplicate(id: close.id)
        XCTAssertEqual(state.studio.buttons.map(\.name), ["Wide", "Close", "Close copy", "Scene 3"])
        XCTAssertEqual(state.editedSceneID, state.studio.buttons[2].id)
        book.duplicate(id: UUID())
        XCTAssertEqual(state.studio.buttons.count, 4)

        book.remove(id: added)
        XCTAssertEqual(state.editedSceneID, state.studio.buttons[2].id, "removing another leaves the open one open")
        book.remove(id: state.studio.buttons[2].id)
        XCTAssertNil(state.editedSceneID)
        book.remove(id: wide.id)
        XCTAssertEqual(state.studio.buttons.map(\.name), ["Wide", "Close"], "the scene on air stays")
    }
}
