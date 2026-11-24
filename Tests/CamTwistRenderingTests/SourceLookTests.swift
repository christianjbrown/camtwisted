import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

private let size = CGSize(width: 200, height: 100)
private let access = makePixelAccess()

private func solid(_ color: CIColor, _ rect: CGRect) -> CIImage {
    CIImage(color: color).cropped(to: rect)
}

/// Red on the left half, blue on the right, with a green strip along the top.
private var scene: CIImage {
    solid(.green, CGRect(x: 0, y: 80, width: 200, height: 20))
        .composited(over: solid(.red, CGRect(x: 0, y: 0, width: 100, height: 100)))
        .composited(over: solid(.blue, CGRect(origin: .zero, size: size)))
}

private func pixel(_ image: CIImage, x: Int, y: Int) -> [UInt8] {
    let bytes = access.rgba(of: image, width: 200, height: 100)
    return Array(bytes[(y * 200 + x) * 4..<(y * 200 + x) * 4 + 3])
}

final class SourceLookTests: XCTestCase {
    private func look(_ adjustments: SourceAdjustments?) -> CIImage {
        SourceLook.apply(adjustments, to: scene)
    }

    func testNoAdjustmentsLeaveThePictureAlone() {
        XCTAssertEqual(pixel(look(nil), x: 20, y: 50), [255, 0, 0])
        XCTAssertEqual(pixel(look(SourceAdjustments()), x: 180, y: 50), [0, 0, 255])
    }

    func testFlipsMirrorThePictureWhereItStands() {
        let sideways = look(SourceAdjustments(flipsHorizontally: true))
        XCTAssertEqual(sideways.extent, CGRect(origin: .zero, size: size))
        XCTAssertEqual(pixel(sideways, x: 20, y: 50), [0, 0, 255], "the right half is now on the left")
        XCTAssertEqual(pixel(sideways, x: 20, y: 5), [0, 255, 0], "the top strip is still at the top")

        let upsideDown = look(SourceAdjustments(flipsVertically: true))
        XCTAssertEqual(pixel(upsideDown, x: 20, y: 95), [0, 255, 0], "the top strip is now at the bottom")
        XCTAssertEqual(pixel(upsideDown, x: 20, y: 50), [255, 0, 0], "left and right are unchanged")
    }

    func testZoomShowsOnlyTheMiddle() {
        let zoomed = look(SourceAdjustments(zoom: 2))
        XCTAssertEqual(zoomed.extent, CGRect(x: 50, y: 25, width: 100, height: 50))
        XCTAssertEqual(pixel(zoomed, x: 60, y: 5), [255, 0, 0], "the green strip at the top is cut off")
    }

    func testZoomedOutThePictureSitsSmallerInAClearFrame() {
        let small = look(SourceAdjustments(zoom: 0.5))
        XCTAssertEqual(small.extent, CGRect(x: -100, y: -50, width: 400, height: 200))
        // The frame is twice the picture each way: its outer quarter is clear
        // and the picture is whole in the middle.
        let bytes = access.rgba(of: small, width: 200, height: 100)
        XCTAssertEqual(bytes[(5 * 200 + 5) * 4 + 3], 0, "clear in the corner")
        XCTAssertEqual(Array(bytes[(50 * 200 + 60) * 4..<(50 * 200 + 60) * 4 + 4]), [255, 0, 0, 255], "the left half, red")
        XCTAssertEqual(Array(bytes[(50 * 200 + 140) * 4..<(50 * 200 + 140) * 4 + 3]), [0, 0, 255], "the right half, blue")
    }

    func testColourControlsChangeTheColours() {
        let noRed = pixel(look(SourceAdjustments(red: 0)), x: 20, y: 50)
        XCTAssertLessThan(noRed[0], 10, "red turned right down")

        let brighter = pixel(look(SourceAdjustments(brightness: 0.4)), x: 180, y: 50)
        XCTAssertGreaterThan(brighter[0], 60, "brightness lifts every colour")

        let grey = pixel(look(SourceAdjustments(saturation: 0)), x: 20, y: 50)
        XCTAssertEqual(Int(grey[0]), Int(grey[2]), accuracy: 3, "no saturation leaves only greys")

        let midGrey = solid(CIColor(red: 0.25, green: 0.25, blue: 0.25), CGRect(origin: .zero, size: size))
        let lifted = pixel(SourceLook.apply(SourceAdjustments(gamma: 2), to: midGrey), x: 10, y: 10)
        XCTAssertGreaterThan(lifted[0], pixel(midGrey, x: 10, y: 10)[0] + 15, "a gamma above 1 lifts the mid tones")
    }

