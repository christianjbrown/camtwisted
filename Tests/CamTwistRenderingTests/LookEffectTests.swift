import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

final class LookEffectTests: XCTestCase {
    private let canvas = CGSize(width: 320, height: 180)
    private let access = makePixelAccess()
    private var bounds: CGRect { CGRect(origin: .zero, size: canvas) }

    /// A picture with something in every part of it: the thumbnailer's scene.
    private var picture: CIImage { EffectThumbnailer.sampleScene(size: canvas) }

    private func bytes(_ image: CIImage) -> [UInt8] {
        access.rgba(of: image.composited(over: CIImage(color: .clear).cropped(to: bounds)), width: 320, height: 180)
    }

    private func pixel(_ image: CIImage, x: Int, y: Int) -> [Int] {
        let all = bytes(image)
        return all[(y * 320 + x) * 4..<(y * 320 + x) * 4 + 4].map(Int.init)
    }

    private func effect(_ name: String) throws -> NativeEffect {
        try XCTUnwrap(NativeEffect.looks.first { $0.name == name })
    }

    func testEveryLookChangesThePictureAndKeepsItsSize() {
        let before = bytes(picture)
        XCTAssertEqual(NativeEffect.looks.map(\.name), [
            "Sepia", "Black and White", "Invert", "Posterize", "Hue Shift", "Tint", "Thermal", "X-Ray",
            "Kaleidoscope", "Mirror", "Twirl", "Pinch", "Halftone", "Crystallize", "Glow", "Motion Blur", "Zoom Blur",
        ])
        for look in NativeEffect.looks {
            XCTAssertEqual(look.kind, .filter)
            let made = look.make(canvas)
            // Once as it starts, once with every control at its own starting value.
            let plain = made.apply(to: picture, time: 0)
            XCTAssertEqual(plain.extent, bounds, look.name)
            XCTAssertNotEqual(bytes(plain), before, "\(look.name) changes the picture")
            made.setValues(Dictionary(uniqueKeysWithValues: look.parameters.map { ($0.key, $0.defaultValue) }))
            XCTAssertEqual(bytes(made.apply(to: picture, time: 0)), bytes(plain), "\(look.name) starts as its controls say")
        }
    }

    func testInvertTurnsWhiteToBlack() throws {
        let white = CIImage(color: .white).cropped(to: bounds)
        XCTAssertEqual(pixel(try effect("Invert").make(canvas).apply(to: white, time: 0), x: 10, y: 10), [0, 0, 0, 255])
    }

    func testTheMirrorReflectsTheSideItKeepsAboutALineThatMoves() throws {
        let leftRed = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 160, height: 180))
            .composited(over: CIImage(color: .blue).cropped(to: bounds))
        let mirror = try effect("Mirror").make(canvas)
        let fromLeft = mirror.apply(to: leftRed, time: 0)
        XCTAssertEqual(Array(pixel(fromLeft, x: 20, y: 90).prefix(3)), [255, 0, 0])
        XCTAssertEqual(Array(pixel(fromLeft, x: 300, y: 90).prefix(3)), [255, 0, 0], "the left half, reflected")
        mirror.setValues([LookEffect.Key.rightSide: .boolean(true)])
        let fromRight = mirror.apply(to: leftRed, time: 0)
        XCTAssertEqual(Array(pixel(fromRight, x: 20, y: 90).prefix(3)), [0, 0, 255], "the right half, reflected")

        // With the mirror three quarters of the way across, the blue just
        // left of it shows again just right of it.
        mirror.setValues([LookEffect.Key.position: .number(0.75)])
        let moved = mirror.apply(to: leftRed, time: 0)
        XCTAssertEqual(Array(pixel(moved, x: 100, y: 90).prefix(3)), [255, 0, 0])
        XCTAssertEqual(Array(pixel(moved, x: 200, y: 90).prefix(3)), [0, 0, 255])
        XCTAssertEqual(Array(pixel(moved, x: 300, y: 90).prefix(3)), [0, 0, 255], "reflected from the left of the line")
        // A quarter of the way across, the reflection only reaches half way.
        mirror.setValues([LookEffect.Key.position: .number(0.25)])
        let narrow = mirror.apply(to: leftRed, time: 0)
        XCTAssertEqual(Array(pixel(narrow, x: 120, y: 90).prefix(3)), [255, 0, 0])
        XCTAssertEqual(pixel(narrow, x: 300, y: 90)[3], 0, "beyond the reflection there is nothing")
    }

    func testTheTintTakesItsColour() throws {
        let tint = try effect("Tint").make(canvas)
        tint.setValues([LookEffect.Key.color: .color(red: 1, green: 0, blue: 0, alpha: 1)])
        // White stays white under a tint; a mid grey takes the colour.
        let red = pixel(tint.apply(to: CIImage(color: .gray).cropped(to: bounds), time: 0), x: 10, y: 10)
        XCTAssertGreaterThan(red[0], red[1] + 60)
    }
}
