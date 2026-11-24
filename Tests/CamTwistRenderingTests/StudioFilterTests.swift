import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

final class StudioFilterTests: XCTestCase {
    private let canvas = CGSize(width: 320, height: 180)
    private let access = makePixelAccess()
    private var bounds: CGRect { CGRect(origin: .zero, size: canvas) }

    private func solid(_ color: CIColor) -> CIImage {
        CIImage(color: color).cropped(to: bounds)
    }

    /// Left half one colour, right half another.
    private func halves(_ left: CIColor, _ right: CIColor) -> CIImage {
        solid(right)
            .replacingLeftHalf(with: left, in: bounds)
    }

    /// The red, green, blue and alpha at a point, with x and y as fractions
    /// of the picture. Whatever the effect left clear reads as nothing.
    private func pixel(_ image: CIImage, x: Double, y: Double) -> [Int] {
        let whole = image.composited(over: CIImage(color: .clear).cropped(to: bounds))
        let bytes = access.rgba(of: whole, width: 320, height: 180)
        let index = (min(Int(y * 180), 179) * 320 + min(Int(x * 320), 319)) * 4
        return bytes[index..<index + 4].map(Int.init)
    }

    private func effect(named name: String) throws -> ImageEffect {
        try XCTUnwrap(NativeEffect.studioFilters.first { $0.name == name }).make(canvas)
    }

    func testTheSetHasTheUsualFiltersAndEachRunsAsItStarts() {
        XCTAssertEqual(NativeEffect.studioFilters.map(\.name), [
            "Luma Key", "Blur", "Sharpen", "Crop", "Scroll", "Pixelate", "Vignette", "Mask",
        ])
        for filter in NativeEffect.studioFilters {
            XCTAssertEqual(filter.kind, .filter)
            let made = filter.make(canvas)
            made.setValues(Dictionary(uniqueKeysWithValues: filter.parameters.map { ($0.key, $0.defaultValue) }))
            XCTAssertFalse(made.apply(to: solid(.gray), time: 1).extent.isInfinite, filter.name)
        }
    }

    func testLumaKeyClearsTheDarkPartsOrTheBrightOnes() throws {
        let key = try effect(named: "Luma Key")
        XCTAssertEqual(pixel(key.apply(to: solid(.black), time: 0), x: 0.5, y: 0.5)[3], 0)
        XCTAssertEqual(pixel(key.apply(to: solid(.white), time: 0), x: 0.5, y: 0.5)[3], 255)
        key.setValues([StudioFilter.LumaKey.brightKey: .boolean(true), StudioFilter.LumaKey.smoothnessKey: .number(0)])
        XCTAssertEqual(pixel(key.apply(to: solid(.white), time: 0), x: 0.5, y: 0.5)[3], 0)
        XCTAssertEqual(pixel(key.apply(to: solid(.black), time: 0), x: 0.5, y: 0.5)[3], 255)
    }

    func testBlurSoftensAnEdgeAndNoneLeavesItSharp() throws {
        let blur = try effect(named: "Blur")
        let edge = halves(.white, .black)
        blur.setValues([StudioFilter.Blur.amountKey: .number(1)])
        let soft = pixel(blur.apply(to: edge, time: 0), x: 0.48, y: 0.5)[0]
        XCTAssertGreaterThan(soft, 30)
        XCTAssertLessThan(soft, 225)
        blur.setValues([StudioFilter.Blur.amountKey: .number(0)])
        XCTAssertGreaterThan(pixel(blur.apply(to: edge, time: 0), x: 0.48, y: 0.5)[0], 240)
    }

    func testSharpenLeavesAFlatPictureAlone() throws {
        let sharpen = try effect(named: "Sharpen")
        let grey = pixel(sharpen.apply(to: solid(.gray), time: 0), x: 0.5, y: 0.5)
        XCTAssertEqual(grey[0], pixel(solid(.gray), x: 0.5, y: 0.5)[0], accuracy: 3)
    }

    func testCropTakesTheSidesOff() throws {
        let crop = try effect(named: "Crop")
        crop.setValues([StudioFilter.Crop.leftKey: .number(0.5), StudioFilter.Crop.topKey: .number(0.5)])
        XCTAssertEqual(crop.apply(to: solid(.white), time: 0).extent, CGRect(x: 160, y: 0, width: 160, height: 90))
        crop.setValues([
            StudioFilter.Crop.leftKey: .number(2), StudioFilter.Crop.rightKey: .number(2),
            StudioFilter.Crop.bottomKey: .number(-1),
        ])
        let gone = crop.apply(to: solid(.white), time: 0).extent
        XCTAssertTrue(gone.isEmpty, "each side is held to its range, and the two together leave nothing")
    }

    func testScrollMovesThePictureAndWrapsItRound() throws {
        let scroll = try effect(named: "Scroll")
        let picture = halves(.red, .blue)
        scroll.setValues([StudioFilter.Scroll.horizontalKey: .number(0.5)])
        XCTAssertGreaterThan(pixel(scroll.apply(to: picture, time: 0), x: 0.25, y: 0.5)[0], 200, "red on the left to begin with")
        let moved = pixel(scroll.apply(to: picture, time: 1), x: 0.25, y: 0.5)
        XCTAssertGreaterThan(moved[2], 200, "half a picture on, blue has come round to the left")
        XCTAssertEqual(scroll.apply(to: picture, time: 1).extent, bounds)
        XCTAssertGreaterThan(pixel(scroll.apply(to: picture, time: 2), x: 0.25, y: 0.5)[0], 200, "a whole picture on, back where it began")
    }

