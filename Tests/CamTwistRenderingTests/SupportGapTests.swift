import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

final class ColorSpaceAndFilterTests: XCTestCase {
    func testAnUnknownColourSpaceNameFallsBackToDeviceRGB() {
        let space = SRGBColorSpace.make(named: "no such colour space" as CFString)

        XCTAssertEqual(space.numberOfComponents, 3)
        XCTAssertNotEqual(space.name, CGColorSpace.sRGB)
        XCTAssertEqual(SRGBColorSpace.shared.name, CGColorSpace.sRGB)
    }

    func testAFilterThatDoesNotExistGivesTheFallbackPicture() {
        let fallback = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))

        let missing = FilterOutput.image(named: "NoSuchFilter", parameters: [:], fallback: fallback)
        let real = FilterOutput.image(named: "CIConstantColorGenerator", parameters: [
            kCIInputColorKey: CIColor.blue,
        ], fallback: fallback)

        XCTAssertEqual(missing.extent, fallback.extent)
        XCTAssertTrue(real.extent.isInfinite)
    }

    func testAPictureWithNoExtentGivesBlankBytes() {
        let access = makePixelAccess()

        XCTAssertEqual(access.rgba(of: CIImage.empty(), width: 2, height: 2), [UInt8](repeating: 0, count: 16))
    }
}

final class MatrixGlyphTests: XCTestCase {
    func testNothingIsDrawnWhenThereIsNoSurfaceToDrawOn() {
        XCTAssertEqual(DrawnMatrixFont.draw("Z", glyphSize: 0), [])
        XCTAssertTrue(DrawnMatrixFont.draw("Z", glyphSize: 16).contains { $0 > 0 })
    }
}

final class CompositorEdgeTests: XCTestCase {
    func testAPictureWithoutAFiniteSizeIsLeftAsItIs() {
        let compositor = Compositor(canvas: CGSize(width: 32, height: 18))
        let endless = CIImage(color: .red)

        let frame = compositor.compose([.picture(endless, placement: nil)], time: 0)

        XCTAssertEqual(frame.extent, CGRect(x: 0, y: 0, width: 32, height: 18))
    }
}

final class BadTVEdgeTests: XCTestCase {
    func testMissingValuesUseTheEffectsOwnDefaults() {
        let canvas = CGSize(width: 64, height: 36)
        let picture = CIImage(color: .blue).cropped(to: CGRect(origin: .zero, size: canvas))

        let output = DodgySignal.apply(to: picture, values: [:], time: 1, canvas: canvas)

        XCTAssertEqual(output.extent.size, canvas)
    }
}

final class SnapshotConversionTests: XCTestCase {
    func testNoSnapshotMeansNoPicture() {
        XCTAssertNil(WebPageCamera.frame(from: nil))
        XCTAssertNil(WebPageCamera.frame(from: NSImage()))
    }

    func testASnapshotBecomesAPicture() {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }

        XCTAssertNotNil(WebPageCamera.frame(from: image))
    }
}

final class CanvasEdgeTests: XCTestCase {
    private let empty = CGSize.zero

    func testNothingCanBeDrawnOnACanvasWithNoSize() {
        XCTAssertNil(CanvasDrawing.image(size: empty) { _ in })
    }

    func testOverlaysLeavePicturesAloneWhenTheirCanvasCannotBeDrawn() {
        let picture = CIImage(color: .green).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let clock = ClockEffect(canvas: empty, now: Date.init)
        let bubble = ThoughtBubbleEffect(canvas: empty)
        clock.setValues([:])
        bubble.setValues([:])

        XCTAssertEqual(clock.apply(to: picture, time: 0).extent, picture.extent)
        XCTAssertEqual(bubble.apply(to: picture, time: 0).extent, picture.extent)
    }

    func testTheClockWorksWithItsOwnClock() {
        let canvas = CGSize(width: 64, height: 36)
        let clock = ClockEffect(canvas: canvas, now: Date.init)
        let picture = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: canvas))

        XCTAssertEqual(clock.apply(to: picture, time: 0).extent.size, canvas)
    }

    func testTelestratorWithoutACanvasShowsNothing() {
        let source = TelestratorSource(settings: TelestratorSettings(), canvas: empty)

        XCTAssertNil(source.latestFrame)
    }
}
