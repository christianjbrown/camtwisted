import XCTest
@testable import CamTwistCore

final class SourceAdjustmentsTests: XCTestCase {
    func testUntouchedAdjustmentsAreNeutral() {
        XCTAssertTrue(SourceAdjustments().isNeutral)
        XCTAssertFalse(SourceAdjustments(brightness: 0.1).isNeutral)
        XCTAssertFalse(SourceAdjustments(blue: 1.2).isNeutral)
    }

    func testZoomKeepsTheMiddleOfThePicture() {
        let extent = CGRect(x: 100, y: 0, width: 400, height: 200)
        XCTAssertEqual(SourceAdjustments().visibleRegion(of: extent), extent)
        XCTAssertEqual(SourceAdjustments(zoom: 2).visibleRegion(of: extent), CGRect(x: 200, y: 50, width: 200, height: 100))
        XCTAssertEqual(
            SourceAdjustments(zoom: 0.5).visibleRegion(of: extent), CGRect(x: -100, y: -100, width: 800, height: 400),
            "zoomed out, the view is larger than the picture"
        )
        XCTAssertEqual(SourceAdjustments(zoom: 0).visibleRegion(of: extent).width, 8000, "held to the smallest zoom")
        XCTAssertEqual(SourceAdjustments(zoom: 100).visibleRegion(of: extent).width, 50)
    }

    func testZoomAndFlipsAreNotColourChanges() {
        let framed = SourceAdjustments(zoom: 2, flipsHorizontally: true, flipsVertically: true)
        XCTAssertFalse(framed.isNeutral)
        XCTAssertFalse(framed.changesColor)
        XCTAssertTrue(SourceAdjustments(gamma: 1.2).changesColor)
    }

    func testNoiseReductionIsOffUntilTurnedUp() {
        XCTAssertFalse(SourceAdjustments().reducesNoise)
        XCTAssertEqual(SourceAdjustments().sharpness, SourceAdjustments.defaultSharpness)
        let smoothed = SourceAdjustments(noiseReduction: 0.02, sharpness: 0.9)
        XCTAssertTrue(smoothed.reducesNoise)
        XCTAssertFalse(smoothed.isNeutral)
        XCTAssertFalse(smoothed.changesColor, "smoothing is not a colour change")
    }

    func testEveryControlIsKept() {
        let adjustments = SourceAdjustments(
            brightness: 0.1, contrast: 1.2, saturation: 0.8, gamma: 1.5, red: 1.1, green: 0.9, blue: 0.7
        )
        XCTAssertEqual(
            [adjustments.brightness, adjustments.contrast, adjustments.saturation, adjustments.gamma,
             adjustments.red, adjustments.green, adjustments.blue],
            [0.1, 1.2, 0.8, 1.5, 1.1, 0.9, 0.7]
        )
    }
}

final class AnimationClockTests: XCTestCase {
    private func progress(_ elapsed: Double, _ mode: AnimationMode, duration: Double = 2) -> Double {
        AnimationClock.progress(elapsed: elapsed, duration: duration, mode: mode)
    }

    func testOncePlaysThroughAndStops() {
        XCTAssertEqual(progress(0, .once), 0)
        XCTAssertEqual(progress(1, .once), 0.5)
        XCTAssertEqual(progress(5, .once), 1)
    }

    func testLoopStartsAgain() {
        XCTAssertEqual(progress(1, .loop), 0.5)
        XCTAssertEqual(progress(3, .loop), 0.5)
        XCTAssertEqual(progress(4, .loop), 0)
    }

    func testBackAndForthTurnsRound() {
        XCTAssertEqual(progress(1, .backAndForth), 0.5)
        XCTAssertEqual(progress(2, .backAndForth), 1)
        XCTAssertEqual(progress(3, .backAndForth), 0.5)
        XCTAssertEqual(progress(4, .backAndForth), 0)
    }

    func testNoDurationOrNoTimeIsAtAnEnd() {
        XCTAssertEqual(progress(1, .loop, duration: 0), 1)
        XCTAssertEqual(progress(0, .loop, duration: 0), 0)
        XCTAssertEqual(progress(-1, .once), 0)
    }
}