    func testNoiseReductionKeepsThePictureInPlace() {
        let smoothed = look(SourceAdjustments(noiseReduction: 0.05, sharpness: 0.8))
        XCTAssertEqual(pixel(smoothed, x: 20, y: 50)[0], 255, "flat colour stays as it was")
        XCTAssertEqual(pixel(smoothed, x: 180, y: 50)[2], 255)
    }
}

final class PerspectiveCompositingTests: XCTestCase {
    private let compositor = Compositor(canvas: size)

    private func frame(_ placement: PictureInPictureSettings) -> CIImage {
        compositor.compose([
            .picture(solid(.red, CGRect(origin: .zero, size: size)), placement: nil),
            .picture(solid(.blue, CGRect(x: 0, y: 0, width: 100, height: 50)), placement: placement),
        ], time: 0)
    }

    func testASwungPictureLooksNarrower() {
        let flat = frame(PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5), scale: 0.5))
        XCTAssertEqual(pixel(flat, x: 145, y: 50), [0, 0, 255], "the flat picture reaches out to here")

        let swung = frame(PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5), scale: 0.5, swing: 70))
        XCTAssertEqual(pixel(swung, x: 145, y: 50), [255, 0, 0], "swung round, it no longer does")
        XCTAssertEqual(pixel(swung, x: 100, y: 50), [0, 0, 255], "its middle is still there")
    }

    func testATiltedPictureLooksShorter() {
        let tilted = frame(PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5), scale: 0.5, tilt: 70))
        XCTAssertEqual(pixel(tilted, x: 100, y: 28), [255, 0, 0], "the bottom edge has drawn in")
        XCTAssertEqual(pixel(tilted, x: 100, y: 50), [0, 0, 255])
    }
}

private final class NoEffects: ImageEffectFactory {
    func makeEffect(named name: String, canvas: CGSize) -> ImageEffect? { nil }
}

final class AnimatedSceneTests: XCTestCase {
    private let canvas = CameraContract.size

    func testAnimationsRunFromWhenASourceAppearsAndRestartWhenItComesBack() {
        let registry = SourceRegistry(providers: [ShapeSourceProvider()])
        let renderer = SceneRenderer(sources: registry, effectFactory: NoEffects(), canvas: canvas, supplies: .system())
        // A red square that slides from the left quarter to the right quarter in a second.
        var square = ChainItem(
            content: .source(.shape(ShapeSettings(kind: .square, color: RGBColor(red: 1, green: 0, blue: 0)))),
            pictureInPicture: PictureInPictureSettings(center: CGPoint(x: 0.25, y: 0.5), scale: 0.1),
            animations: [SourceAnimation(property: .positionX, from: 0.25, to: 0.75, duration: 1, mode: .once)]
        )
        var scene = SceneConfiguration(items: [square])
        registry.setSourcesInUse(scene.sourcesInUse)

        func redAt(_ fraction: CGFloat, time: TimeInterval) -> Bool {
            let bytes = access.rgba(of: renderer.render(scene, time: time), width: 160, height: 90)
            let index = (45 * 160 + Int(fraction * 160)) * 4
            return bytes[index] > 200 && bytes[index + 1] < 50
        }

        XCTAssertTrue(redAt(0.25, time: 100), "it starts on the left, whatever the clock says")
        XCTAssertTrue(redAt(0.75, time: 101), "a second later it is on the right")
        XCTAssertFalse(redAt(0.25, time: 101))

        square.isEnabled = false
        scene = SceneConfiguration(items: [square])
        _ = renderer.render(scene, time: 102)
        square.isEnabled = true
        scene = SceneConfiguration(items: [square])
        XCTAssertTrue(redAt(0.25, time: 103), "switched off and on, it starts again from the left")
    }

