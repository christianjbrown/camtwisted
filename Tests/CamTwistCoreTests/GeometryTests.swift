import XCTest
@testable import CamTwistCore

final class AspectFitterTests: XCTestCase {
    private let canvas = CGSize(width: 1280, height: 720)

    func testFitLetterboxesTallerContent() {
        let frame = AspectFitter.fit(CGSize(width: 400, height: 400), in: canvas)
        XCTAssertEqual(frame, CGRect(x: 280, y: 0, width: 720, height: 720))
    }

    func testFillCoversTheCanvasAndOverflows() {
        let frame = AspectFitter.fill(CGSize(width: 400, height: 400), in: canvas)
        XCTAssertEqual(frame, CGRect(x: 0, y: -280, width: 1280, height: 1280))
    }

    func testSameShapeFillsExactly() {
        let content = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(AspectFitter.fit(content, in: canvas), CGRect(origin: .zero, size: canvas))
        XCTAssertEqual(AspectFitter.fill(content, in: canvas), CGRect(origin: .zero, size: canvas))
    }

    func testEmptyContentTakesTheWholeCanvas() {
        XCTAssertEqual(AspectFitter.fit(.zero, in: canvas), CGRect(origin: .zero, size: canvas))
        XCTAssertEqual(
            AspectFitter.fill(CGSize(width: 10, height: 0), in: canvas),
            CGRect(origin: .zero, size: canvas)
        )
    }
}

final class PictureInPictureLayoutTests: XCTestCase {
    private let canvas = CGSize(width: 1000, height: 500)
    private let content = CGSize(width: 400, height: 200)

    private func frame(_ corner: Corner, scale: Double = 0.2, margin: Double = 0.01) -> CGRect {
        PictureInPictureLayout.frame(
            for: content,
            in: canvas,
            settings: PictureInPictureSettings(corner: corner, scale: scale, margin: margin, canvasAspect: 2)
        )
    }

    private func assertEqual(_ frame: CGRect, _ expected: CGRect, line: UInt = #line) {
        XCTAssertEqual(frame.minX, expected.minX, accuracy: 0.001, line: line)
        XCTAssertEqual(frame.minY, expected.minY, accuracy: 0.001, line: line)
        XCTAssertEqual(frame.width, expected.width, accuracy: 0.001, line: line)
        XCTAssertEqual(frame.height, expected.height, accuracy: 0.001, line: line)
    }

    func testEachCornerKeepsTheMargin() {
        assertEqual(frame(.bottomLeft), CGRect(x: 10, y: 10, width: 200, height: 100))
        assertEqual(frame(.bottomRight), CGRect(x: 790, y: 10, width: 200, height: 100))
        assertEqual(frame(.topLeft), CGRect(x: 10, y: 390, width: 200, height: 100))
        assertEqual(frame(.topRight), CGRect(x: 790, y: 390, width: 200, height: 100))
    }

    func testScaleIsClampedToItsRange() {
        XCTAssertEqual(frame(.bottomLeft, scale: 5).width, 3000, "three canvases wide at most")
        XCTAssertEqual(frame(.bottomLeft, scale: 0).width, 50)
    }

    func testAPictureSitsAroundItsCentreAndMayHangOffTheCanvas() {
        func frame(at center: CGPoint) -> CGRect {
            PictureInPictureLayout.frame(
                for: content, in: canvas, settings: PictureInPictureSettings(center: center, scale: 0.2)
            )
        }
        XCTAssertEqual(frame(at: CGPoint(x: 0.5, y: 0.5)), CGRect(x: 400, y: 200, width: 200, height: 100))
        XCTAssertEqual(frame(at: CGPoint(x: 0, y: 1)), CGRect(x: -100, y: 450, width: 200, height: 100))
        XCTAssertEqual(frame(at: CGPoint(x: 1.2, y: -0.2)), CGRect(x: 1100, y: -150, width: 200, height: 100))
    }