final class SourceAnimationTests: XCTestCase {
    private let settings = PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5), scale: 0.4)

    func testValueRunsFromStartToEnd() {
        let animation = SourceAnimation(property: .size, from: 0.2, to: 0.6, duration: 2, mode: .once)
        XCTAssertEqual(animation.value(at: 0), 0.2)
        XCTAssertEqual(animation.value(at: 1), 0.4, accuracy: 0.0001)
        XCTAssertEqual(animation.value(at: 9), 0.6, accuracy: 0.0001)
    }

    func testEachPropertyIsMovedAndTheRestAreLeft() {
        func animated(_ property: AnimatedProperty) -> PictureInPictureSettings {
            settings.animated(
                by: [SourceAnimation(property: property, from: 0.9, to: 0.9, duration: 1, mode: .once)], elapsed: 1
            )
        }
        XCTAssertEqual(animated(.positionX).center.x, 0.9)
        XCTAssertEqual(animated(.positionY).center.y, 0.9)
        XCTAssertEqual(animated(.size).scale, 0.9)
        XCTAssertEqual(animated(.rotation).rotation, 0.9)
        XCTAssertEqual(animated(.tilt).tilt, 0.9)
        XCTAssertEqual(animated(.swing).swing, 0.9)
        XCTAssertEqual(animated(.swing).scale, 0.4)
        XCTAssertEqual(settings.animated(by: [], elapsed: 3), settings)
    }

    func testCurrentValuesCanBeRead() {
        let turned = PictureInPictureSettings(
            center: CGPoint(x: 0.1, y: 0.2), scale: 0.3, rotation: 4, tilt: 5, swing: 6
        )
        XCTAssertEqual(AnimatedProperty.allCases.map(turned.value(of:)), [0.1, 0.2, 0.3, 4, 5, 6])
        XCTAssertTrue(turned.isTurnedInSpace)
        XCTAssertFalse(settings.isTurnedInSpace)
    }

    func testStartersSuitTheirProperty() {
        let spin = SourceAnimation.starter(for: .swing, around: 12)
        XCTAssertEqual([spin.from, spin.to], [0, 360])
        XCTAssertEqual(spin.mode, .loop)
        XCTAssertEqual(spin.duration, SourceAnimation.defaultDuration)
        XCTAssertEqual(SourceAnimation.starter(for: .rotation, around: 0).to, 360)
        XCTAssertEqual(SourceAnimation.starter(for: .tilt, around: 0).to, 360)

        let slide = SourceAnimation.starter(for: .positionX, around: 0.5)
        XCTAssertEqual(slide.from, 0.4, accuracy: 0.0001)
        XCTAssertEqual(slide.to, 0.6, accuracy: 0.0001)
        XCTAssertEqual(slide.mode, .backAndForth)
        XCTAssertEqual(SourceAnimation.starter(for: .positionY, around: 0.5).mode, .backAndForth)

        let swell = SourceAnimation.starter(for: .size, around: 0.4)
        XCTAssertEqual([swell.from, swell.to], [0.4, 0.4 * 1.5])
    }

    func testSettingsWithTurnsRoundTripAndOlderOnesLoadFlat() throws {
        let turned = PictureInPictureSettings(center: CGPoint(x: 0.1, y: 0.2), scale: 0.3, rotation: 4, tilt: 5, swing: 6)
        let data = try JSONEncoder().encode(turned)
        XCTAssertEqual(try JSONDecoder().decode(PictureInPictureSettings.self, from: data), turned)

        let older = #"{"center":[0.5,0.5],"scale":0.4,"rotation":10}"#
        let loaded = try JSONDecoder().decode(PictureInPictureSettings.self, from: Data(older.utf8))
        XCTAssertEqual(loaded, PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5), scale: 0.4, rotation: 10))
    }

    func testAStepKeepsItsLookWhenCopiedAndSaved() throws {
        let animation = SourceAnimation(property: .swing, from: 0, to: 360)
        let item = ChainItem(
            content: .source(.colorBars), pictureInPicture: settings,
            adjustments: SourceAdjustments(gamma: 1.4), animations: [animation]
        )
        let copy = item.duplicated()
        XCTAssertEqual(copy.adjustments, item.adjustments)
        XCTAssertEqual(copy.animations?.map(\.property), [.swing])
        XCTAssertNotEqual(copy.animations?.first?.id, animation.id)

        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(ChainItem.self, from: data), item)
    }
}

final class PerspectiveTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 100, width: 200, height: 100)

    private func corners(rotation: Double = 0, tilt: Double = 0, swing: Double = 0) -> Quadrilateral {
        Perspective.corners(of: frame, rotation: rotation, tilt: tilt, swing: swing, canvasWidth: 1000)
    }

    private func assertEqual(_ point: CGPoint, _ x: CGFloat, _ y: CGFloat, line: UInt = #line) {
        XCTAssertEqual(point.x, x, accuracy: 0.001, line: line)
        XCTAssertEqual(point.y, y, accuracy: 0.001, line: line)
    }

    func testAnUnturnedPictureKeepsItsCorners() {
        let flat = corners()
        assertEqual(flat.topLeft, 100, 200)
        assertEqual(flat.topRight, 300, 200)
        assertEqual(flat.bottomRight, 300, 100)
        assertEqual(flat.bottomLeft, 100, 100)
    }

    func testRotationTurnsItClockwiseInItsOwnPlane() {
        let quarter = corners(rotation: 90)
        // The top left corner swings round to the top right.
        assertEqual(quarter.topLeft, 250, 250)
        assertEqual(quarter.topRight, 250, 50)
    }

    func testSwingNarrowsThePictureAndShrinksItsFarSide() {
        let swung = corners(swing: 60)
        XCTAssertLessThan(swung.topRight.x - swung.topLeft.x, 200, "narrower seen at an angle")
        let nearHeight = swung.topLeft.y - swung.bottomLeft.y
        let farHeight = swung.topRight.y - swung.bottomRight.y
        XCTAssertGreaterThan(nearHeight, farHeight, "the side swung away looks shorter")
    }

    func testTiltShortensThePictureAndNarrowsItsFarEdge() {
        let tilted = corners(tilt: 60)
        XCTAssertLessThan(tilted.topLeft.y - tilted.bottomLeft.y, 100)
        XCTAssertLessThan(tilted.topRight.x - tilted.topLeft.x, tilted.bottomRight.x - tilted.bottomLeft.x)
    }

    func testAHugePictureSwungRoundStaysInFrontOfTheEye() {
        let huge = Perspective.corners(
            of: CGRect(x: 0, y: 0, width: 100_000, height: 100), rotation: 0, tilt: 0, swing: -89, canvasWidth: 100
        )
        XCTAssertTrue(huge.topRight.x.isFinite)
        XCTAssertTrue(huge.topLeft.x.isFinite)
    }

    func testAQuadrilateralKeepsItsCorners() {
        let quad = Quadrilateral(
            topLeft: CGPoint(x: 1, y: 2), topRight: CGPoint(x: 3, y: 4),
            bottomRight: CGPoint(x: 5, y: 6), bottomLeft: CGPoint(x: 7, y: 8)
        )
        XCTAssertEqual(quad.bottomLeft, CGPoint(x: 7, y: 8))
        XCTAssertEqual(quad.topRight, CGPoint(x: 3, y: 4))
    }
}
