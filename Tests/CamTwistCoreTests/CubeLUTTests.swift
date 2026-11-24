import XCTest
@testable import CamTwistCore

final class CubeLUTTests: XCTestCase {
    /// The text of a table of some size that turns every colour into itself.
    private func identity(size: Int) -> String {
        var lines = ["TITLE \"Identity\"", "# a comment", "", "LUT_3D_SIZE \(size)", "DOMAIN_MIN 0 0 0", "DOMAIN_MAX 1 1 1"]
        let last = Double(size - 1)
        for blue in 0..<size {
            for green in 0..<size {
                for red in 0..<size {
                    lines.append("\(Double(red) / last) \(Double(green) / last) \(Double(blue) / last)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    func testACubeFileIsReadWithRedChangingFastest() {
        let table = CubeLUT(text: identity(size: 2))
        XCTAssertEqual(table?.size, 2)
        XCTAssertEqual(table?.values.count, 8 * 4)
        XCTAssertEqual(table.map { Array($0.values[4..<8]) }, [1, 0, 0, 1], "the second entry is pure red")
        XCTAssertEqual(table.map { Array($0.values[8..<12]) }, [0, 1, 0, 1], "the third is pure green")
        XCTAssertEqual(CubeLUT(text: identity(size: 2).replacingOccurrences(of: "\n", with: "\r\n"))?.size, 2)
    }

    func testFilesThatDoNotAddUpAreRefused() {
        XCTAssertNil(CubeLUT(text: "0 0 0\n1 1 1"), "no size")
        XCTAssertNil(CubeLUT(text: "LUT_3D_SIZE 2\n0 0 0"), "too few colours")
        XCTAssertNil(CubeLUT(text: "LUT_3D_SIZE 1\n0 0 0"), "a table of one colour")
        XCTAssertNil(CubeLUT(text: "LUT_3D_SIZE two"), "a size that is not a number")
        XCTAssertNil(CubeLUT(text: "LUT_3D_SIZE"), "a size with no number")
        XCTAssertNil(CubeLUT(text: identity(size: 2) + "\n0.5 0.5"), "a colour of two numbers")
        XCTAssertNil(CubeLUT(text: identity(size: 2).replacingOccurrences(of: "1.0 1.0 1.0", with: "1.0 1.0 x")), "a colour with a word in it")
        XCTAssertNil(CubeLUT(text: ""))
    }

    func testATableTooBigForCoreImageIsCutDownByKeepingTheNearestEntries() {
        let small = CubeLUT(text: identity(size: 4))
        XCTAssertEqual(small?.fittingCoreImage, small, "small enough already")

        let big = CubeLUT(text: identity(size: 65))
        let fitted = big?.fittingCoreImage
        XCTAssertEqual(fitted?.size, 64)
        XCTAssertEqual(fitted?.values.count, 64 * 64 * 64 * 4)
        // Still the table that turns each colour into itself, near enough.
        XCTAssertEqual(fitted.map { Array($0.values.suffix(4)) }, [1, 1, 1, 1])
        XCTAssertEqual(fitted?.values[4] ?? 0, 1.0 / 63, accuracy: 0.02)
    }
}
