import CamTwistCore
import CoreGraphics
import XCTest
@testable import CamTwistControl

@MainActor
final class PictureModelTests: XCTestCase {
    private static let middle = CGPoint(x: 0.5, y: 0.5)
    private static let pictureSize = CGSize(width: 400, height: 400)

    private let state = FakeState()
    private let sizes = FakePictureSizes()

    private func makeModel() -> PictureModel {
        PictureModel(
            state: state, dragging: PictureDragging(parameters: EffectParameters(library: FakeEffectLibrary())),
            pictureSizes: sizes, overlayMeasurer: FakeOverlayMeasurer()
        )
    }

    func testDeleteRemovesTheSelectedStepUnlessTheSceneIsLocked() {
        let card = sourceItem(.testCard)
        state.scene = SceneConfiguration(items: [card])
        let model = makeModel()
        model.removeSelectedStep()
        XCTAssertNotNil(state.scene.item(id: card.id), "nothing is selected")
        state.selectedStepID = card.id
        state.isEditedSceneLocked = true
        model.removeSelectedStep()
        XCTAssertNotNil(state.scene.item(id: card.id), "a locked scene keeps its steps")
        XCTAssertEqual(state.selectedStepID, card.id)
        state.isEditedSceneLocked = false
        model.removeSelectedStep()
        XCTAssertNil(state.scene.item(id: card.id))
        XCTAssertNil(state.selectedStepID)
    }

    func testDraggingMovesAndResizesTheSelectedStep() {
        let small = sourceItem(.testCard, pip: PictureInPictureSettings(center: Self.middle))
        state.scene = SceneConfiguration(items: [small])
        let model = makeModel()
        XCTAssertNil(model.dragTarget, "nothing is selected")
        XCTAssertNil(model.dragHint)
        state.selectedStepID = small.id
        XCTAssertEqual(model.dragTarget, .picture(small.id))
        XCTAssertNotNil(model.dragHint)
        model.drag(by: CGPoint(x: 0.1, y: 0))
        XCTAssertNotEqual(state.scene.item(id: small.id)?.pictureInPicture?.center, Self.middle)

        XCTAssertNil(model.selectionOutline, "the source has no picture yet")
        sizes.sizes[small.id] = Self.pictureSize
        XCTAssertNotNil(model.selectionOutline)
        let before = state.scene.item(id: small.id)?.pictureInPicture?.scale
        model.drag(from: CGPoint(x: 0.7, y: 0.5), to: CGPoint(x: 0.8, y: 0.5), mode: .resize)
        XCTAssertNotEqual(state.scene.item(id: small.id)?.pictureInPicture?.scale, before)
    }

    func testDrawingGoesToTheTelestratorInTheScene() {
        let pen = sourceItem(.telestrator(TelestratorSettings()))
        state.scene = SceneConfiguration(items: [pen])
        let model = makeModel()
        XCTAssertEqual(model.activeTelestrator, pen.id)
        let before = state.scene
        model.addStroke([CGPoint.zero, Self.middle], to: pen.id)
        XCTAssertNotEqual(state.scene, before)
    }

    func testTheBoxRoundTheSelectedStepIsLaidOutOnThePictureAsShown() {
        let small = sourceItem(.testCard, pip: PictureInPictureSettings(center: Self.middle))
        state.scene = SceneConfiguration(items: [small])
        state.selectedStepID = small.id
        let model = makeModel()
        XCTAssertNil(model.selectionBox(in: Self.pictureSize), "the source has no picture yet")
        sizes.sizes[small.id] = Self.pictureSize
        XCTAssertEqual(model.selectionBox(in: Self.pictureSize)?.center, CGPoint(x: 200, y: 200))
    }

    func testThePenIsThatOfTheTelestratorADragWouldDrawWith() {
        let settings = TelestratorSettings(penWidth: 0.02)
        let pen = sourceItem(.telestrator(settings))
        let card = sourceItem(.testCard, pip: PictureInPictureSettings(center: Self.middle))
        state.scene = SceneConfiguration(items: [card])
        let model = makeModel()
        XCTAssertNil(model.pen, "there is no telestrator")
        state.scene = SceneConfiguration(items: [card, pen])
        XCTAssertEqual(model.pen, settings)
    }

    func testEscapeLetsGoOfTheSelectedStepAndDeleteRemovesIt() {
        let escape: UInt16 = 53
        let delete: UInt16 = 51
        let letterA: UInt16 = 0
        let card = sourceItem(.testCard)
        state.scene = SceneConfiguration(items: [card])
        let model = makeModel()
        XCTAssertFalse(model.keyPressed(escape, isTyping: false, isSheetUp: false), "nothing is selected")
        state.selectedStepID = card.id
        XCTAssertFalse(model.keyPressed(letterA, isTyping: false, isSheetUp: false), "not one of the picture's keys")
        XCTAssertFalse(model.keyPressed(delete, isTyping: true, isSheetUp: false), "the key is being typed")
        XCTAssertFalse(model.keyPressed(delete, isTyping: false, isSheetUp: true), "a sheet has the keys")
        XCTAssertTrue(model.keyPressed(escape, isTyping: false, isSheetUp: false))
        XCTAssertNil(state.selectedStepID)
        XCTAssertNotNil(state.scene.item(id: card.id))
        state.selectedStepID = card.id
        XCTAssertTrue(model.keyPressed(delete, isTyping: false, isSheetUp: false))
        XCTAssertNil(state.scene.item(id: card.id))
    }
}
