import CamTwistCore
import XCTest
@testable import CamTwistControl

final class PictureGestureTests: XCTestCase {
    private let size = CGSize(width: 200, height: 100)

    func testViewPointsBecomeUnitPointsWithUpAsPositive() {
        XCTAssertEqual(PictureGestures.unitPoint(CGPoint(x: 100, y: 25), in: size), CGPoint(x: 0.5, y: 0.75))
        XCTAssertEqual(PictureGestures.unitPoint(.zero, in: size), CGPoint(x: 0, y: 1))
    }

    func testUnitPointsBecomeViewPointsAgain() {
        XCTAssertEqual(PictureGestures.viewPoint(CGPoint(x: 0.5, y: 0.75), in: size), CGPoint(x: 100, y: 25))
    }

    func testThePenIsFoundOnlyForATelestratorTarget() {
        let settings = TelestratorSettings(penWidth: 0.02)
        let item = ChainItem(content: .source(.telestrator(settings)))
        let other = ChainItem(content: .source(.colorBars))
        let scene = SceneConfiguration(items: [item, other])
        XCTAssertEqual(PictureGestures.pen(target: .telestrator(item.id), in: scene), settings)
        XCTAssertNil(PictureGestures.pen(target: .telestrator(other.id), in: scene))
        XCTAssertNil(PictureGestures.pen(target: .picture(item.id), in: scene))
        XCTAssertNil(PictureGestures.pen(target: nil, in: scene))
    }

    private func box(
        centerY: Double = 0.5, rotation: Double = 0, canTurn: Bool = true, canResize: Bool = true
    ) -> SelectionBoxLayout {
        // On a 200 by 100 canvas: 100 wide and 20 high, round (100, 50) by default.
        let outline = SelectionOutline(
            center: CGPoint(x: 0.5, y: centerY), size: CGSize(width: 0.5, height: 0.2), rotation: rotation,
            canTurn: canTurn, canResize: canResize
        )
        return SelectionBoxLayout(outline: outline, canvas: size)
    }

    func testTheSelectionBoxIsScaledToTheCanvas() {
        let layout = box(centerY: 0.75, canTurn: false)
        XCTAssertEqual(layout.size, CGSize(width: 100, height: 20))
        XCTAssertEqual(layout.center, CGPoint(x: 100, y: 25))
        XCTAssertEqual(layout.rotation, 0)
    }

    func testTheKnobTurnsACornerResizesAndTheMiddleMoves() {
        let layout = box()
        XCTAssertEqual(layout.knobOffset, -(10 + SelectionBoxLayout.stalkLength))
        XCTAssertEqual(layout.grip(at: CGPoint(x: 100, y: 18)), .turn)
        for corner in [CGPoint(x: 50, y: 40), CGPoint(x: 150, y: 40), CGPoint(x: 50, y: 60), CGPoint(x: 150, y: 60)] {
            XCTAssertEqual(layout.grip(at: corner), .resize)
        }
        XCTAssertEqual(layout.grip(at: CGPoint(x: 100, y: 50)), .move)
        XCTAssertNil(layout.grip(at: CGPoint(x: 100, y: 90)), "below the box")
        XCTAssertNil(layout.grip(at: CGPoint(x: 20, y: 50)), "beside the box")
    }

    func testABoxThatCannotTurnOrResizeOnlyMoves() {
        let fixed = box(canTurn: false, canResize: false)
        XCTAssertNil(fixed.grip(at: CGPoint(x: 100, y: 18)), "there is no knob to take")
        XCTAssertEqual(fixed.grip(at: CGPoint(x: 52, y: 42)), .move, "there is no corner to take")
    }

    func testATurnedBoxIsGrippedWhereItIsDrawn() {
        // A quarter turn clockwise puts the knob out to the right.
        let layout = box(rotation: 90)
        XCTAssertEqual(layout.grip(at: CGPoint(x: 132, y: 50)), .turn)
        XCTAssertNil(layout.grip(at: CGPoint(x: 60, y: 50)), "inside the box before the turn, beside it now")
        XCTAssertEqual(layout.grip(at: CGPoint(x: 100, y: 75)), .move, "the box now stands upright")
    }

    func testAKnobThatWouldLeaveThePictureSitsInsideTheBox() {
        // Round (100, 15): above the top edge is off the picture.
        let layout = box(centerY: 0.85)
        XCTAssertEqual(layout.knobOffset, -(10 - SelectionBoxLayout.stalkLength))
        XCTAssertEqual(layout.grip(at: CGPoint(x: 100, y: 27)), .turn)
    }

    func testADragWithNoBoxMovesAndOneOutsideTheBoxLetsGo() {
        XCTAssertEqual(PictureGestures.mode(at: .zero, box: nil), .move)
        XCTAssertEqual(PictureGestures.mode(at: CGPoint(x: 100, y: 50), box: box()), .move)
        XCTAssertNil(PictureGestures.mode(at: .zero, box: box()))
    }

    func testEscapeLetsGoAndDeleteRemoves() {
        func action(_ code: UInt16, selection: Bool = true, typing: Bool = false, sheet: Bool = false) -> PictureKey? {
            PictureKey.action(keyCode: code, hasSelection: selection, isTyping: typing, isSheetUp: sheet)
        }
        XCTAssertEqual(action(53), .deselect)
        XCTAssertEqual(action(51), .remove)
        XCTAssertEqual(action(117), .remove)
        XCTAssertNil(action(0), "any other key")
        XCTAssertNil(action(51, selection: false))
        XCTAssertNil(action(51, typing: true), "Delete in a field deletes text")
        XCTAssertNil(action(53, sheet: true), "Escape closes the sheet")
    }
}
