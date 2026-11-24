import CamTwistCore
import CoreGraphics
import XCTest
@testable import CamTwistControl

/// A picture that keeps what a drag asks of it.
@MainActor
private final class FakePicture: PictureDragActing {
    var dragTarget: DragTarget?
    var box: SelectionBoxLayout?
    var drags: [(start: CGPoint, end: CGPoint, mode: DragMode)] = []
    var strokes: [(points: [CGPoint], id: UUID)] = []
    var deselections = 0

    func selectionBox(in size: CGSize) -> SelectionBoxLayout? { box }
    func drag(from start: CGPoint, to end: CGPoint, mode: DragMode) { drags.append((start, end, mode)) }
    func addStroke(_ points: [CGPoint], to id: UUID) { strokes.append((points, id)) }
    func deselect() { deselections += 1 }
}

@MainActor
final class PictureDragSessionTests: XCTestCase {
    private static let size = CGSize(width: 200, height: 100)
    private static let press = CGPoint(x: 100, y: 50)
    private static let outside = CGPoint(x: 5, y: 5)

    private let picture = FakePicture()
    private lazy var session = PictureDragSession(picture: picture)

    /// A box in the middle of the picture, a fifth of its width and height.
    private var middleBox: SelectionBoxLayout {
        SelectionBoxLayout(
            outline: SelectionOutline(
                center: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 0.2, height: 0.2), rotation: 0,
                canTurn: true, canResize: true
            ),
            canvas: Self.size
        )
    }

    func testADragWithNoBoxMovesTheStepBetweenEachPointAndTheNext() {
        picture.dragTarget = .picture(UUID())
        session.changed(to: Self.press, start: Self.press, in: Self.size)
        XCTAssertTrue(picture.drags.isEmpty, "the press only decides what the drag does")
        session.changed(to: CGPoint(x: 120, y: 50), start: Self.press, in: Self.size)
        session.changed(to: CGPoint(x: 120, y: 25), start: Self.press, in: Self.size)
        XCTAssertEqual(picture.drags.map(\.mode), [.move, .move])
        XCTAssertEqual(picture.drags[0].start, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(picture.drags[0].end, CGPoint(x: 0.6, y: 0.5))
        XCTAssertEqual(picture.drags[1].start, CGPoint(x: 0.6, y: 0.5))
        XCTAssertEqual(picture.drags[1].end, CGPoint(x: 0.6, y: 0.75), "up the view is up the picture")
        XCTAssertEqual(picture.deselections, 0)
    }

    func testThePressDecidesTheWholeDrag() {
        picture.dragTarget = .picture(UUID())
        picture.box = middleBox
        let corner = CGPoint(x: 120, y: 60)
        session.changed(to: corner, start: corner, in: Self.size)
        // The pointer wanders into the middle, and the drag still resizes.
        session.changed(to: Self.press, start: corner, in: Self.size)
        XCTAssertEqual(picture.drags.map(\.mode), [.resize])
        session.ended(in: Self.size)

        session.changed(to: Self.press, start: Self.press, in: Self.size)
        session.changed(to: corner, start: Self.press, in: Self.size)
        XCTAssertEqual(picture.drags.map(\.mode), [.resize, .move], "a new drag is decided afresh")
    }

    func testAPressOutsideTheBoxLetsGoOfTheStepAndDragsNothing() {
        picture.dragTarget = .picture(UUID())
        picture.box = middleBox
        session.changed(to: Self.outside, start: Self.outside, in: Self.size)
        XCTAssertEqual(picture.deselections, 1)
        session.changed(to: Self.press, start: Self.outside, in: Self.size)
        XCTAssertTrue(picture.drags.isEmpty)
        XCTAssertEqual(picture.deselections, 1)
        session.ended(in: Self.size)
        XCTAssertTrue(picture.strokes.isEmpty)
    }

    func testADragOnATelestratorDrawsAStrokeThatJoinsThePictureWhenTheMouseComesUp() {
        let pen = UUID()
        picture.dragTarget = .telestrator(pen)
        session.ended(in: Self.size)
        XCTAssertTrue(picture.strokes.isEmpty, "nothing was drawn")

        session.changed(to: Self.press, start: Self.press, in: Self.size)
        session.changed(to: CGPoint(x: 200, y: 0), start: Self.press, in: Self.size)
        XCTAssertEqual(session.stroke, [Self.press, CGPoint(x: 200, y: 0)], "shown in the view's own points")
        XCTAssertTrue(picture.drags.isEmpty)
        session.ended(in: Self.size)
        XCTAssertEqual(picture.strokes.count, 1)
        XCTAssertEqual(picture.strokes[0].id, pen)
        XCTAssertEqual(picture.strokes[0].points, [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1)])
        XCTAssertTrue(session.stroke.isEmpty)
    }
}