    func testAStillSourceStaysWhereItIsPut() {
        let registry = SourceRegistry(providers: [ShapeSourceProvider()])
        let renderer = SceneRenderer(sources: registry, effectFactory: NoEffects(), canvas: canvas, supplies: .system())
        let square = ChainItem(
            content: .source(.shape(ShapeSettings(kind: .square, color: RGBColor(red: 1, green: 0, blue: 0)))),
            pictureInPicture: PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5), scale: 0.1),
            adjustments: SourceAdjustments(red: 0),
            animations: []
        )
        let scene = SceneConfiguration(items: [square])
        registry.setSourcesInUse(scene.sourcesInUse)

        let bytes = access.rgba(of: renderer.render(scene, time: 5), width: 160, height: 90)
        let centre = (45 * 160 + 80) * 4
        XCTAssertLessThan(bytes[centre], 10, "its red is turned off by its own colour control")
    }
}

final class DrawnSourceTests: XCTestCase {
    private func pixels(_ image: CIImage) -> (width: Int, height: Int, bytes: [UInt8]) {
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        return (width, height, access.rgba(of: image, width: width, height: height))
    }

    private func alpha(_ picture: (width: Int, height: Int, bytes: [UInt8]), x: Double, y: Double) -> UInt8 {
        // x and y are fractions of the picture, measured from its top left.
        let column = min(Int(x * Double(picture.width)), picture.width - 1)
        let row = min(Int(y * Double(picture.height)), picture.height - 1)
        return picture.bytes[(row * picture.width + column) * 4 + 3]
    }

    func testEachShapeIsFilledInsideAndClearOutside() throws {
        func drawn(_ kind: ShapeKind) throws -> (width: Int, height: Int, bytes: [UInt8]) {
            let source = try XCTUnwrap(ShapeSourceProvider().makeSource(for: .shape(ShapeSettings(kind: kind))))
            return pixels(try XCTUnwrap(source.latestFrame))
        }
        let rectangle = try drawn(.rectangle)
        XCTAssertEqual(rectangle.width, CameraContract.width)
        XCTAssertEqual(rectangle.height, CameraContract.height)
        XCTAssertEqual(alpha(rectangle, x: 0.01, y: 0.01), 255, "a rectangle is filled to its corners")

        let circle = try drawn(.circle)
        XCTAssertEqual(circle.width, circle.height, "a circle is drawn in a square box")
        XCTAssertEqual(alpha(circle, x: 0.5, y: 0.5), 255)
        XCTAssertEqual(alpha(circle, x: 0.02, y: 0.02), 0, "and its corners are clear")

        let triangle = try drawn(.triangle)
        XCTAssertEqual(alpha(triangle, x: 0.5, y: 0.9), 255, "wide at the bottom")
        XCTAssertEqual(alpha(triangle, x: 0.05, y: 0.1), 0, "narrow at the top")

        let star = try drawn(.star)
        XCTAssertEqual(alpha(star, x: 0.5, y: 0.5), 255)
        XCTAssertEqual(alpha(star, x: 0.05, y: 0.5), 0)
    }

    func testAShapeHasItsColourAndOpacityAndRedrawsWhenChanged() throws {
        let source = try XCTUnwrap(ShapeSourceProvider().makeSource(for: .shape(ShapeSettings())))
        source.start()
        let half = ShapeSettings(kind: .rectangle, color: RGBColor(red: 1, green: 0, blue: 0), opacity: 0.5)
        XCTAssertTrue(source.update(to: .shape(half)))
        XCTAssertTrue(source.update(to: .shape(half)))
        let picture = pixels(try XCTUnwrap(source.latestFrame))
        XCTAssertEqual(Int(alpha(picture, x: 0.5, y: 0.5)), 128, accuracy: 2)
        XCTAssertGreaterThan(picture.bytes[0], 100, "red, premultiplied by its opacity")
        XCTAssertFalse(source.update(to: .colorBars))
        source.stop()
        XCTAssertNil(ShapeSourceProvider().makeSource(for: .colorBars))
    }

