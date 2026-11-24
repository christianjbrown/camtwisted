import XCTest
@testable import CamTwistCore

final class ShapeTests: XCTestCase {
    func testDefaultsAreASolidRectangle() {
        let shape = ShapeSettings()
        XCTAssertEqual(shape.kind, .rectangle)
        XCTAssertEqual(shape.color, ShapeSettings.defaultColor)
        XCTAssertEqual(shape.opacity, ShapeSettings.opaque)
    }

    func testSquareShapesAreSquareAndTheRestTakeThePicturesShape() {
        for kind in [ShapeKind.square, .circle, .star, .diamond] {
            XCTAssertEqual(ShapeGeometry.aspect(of: kind, canvasAspect: 1.78), 1, "\(kind)")
        }
        for kind in [ShapeKind.rectangle, .ellipse, .triangle] {
            XCTAssertEqual(ShapeGeometry.aspect(of: kind, canvasAspect: 1.78), 1.78, "\(kind)")
        }
    }

    func testRoundShapesHaveNoCorners() {
        XCTAssertTrue(ShapeGeometry.isRound(.circle))
        XCTAssertTrue(ShapeGeometry.isRound(.ellipse))
        XCTAssertFalse(ShapeGeometry.isRound(.star))
        XCTAssertEqual(ShapeGeometry.corners(of: .circle), [])
        XCTAssertEqual(ShapeGeometry.corners(of: .ellipse), [])
    }

    func testStraightSidedShapesHaveTheirCorners() {
        XCTAssertEqual(ShapeGeometry.corners(of: .rectangle).count, 4)
        XCTAssertEqual(ShapeGeometry.corners(of: .square), ShapeGeometry.corners(of: .rectangle))
        XCTAssertEqual(ShapeGeometry.corners(of: .triangle).last, CGPoint(x: 0.5, y: 1), "the point is at the top")
        XCTAssertEqual(ShapeGeometry.corners(of: .diamond).first, CGPoint(x: 0.5, y: 0))

        let star = ShapeGeometry.corners(of: .star)
        XCTAssertEqual(star.count, 10)
        XCTAssertEqual(star[0].x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(star[0].y, 1, accuracy: 0.0001, "the first tip points up")
        let inner = star[1]
        XCTAssertEqual(hypot(inner.x - 0.5, inner.y - 0.5), 0.2, accuracy: 0.0001, "inner corners sit closer in")
        XCTAssertTrue(star.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }

    func testEveryKindHasAnOutlineThatAgreesWithTheGeometry() {
        for kind in ShapeKind.allCases {
            let outline = ShapeOutlines.outline(for: kind)
            XCTAssertEqual(outline.isRound, ShapeGeometry.isRound(kind), "\(kind)")
            XCTAssertEqual(outline.corners, ShapeGeometry.corners(of: kind), "\(kind)")
            XCTAssertEqual(outline.aspect(canvasAspect: 2), ShapeGeometry.aspect(of: kind, canvasAspect: 2), "\(kind)")
            XCTAssertEqual(outline.isRound, outline.corners.isEmpty, "\(kind)")
        }
    }
}
