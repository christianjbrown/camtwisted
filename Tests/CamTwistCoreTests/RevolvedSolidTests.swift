import XCTest
@testable import CamTwistCore

final class RevolvedSolidTests: XCTestCase {
    private let accuracy: Float = 1e-5

    func testARoundedCylinderRunsFromTheBottomOfTheAxisToTheTop() {
        let profile = RevolvedSolid.roundedCylinder(radius: 1, height: 4, rim: 0.5, steps: 2)
        XCTAssertEqual(profile.count, 8)
        XCTAssertEqual(profile.first, SIMD2(0, -2))
        XCTAssertEqual(profile.last, SIMD2(0, 2))
        XCTAssertEqual(profile[1].x, 0.5, accuracy: accuracy, "the bottom edge starts flat")
        XCTAssertEqual(profile[1].y, -2, accuracy: accuracy)
        XCTAssertEqual(profile[3].x, 1, accuracy: accuracy, "and comes round to the side")
        XCTAssertEqual(profile[3].y, -1.5, accuracy: accuracy)
        XCTAssertEqual(profile[4].y, 1.5, accuracy: accuracy, "the side runs straight up to the top edge")
        XCTAssertEqual(profile[6].x, 0.5, accuracy: accuracy)
        XCTAssertEqual(profile[6].y, 2, accuracy: accuracy)
    }

    func testAnOutlineIsSweptRoundIntoRingsOfCorners() {
        // A cone standing on a flat base: axis, rim, tip.
        let mesh = RevolvedSolid.mesh(profile: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 2)], segments: 4)
        XCTAssertEqual(mesh.positions.count, 15, "three rings of five, the seam made twice")
        XCTAssertEqual(mesh.normals.count, 15)
        XCTAssertEqual(mesh.coordinates.count, 15)
        XCTAssertEqual(mesh.triangles.count, 48, "sixteen triangles")
        XCTAssertTrue(mesh.triangles.allSatisfy { $0 < 15 })

        // The middle of each ring is at the front, towards the viewer.
        let front = mesh.positions[5 + 2]
        XCTAssertEqual(front.x, 0, accuracy: accuracy)
        XCTAssertEqual(front.z, 1, accuracy: accuracy)
        XCTAssertEqual(mesh.coordinates[5 + 2], SIMD2(0.5, 0))
        // A quarter of the way further round is to the right.
        XCTAssertEqual(mesh.positions[5 + 3].x, 1, accuracy: accuracy)
        XCTAssertEqual(mesh.coordinates[5 + 3].x, 0.75)
        // The seam is at the back, and its two copies are in one place.
        XCTAssertEqual(mesh.positions[5].z, -1, accuracy: accuracy)
        XCTAssertEqual(mesh.positions[9].z, -1, accuracy: accuracy)
        XCTAssertEqual(mesh.coordinates[5].x, 0)
        XCTAssertEqual(mesh.coordinates[9].x, 1)

        // The base faces down, the tip's ring is at the top of the picture.
        XCTAssertEqual(mesh.normals[0].y, -1, accuracy: accuracy)
        XCTAssertEqual(mesh.coordinates[10].y, 1)
        XCTAssertTrue(mesh.positions[10...14].allSatisfy { $0.x == 0 && $0.z == 0 && $0.y == 2 })
        for normal in mesh.normals {
            XCTAssertEqual((normal * normal).sum().squareRoot(), 1, accuracy: accuracy)
        }
        // On the rim the surface faces outwards and a little up, as a cone's does.
        XCTAssertGreaterThan(mesh.normals[5 + 2].z, 0)
    }
}