    func testTextIsDrawnInItsColourAndGrowsWithItsWords() throws {
        let provider = TextSourceProvider()
        let short = try XCTUnwrap(provider.makeSource(for: .text(TextSettings(text: "Hi"))))
        let words = String(repeating: "Hello there, everyone. ", count: 8)
        let long = try XCTUnwrap(provider.makeSource(for: .text(TextSettings(text: words))))
        let shortFrame = try XCTUnwrap(short.latestFrame)
        let longFrame = try XCTUnwrap(long.latestFrame)
        XCTAssertEqual(shortFrame.extent.width, CameraContract.size.width, "the box is as wide as the picture")
        XCTAssertEqual(longFrame.extent.width, shortFrame.extent.width, "so more words wrap, and stay the same size")
        XCTAssertGreaterThan(longFrame.extent.height, shortFrame.extent.height * 1.5)

        let lines = try XCTUnwrap(provider.makeSource(for: .text(TextSettings(text: "Hi\nHi"))))
        XCTAssertGreaterThan(try XCTUnwrap(lines.latestFrame).extent.height, shortFrame.extent.height * 1.5)

        let red = TextSettings(text: "MMMM", color: RGBColor(red: 1, green: 0, blue: 0))
        XCTAssertTrue(short.update(to: .text(red)))
        let picture = pixels(try XCTUnwrap(short.latestFrame))
        var inked = 0
        for index in stride(from: 0, to: picture.bytes.count, by: 4) where picture.bytes[index + 3] > 200 {
            inked += 1
            XCTAssertLessThan(picture.bytes[index + 1], 30, "the ink is red, with no green in it")
        }
        XCTAssertGreaterThan(inked, 500)
        XCTAssertEqual(alpha(picture, x: 0.001, y: 0.001), 0, "the background is clear")
    }

    func testTextTakesItsSizeLineHeightAndShadow() throws {
        func frame(_ settings: TextSettings) throws -> CIImage {
            try XCTUnwrap(TextSourceProvider().makeSource(for: .text(settings))?.latestFrame)
        }
        func inked(_ image: CIImage) -> Int {
            let picture = pixels(image)
            return stride(from: 3, to: picture.bytes.count, by: 4).filter { picture.bytes[$0] > 0 }.count
        }
        let plain = try frame(TextSettings(text: "Hi\nHi", fontSize: 60))
        let large = try frame(TextSettings(text: "Hi\nHi", fontSize: 120))
        XCTAssertGreaterThan(large.extent.height, plain.extent.height * 1.5)
        XCTAssertGreaterThan(inked(large), inked(plain) * 2)

        let spaced = try frame(TextSettings(text: "Hi\nHi", fontSize: 60, lineHeight: 2))
        XCTAssertGreaterThan(spaced.extent.height, plain.extent.height * 1.4)

        let shadowed = try frame(TextSettings(text: "Hi\nHi", fontSize: 60, hasShadow: true))
        XCTAssertEqual(shadowed.extent, plain.extent)
        XCTAssertGreaterThan(inked(shadowed), inked(plain), "the shadow adds ink round the letters")

        // Where the ink sits across the box follows the alignment.
        func inkedColumns(_ alignment: TextAlignment) throws -> (left: Int, right: Int) {
            let picture = pixels(try frame(TextSettings(text: "Hi", fontSize: 60, alignment: alignment)))
            var left = 0
            var right = 0
            for index in stride(from: 3, to: picture.bytes.count, by: 4) where picture.bytes[index] > 0 {
                if (index / 4) % picture.width < picture.width / 2 { left += 1 } else { right += 1 }
            }
            return (left, right)
        }
        XCTAssertEqual(try inkedColumns(.left).right, 0)
        XCTAssertEqual(try inkedColumns(.right).left, 0)
        let centred = try inkedColumns(.center)
        XCTAssertGreaterThan(centred.left, 0)
        XCTAssertGreaterThan(centred.right, 0)
        XCTAssertEqual(try inkedColumns(.justified).right, 0, "a last line is not stretched")

        let tiny = try frame(TextSettings(text: "Hi", fontSize: 1, lineHeight: 0))
        let smallest = try frame(TextSettings(
            text: "Hi", fontSize: TextSettings.fontSizeRange.lowerBound,
            lineHeight: TextSettings.lineHeightRange.lowerBound
        ))
        XCTAssertEqual(tiny.extent, smallest.extent, "sizes outside the range are held to it")
    }

    func testEmptyTextDrawsNothing() throws {
        let provider = TextSourceProvider()
        let source = try XCTUnwrap(provider.makeSource(for: .text(TextSettings(text: ""))))
        XCTAssertNil(source.latestFrame)
        XCTAssertFalse(source.update(to: .colorBars))
        XCTAssertNil(provider.makeSource(for: .colorBars))
    }
}
