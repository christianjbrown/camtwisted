import XCTest
@testable import CamTwistCore

final class ChromaKeyTests: XCTestCase {
    private let green = ChromaKeySettings(red: 0, green: 1, blue: 0, similarity: 0.4, smoothness: 0.08, spillReduction: 0.1)

    func testTheKeyColourTurnsClearAndOtherColoursStay() {
        XCTAssertEqual(
            ChromaKey.keyed(red: 0, green: 1, blue: 0, settings: green), KeyedColor(red: 0, green: 0, blue: 0, alpha: 0)
        )
        XCTAssertEqual(ChromaKey.keyed(red: 0.1, green: 0.9, blue: 0.1, settings: green).alpha, 0, "near green goes too")
        let red = ChromaKey.keyed(red: 1, green: 0, blue: 0, settings: green)
        XCTAssertEqual(red.alpha, 1)
        XCTAssertEqual(red.red, 1, accuracy: 0.0001)
        XCTAssertEqual(red.green, 0, accuracy: 0.0001)
        XCTAssertEqual(ChromaKey.keyed(red: 0, green: 0.3, blue: 0, settings: green).alpha, 0, "green in shadow goes too")
        XCTAssertEqual(ChromaKey.keyed(red: 0, green: 0, blue: 0, settings: green).alpha, 1, "black is not the backdrop")
        XCTAssertEqual(ChromaKey.keyed(red: 0.01, green: 0.03, blue: 0.01, settings: green).alpha, 1, "nor is nearly black")
        let white = ChromaKey.keyed(red: 1, green: 1, blue: 1, settings: green)
        XCTAssertEqual(white.alpha, 1, "white has no colour to it, so it is far from green")
    }

    func testTheEdgeFadesAndLosesItsTint() {
        var wide = green
        wide.similarity = 0.2
        wide.smoothness = 0.5
        wide.spillReduction = 0.5
        // A greenish grey sits part way out from the key colour.
        let edge = ChromaKey.keyed(red: 0.3, green: 0.7, blue: 0.3, settings: wide)
        XCTAssertGreaterThan(edge.alpha, 0)
        XCTAssertLessThan(edge.alpha, 1)
        let unpremultiplied = (red: edge.red / edge.alpha, green: edge.green / edge.alpha)
        XCTAssertLessThan(unpremultiplied.green - unpremultiplied.red, 0.4, "less green than it went in with")
    }

    func testWithNoFadeTheEdgeIsHard() {
        var hard = green
        hard.smoothness = 0
        hard.spillReduction = 0
        XCTAssertEqual(ChromaKey.keyed(red: 0, green: 1, blue: 0, settings: hard).alpha, 0)
        let kept = ChromaKey.keyed(red: 1, green: 0, blue: 1, settings: hard)
        XCTAssertEqual(kept, KeyedColor(red: 1, green: 0, blue: 1, alpha: 1))
    }

    func testTheCubeHoldsEveryColourWithRedChangingFastest() {
        let cube = ChromaKey.cube(for: green)
        let side = ChromaKey.cubeSize
        XCTAssertEqual(cube.count, side * side * side * 4)
        // Pure red is the last entry of the first row.
        let red = (side - 1) * 4
        XCTAssertEqual(Array(cube[red..<red + 4]), [1, 0, 0, 1])
        // Pure green is the first entry of the last row of the first slice.
        let greenAt = (side - 1) * side * 4
        XCTAssertEqual(cube[greenAt + 3], 0)
    }
}