    func testPixelateMakesBlocksAndTheSmallestSizeLeavesItAlone() throws {
        let pixelate = try effect(named: "Pixelate")
        let edge = halves(.white, .black)
        pixelate.setValues([StudioFilter.Pixelate.sizeKey: .number(1)])
        // 32 point blocks: the block from 160 to 192 is all black, and so
        // is every point in it; the block before it all white.
        XCTAssertGreaterThan(pixel(pixelate.apply(to: edge, time: 0), x: 0.45, y: 0.5)[0], 240)
        XCTAssertLessThan(pixel(pixelate.apply(to: edge, time: 0), x: 0.55, y: 0.5)[0], 15)
        pixelate.setValues([StudioFilter.Pixelate.sizeKey: .number(0)])
        XCTAssertEqual(pixelate.apply(to: edge, time: 0).extent, bounds)
    }

    func testVignetteDarkensTheCorners() throws {
        let vignette = try effect(named: "Vignette")
        vignette.setValues([StudioFilter.Vignette.amountKey: .number(1)])
        let output = vignette.apply(to: solid(.white), time: 0)
        XCTAssertLessThan(pixel(output, x: 0.01, y: 0.01)[0], pixel(output, x: 0.5, y: 0.5)[0] - 20)
    }

    func testTheMaskKeepsItsShapeGoesWhereItIsPutAndTurnsOver() throws {
        let mask = try effect(named: "Mask")
        let output = mask.apply(to: solid(.white), time: 0)
        XCTAssertEqual(pixel(output, x: 0.5, y: 0.5)[3], 255)
        XCTAssertEqual(pixel(output, x: 0.02, y: 0.02)[3], 0)

        mask.setValues([MaskEffect.xKey: .number(-0.8), MaskEffect.sizeKey: .number(0.2)])
        let moved = mask.apply(to: solid(.white), time: 0)
        XCTAssertEqual(pixel(moved, x: 0.1, y: 0.5)[3], 255)
        XCTAssertEqual(pixel(moved, x: 0.5, y: 0.5)[3], 0)

        // Reversed, the inside goes and the outside stays.
        mask.setValues([MaskEffect.reverseKey: .boolean(true), MaskEffect.softnessKey: .number(0)])
        let reversed = mask.apply(to: solid(.white), time: 0)
        XCTAssertEqual(pixel(reversed, x: 0.5, y: 0.5)[3], 0)
        XCTAssertEqual(pixel(reversed, x: 0.02, y: 0.02)[3], 255)
        XCTAssertEqual(pixel(mask.apply(to: solid(.white), time: 1), x: 0.02, y: 0.02)[3], 255)
    }

    func testTheMasksEdgeIsHardUntilItIsSoftened() throws {
        let mask = try effect(named: "Mask")
        func partlyClear(softness: Double) -> Int {
            mask.setValues([MaskEffect.softnessKey: .number(softness)])
            let output = mask.apply(to: solid(.white), time: 0)
            // Along the middle row, how much of the picture is neither kept nor gone.
            return stride(from: 0.0, to: 1.0, by: 0.01).filter { x in
                let alpha = pixel(output, x: x, y: 0.5)[3]
                return alpha > 20 && alpha < 235
            }.count
        }
        let hard = partlyClear(softness: 0)
        XCTAssertGreaterThan(partlyClear(softness: 0.1), hard + 5, "a softened edge fades over a distance")
    }

    func testTheMaskComesInShapesAndTurns() throws {
        let mask = try effect(named: "Mask")
        // A triangle's point is at the top: its bottom corners are kept and
        // the corners of its box up top are not. Turned half way, the reverse.
        func corners(rotation: Double) -> (top: Int, bottom: Int) {
            mask.setValues([
                MaskEffect.shapeKey: .string("Triangle"), MaskEffect.sizeKey: .number(0.5),
                MaskEffect.softnessKey: .number(0), MaskEffect.rotationKey: .number(rotation),
            ])
            let output = mask.apply(to: solid(.white), time: 0)
            // The box is 160 by 90 round the middle: these sit just inside its left edge.
            return (pixel(output, x: 0.27, y: 0.28)[3], pixel(output, x: 0.27, y: 0.72)[3])
        }
        XCTAssertEqual(corners(rotation: 0).top, 0)
        XCTAssertEqual(corners(rotation: 0).bottom, 255)
        XCTAssertEqual(corners(rotation: 180).top, 255)
        XCTAssertEqual(corners(rotation: 180).bottom, 0)

        // A name that is no shape is a circle; every shape keeps its middle.
        for shape in ["Rectangle", "Square", "Circle", "Ellipse", "Triangle", "Diamond", "Star", "Blob"] {
            mask.setValues([MaskEffect.shapeKey: .string(shape)])
            XCTAssertEqual(pixel(mask.apply(to: solid(.white), time: 0), x: 0.5, y: 0.5)[3], 255, shape)
        }
        XCTAssertEqual(MaskEffect.parameters.first?.choices, ["Rectangle", "Square", "Circle", "Ellipse", "Triangle", "Diamond", "Star"])
        XCTAssertEqual(MaskEffect.parameters.map(\.displayName), [
            "Shape", "X Position", "Y Position", "Size", "Rotation", "Softness", "Reverse: hide the inside",
        ])
        XCTAssertEqual(MaskEffect(canvas: .zero).apply(to: solid(.white), time: 0).extent, solid(.white).extent)
    }
}

private extension CIImage {
    func replacingLeftHalf(with color: CIColor, in bounds: CGRect) -> CIImage {
        CIImage(color: color)
            .cropped(to: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width / 2, height: bounds.height))
            .composited(over: self)
    }
}