    func testADragAwayFromTheMiddleGrowsThePictureAndTowardsShrinksIt() {
        var picture = PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5), scale: 0.4)
        picture.resize(draggingFrom: CGPoint(x: 0.6, y: 0.5), to: CGPoint(x: 0.7, y: 0.5))
        XCTAssertEqual(picture.scale, 0.8, accuracy: 0.0001)
        picture.resize(draggingFrom: CGPoint(x: 0.5, y: 0.7), to: CGPoint(x: 0.5, y: 0.6))
        XCTAssertEqual(picture.scale, 0.4, accuracy: 0.0001)
        picture.resize(draggingFrom: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.9, y: 0.9))
        XCTAssertEqual(picture.scale, 0.4, accuracy: 0.0001, "a drag from the very middle changes nothing")
        picture.resize(draggingFrom: CGPoint(x: 0.52, y: 0.5), to: CGPoint(x: 1.5, y: 0.5))
        XCTAssertEqual(picture.scale, PictureInPictureSettings.scaleRange.upperBound)
        picture.resize(draggingFrom: CGPoint(x: 0.9, y: 0.5), to: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(picture.scale, PictureInPictureSettings.scaleRange.lowerBound)
    }

    func testADragRoundTheMiddleTurnsThePicture() {
        var picture = PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5))
        // From the right of the middle down to below it: a quarter turn clockwise.
        picture.turn(draggingFrom: CGPoint(x: 0.7, y: 0.5), to: CGPoint(x: 0.5, y: 0.3), canvasAspect: 1)
        XCTAssertEqual(picture.rotation, 90, accuracy: 0.0001)
        picture.turn(draggingFrom: CGPoint(x: 0.7, y: 0.5), to: CGPoint(x: 0.5, y: 0.3), canvasAspect: 1)
        picture.turn(draggingFrom: CGPoint(x: 0.7, y: 0.5), to: CGPoint(x: 0.6, y: 0.4), canvasAspect: 1)
        XCTAssertEqual(picture.rotation, -135, accuracy: 0.0001, "past a half turn it comes round the other way")
        picture.turn(draggingFrom: CGPoint(x: 0.7, y: 0.5), to: CGPoint(x: 0.5, y: 0.7), canvasAspect: 1)
        XCTAssertEqual(picture.rotation, 135, accuracy: 0.0001)
    }

    func testSnappingMovesToACornerAndKeepsSizeAndAngle() {
        var settings = PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5), scale: 0.2, rotation: 30)
        settings.snap(to: .topLeft, canvasAspect: 2)
        XCTAssertEqual(settings.center.x, 0.13, accuracy: 0.0001)
        XCTAssertEqual(settings.center.y, 0.84, accuracy: 0.0001)
        XCTAssertEqual(settings.scale, 0.2)
        XCTAssertEqual(settings.rotation, 30)
    }

    func testDragsMoveOverlaysAndPictures() {
        let moved = OverlayPosition.moved(x: 0, y: 0.1, by: CGPoint(x: 0.25, y: 0.5), canvas: CGSize(width: 1280, height: 720))
        XCTAssertEqual(moved.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 0.6625, accuracy: 0.0001)
        let size = CGSize(width: 1280, height: 720)
        XCTAssertEqual(OverlayPosition.unitPoint(x: 0, y: 0, canvas: size), CGPoint(x: 0.5, y: 0.5))
        let corner = OverlayPosition.unitPoint(x: 1, y: 0.5625, canvas: size)
        XCTAssertEqual(corner.x, 1, accuracy: 0.0001)
        XCTAssertEqual(corner.y, 1, accuracy: 0.0001)
        XCTAssertEqual(OverlayPosition.unitPoint(x: 1, y: 1, canvas: .zero), CGPoint(x: 0.5, y: 0.5))
        let untouched = OverlayPosition.moved(x: 1, y: 2, by: CGPoint(x: 1, y: 1), canvas: .zero)
        XCTAssertEqual(untouched.x, 1)
        XCTAssertEqual(untouched.y, 2)
        let dragged = OverlayPosition.moved(center: CGPoint(x: 0.9, y: 0.1), by: CGPoint(x: 0.3, y: -0.3))
        XCTAssertEqual(dragged.x, 1.2, accuracy: 0.0001, "free to leave the canvas")
        XCTAssertEqual(dragged.y, -0.2, accuracy: 0.0001)
    }

    func testEmptyContentHasNoFrame() {
        let frame = PictureInPictureLayout.frame(
            for: .zero, in: canvas, settings: PictureInPictureSettings()
        )
        XCTAssertEqual(frame, .zero)
    }

    func testDefaultsSitBottomRightUnturned() {
        let settings = PictureInPictureSettings()
        XCTAssertEqual(settings.scale, PictureInPictureSettings.defaultScale)
        XCTAssertEqual(settings.rotation, 0)
        XCTAssertGreaterThan(settings.center.x, 0.5)
        XCTAssertLessThan(settings.center.y, 0.5)
    }

    func testSettingsSavedByCornerStillLoad() throws {
        let older = #"{"corner":"topLeft","scale":0.4,"margin":0.02}"#
        let settings = try JSONDecoder().decode(PictureInPictureSettings.self, from: Data(older.utf8))
        XCTAssertEqual(settings, PictureInPictureSettings(corner: .topLeft, scale: 0.4, margin: 0.02))

        let bare = try JSONDecoder().decode(PictureInPictureSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(bare, PictureInPictureSettings())
        let turned = try JSONDecoder().decode(
            PictureInPictureSettings.self, from: Data(#"{"corner":"topRight","rotation":15}"#.utf8)
        )
        XCTAssertEqual(turned.rotation, 15)
    }

    func testSettingsRoundTripWithTheirAngle() throws {
        let settings = PictureInPictureSettings(center: CGPoint(x: 0.25, y: 0.75), scale: 0.5, rotation: -45)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(PictureInPictureSettings.self, from: data), settings)
    }
}

final class CameraContractTests: XCTestCase {
    func testStreamsAreDistinctAndOrdered() {
        XCTAssertNotEqual(CameraContract.sourceStreamID, CameraContract.sinkStreamID)
        XCTAssertNotEqual(CameraContract.deviceID, CameraContract.sourceStreamID)
        XCTAssertLessThan(CameraContract.sourceStreamIndex, CameraContract.sinkStreamIndex)
    }

    func testSizeMatchesTheDimensions() {
        XCTAssertEqual(
            CameraContract.size,
            CGSize(width: CameraContract.width, height: CameraContract.height)
        )
    }
}

final class ColorBarsTests: XCTestCase {
    func testBarsTileTheCanvasLeftToRight() {
        let bars = ColorBars.bars(in: CGSize(width: 700, height: 100))

        XCTAssertEqual(bars.count, ColorBars.colors.count)
        XCTAssertEqual(bars.first?.frame, CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(bars.last?.frame, CGRect(x: 600, y: 0, width: 100, height: 100))
        XCTAssertEqual(bars.map(\.color), ColorBars.colors)
        XCTAssertEqual(bars.first?.color, RGBColor(red: 0.75, green: 0.75, blue: 0.75))
    }
}
