import XCTest
@testable import CamTwistCore

final class SolidShapeTests: XCTestCase {
    func testShapesAreFoundByNameAndACubeStandsInForAnythingElse() {
        XCTAssertEqual(SolidShape(named: "sphere"), .sphere)
        XCTAssertEqual(SolidShape(named: "PYRAMID"), .pyramid)
        XCTAssertEqual(SolidShape(named: "blob"), .cube)
        XCTAssertEqual(SolidShape.allCases.map(\.rawValue), ["Cube", "Box", "Sphere", "Cylinder", "Cone", "Pyramid"])
    }

    func testASolidTurnsSoManyTimesASecondAndStandsStillAtNone() {
        XCTAssertEqual(SolidSpin.angle(at: 2.5, turnsPerSecond: 0.1, startingAt: 0), 90)
        XCTAssertEqual(SolidSpin.angle(at: 10, turnsPerSecond: 0.1, startingAt: 30), 30, accuracy: 0.0001)
        XCTAssertEqual(SolidSpin.angle(at: 99, turnsPerSecond: 0, startingAt: 45), 45)
    }
}
