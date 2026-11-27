import CamTwistCore
import CoreImage
import Metal
import XCTest
@testable import CamTwistRendering

private final class FakeTracker: FaceTracking {
    var answer: FaceLandmarks?
    func face(in image: CIImage) -> FaceLandmarks? { answer }
}

private final class FakeCharacter: CharacterDrawing {
    var answer: CIImage?
    private(set) var asked: [FaceExpression] = []
    func picture(of expression: FaceExpression) -> CIImage? {
        asked.append(expression)
        return answer
    }
}

private final class FakeStage: ToyFigureStaging {
    var answer: CIImage?
    private(set) var poses: [ToyFigurePose] = []
    private(set) var faces: [CGImage] = []
    func picture(face: CGImage, pose: ToyFigurePose) -> CIImage? {
        faces.append(face)
        poses.append(pose)
        return answer
    }
}

final class CharacterEffectTests: XCTestCase {
    private let canvas = CGSize(width: 320, height: 180)
    private let access = makePixelAccess()
    private var bounds: CGRect { CGRect(origin: .zero, size: canvas) }
    private var picture: CIImage { CIImage(color: .blue).cropped(to: bounds) }
    /// How many frames the followers in these tests hold a face that has gone.
    private let patience = 10
    private let tuning = EffectTuning(
        slowMotionFramesPerSecond: 12, slowMotionLongestLag: 2.5, slowMotionWidestFrame: 1280, faceFramesHeld: 10,
        characterSmoothing: 0.6, wornSmoothing: 0.85, framingSmoothing: 0.06
    )

    /// Red, green, blue and alpha at a point counted from the bottom left, as pictures are.
    private func pixel(_ image: CIImage, x: Int, y: Int) -> [Int] {
        let whole = image.composited(over: CIImage(color: .clear).cropped(to: bounds)).cropped(to: bounds)
        let bytes = access.rgba(of: whole, width: 320, height: 180)
        let row = 179 - y
        return bytes[(row * 320 + x) * 4..<(row * 320 + x) * 4 + 4].map(Int.init)
    }

    private func isYellow(_ color: [Int]) -> Bool { color[0] > 170 && color[1] > 130 && color[2] < 120 && color[3] == 255 }
    private func isRed(_ color: [Int]) -> Bool { color[0] > 150 && color[1] < 80 && color[2] < 80 && color[3] == 255 }
    private func isBlue(_ color: [Int]) -> Bool { color[0] < 30 && color[1] < 30 && color[2] > 220 }
    private func isDark(_ color: [Int]) -> Bool { color[0] < 120 && color[1] < 90 && color[2] < 90 && color[3] == 255 }
    private func isGreen(_ color: [Int]) -> Bool { color[1] > 100 && color[1] > color[0] + 30 && color[1] > color[2] + 30 }

    /// A face found in the picture, 40 across and 50 tall, with its middle at (60, 85).
    private var foundFace: FaceLandmarks {
        func eye(_ x: CGFloat) -> [CGPoint] {
            [CGPoint(x: x - 3, y: 85), CGPoint(x: x + 3, y: 85), CGPoint(x: x, y: 86), CGPoint(x: x, y: 84)]
        }
        return FaceLandmarks(
            box: CGRect(x: 40, y: 60, width: 40, height: 50),
            eyes: [eye(50), eye(70)],
            brows: [[CGPoint(x: 50, y: 92)], [CGPoint(x: 70, y: 92)]],
            nose: [CGPoint(x: 60, y: 75)],
            outerLips: [CGPoint(x: 52, y: 66), CGPoint(x: 68, y: 66)],
            innerLips: [CGPoint(x: 60, y: 66)]
        )
    }

    private func follower(
        seeing tracker: FaceTracking = FakeTracker(), from start: FaceExpression
    ) -> FaceFollower {
        FaceFollower(
            tracker: tracker, smoother: ExpressionSmoother(start: start, share: 0.6), reader: MeasuringFaceReader(),
            patience: patience
        )
    }

    private func face(_ centre: CGPoint = CGPoint(x: 160, y: 110)) -> FaceExpression {
        FaceExpression(centre: centre, height: 40)
    }

    // MARK: Following a face

    func testAFollowerReadsTheFaceItIsShownAndHoldsItWhenItGoes() {
        let tracker = FakeTracker()
        let follower = follower(seeing: tracker, from: face())
        XCTAssertEqual(follower.expression(in: picture), face(), "nobody yet")
        XCTAssertTrue(follower.isInSight, "and not for long enough to say nobody is coming")

        tracker.answer = foundFace
        let found = follower.expression(in: picture)
        XCTAssertEqual(found.centre, CGPoint(x: 60, y: 85))
        XCTAssertEqual(found.height, 50)
        XCTAssertEqual(found.crown.x, 60, accuracy: 0.001)
        XCTAssertEqual(found.crown.y, 85 + 19 * 1.7, accuracy: 0.001, "the top of the head, up from the eyes")

        tracker.answer = nil
        for _ in 0..<patience {
            XCTAssertEqual(follower.expression(in: picture), found, "held while it is out of view")
            XCTAssertTrue(follower.isInSight)
        }
        _ = follower.expression(in: picture)
        XCTAssertFalse(follower.isInSight, "gone for too long")

        tracker.answer = foundFace
        _ = follower.expression(in: picture)
        XCTAssertTrue(follower.isInSight, "and back")
    }

    func testAPosedFaceStaysInSightUntilARealOneIsSeen() {
        let tracker = FakeTracker()
        let follower = follower(seeing: tracker, from: face())
        let posed = face(CGPoint(x: 30, y: 40))
        follower.rest(at: posed)
        for _ in 0...patience {
            XCTAssertEqual(follower.expression(in: picture), posed)
        }
        XCTAssertTrue(follower.isInSight, "a preview's face never goes")

        tracker.answer = foundFace
        _ = follower.expression(in: picture)
        tracker.answer = nil
        for _ in 0...patience { _ = follower.expression(in: picture) }
        XCTAssertFalse(follower.isInSight, "once a real face has been seen, it can be lost like any other")
    }

    // MARK: The effect

    func testTheCharacterIsDrawnOverThePictureOrAPlainBackdrop() {
        let character = FakeCharacter()
        character.answer = CIImage(color: .green).cropped(to: CGRect(x: 100, y: 50, width: 50, height: 50))
        let effect = CharacterEffect(canvas: canvas, follower: follower(from: face()), character: character)

        let usual = effect.apply(to: picture, time: 0)
        XCTAssertEqual(Array(pixel(usual, x: 120, y: 70).prefix(3)), [0, 255, 0], "the character")
        XCTAssertTrue(isBlue(pixel(usual, x: 10, y: 10)), "the picture round it")
        XCTAssertEqual(character.asked.last?.height, 40)

        effect.setValues([CharacterEffect.sizeKey: .number(2)])
        _ = effect.apply(to: picture, time: 0)
        XCTAssertEqual(character.asked.last?.height, 80, "twice the size")

        effect.setValues([CharacterEffect.plainBackdropKey: .boolean(true)])
        XCTAssertEqual(pixel(effect.apply(to: picture, time: 0), x: 10, y: 10).map { $0 > 100 }, [true, true, true, true])
        effect.setValues([
            CharacterEffect.plainBackdropKey: .boolean(true),
            CharacterEffect.backdropColorKey: .color(red: 1, green: 0, blue: 0, alpha: 1),
        ])
        let onRed = effect.apply(to: picture, time: 0)
        XCTAssertEqual(Array(pixel(onRed, x: 10, y: 10).prefix(3)), [255, 0, 0])
        XCTAssertEqual(Array(pixel(onRed, x: 120, y: 70).prefix(3)), [0, 255, 0])

        character.answer = nil
        effect.setValues([:])
        let plain = picture
        XCTAssertEqual(effect.apply(to: plain, time: 0), plain, "no character, so the picture passes through")
        XCTAssertEqual(CharacterEffect.parameters.map(\.key), ["Size", "Plain_Backdrop", "Backdrop_Color"])

        effect.rest(at: face(CGPoint(x: 5, y: 6)))
        _ = effect.apply(to: picture, time: 0)
        XCTAssertEqual(character.asked.last?.centre, CGPoint(x: 5, y: 6), "a preview can stand it somewhere")
    }

    // MARK: The toy figure

    func testTheToyFigureTurnsAnExpressionIntoAPoseAndAPaintedFace() throws {
        let stage = FakeStage()
        let staged = picture
        stage.answer = staged
        let figure = ToyFigure(stage: stage, painter: ToyFacePainter(height: 100))
        let expression = FaceExpression(centre: CGPoint(x: 10, y: 20), height: 40, roll: 0.3, turn: 1, nod: -1)

        XCTAssertEqual(figure.picture(of: expression), staged)
        XCTAssertEqual(stage.poses.last, ToyFigurePose(
            centre: CGPoint(x: 10, y: 20), headHeight: 60, yaw: 0.9, pitch: -0.7, roll: 0.3
        ))
        let painted = try XCTUnwrap(stage.faces.last)
        XCTAssertEqual(painted.height, 200, "drawn with twice the detail")
        XCTAssertEqual(painted.width, 240, "a third of the way round the head")

        XCTAssertNil(ToyFigure(stage: nil, painter: ToyFacePainter(height: 100)).picture(of: expression))
        XCTAssertNil(ToyFigure(stage: stage, painter: ToyFacePainter(height: 0)).picture(of: expression))
        XCTAssertEqual(ToyFacePainter.usualHeight, 400)
    }

    func testThePaintedFaceFollowsTheEyesAndMouth() throws {
        let painter = ToyFacePainter(height: 100)
        /// A point on the painted face, in head heights from its middle.
        func color(_ expression: FaceExpression, x: CGFloat, y: CGFloat) throws -> [Int] {
            let face = try XCTUnwrap(painter.face(for: expression))
            let image = CIImage(cgImage: face)
            let bytes = access.rgba(of: image, width: face.width, height: face.height)
            let column = Int((x + 0.6) * 200), row = Int((0.5 - y) * 200)
            return bytes[(row * face.width + column) * 4..<(row * face.width + column) * 4 + 4].map(Int.init)
        }
        let centre = CGPoint(x: 0, y: 0)
        let awake = FaceExpression(centre: centre, height: 1)
        let winking = FaceExpression(centre: centre, height: 1, leftEyeOpen: 0)
        let talking = FaceExpression(centre: centre, height: 1, mouthOpen: 1)

        XCTAssertTrue(isYellow(try color(awake, x: 0, y: 0.4)), "the forehead")
        XCTAssertTrue(isDark(try color(awake, x: -0.2, y: 0.15)), "an open eye is round")
        XCTAssertTrue(isYellow(try color(winking, x: -0.2, y: 0.15)), "a shut one is a line")
        XCTAssertTrue(isDark(try color(winking, x: 0.2, y: 0.15)), "and the other is still open")
        XCTAssertGreaterThan(try color(awake, x: -0.18, y: 0.125)[2], 150, "an open eye catches the light")
        XCTAssertTrue(isYellow(try color(awake, x: 0, y: -0.32)), "a closed mouth is a line")
        XCTAssertFalse(isYellow(try color(talking, x: 0, y: -0.32)), "an open one drops")
    }

    func testWithNoGraphicsCardThereIsNoFigureStage() {
        XCTAssertNil(SceneKitToyFigureStage(device: nil, canvas: canvas, model: ToyFigureModel(canvas: canvas)))
    }

    func testTheSolidFigureStandsWhereItIsPutAndItsHeadTurns() throws {
        let stage = try XCTUnwrap(SceneKitToyFigureStage(
            device: MTLCreateSystemDefaultDevice(), canvas: canvas, model: ToyFigureModel(canvas: canvas)
        ))
        let painter = ToyFacePainter(height: 200)
        /// A head 60 points tall with its middle at (160, 110), winking its left eye.
        func drawn(yaw: CGFloat = 0, pitch: CGFloat = 0, roll: CGFloat = 0, mouthOpen: CGFloat = 0) throws -> CIImage {
            let expression = FaceExpression(centre: .zero, height: 1, leftEyeOpen: 0, mouthOpen: mouthOpen)
            return try XCTUnwrap(stage.picture(
                face: try XCTUnwrap(painter.face(for: expression)),
                pose: ToyFigurePose(centre: CGPoint(x: 160, y: 110), headHeight: 60, yaw: yaw, pitch: pitch, roll: roll)
            ))
        }

        let upright = try drawn()
        XCTAssertEqual(upright.extent, bounds)
        XCTAssertTrue(isYellow(pixel(upright, x: 160, y: 132)), "its forehead")
        XCTAssertTrue(isYellow(pixel(upright, x: 160, y: 146)), "the stud on top")
        XCTAssertTrue(isRed(pixel(upright, x: 160, y: 30)), "its shirt")
        XCTAssertTrue(isRed(pixel(upright, x: 101, y: 30)) && isRed(pixel(upright, x: 219, y: 30)), "an arm each side")
        XCTAssertEqual(pixel(upright, x: 5, y: 175)[3], 0, "clear around it")
        XCTAssertTrue(isYellow(pixel(upright, x: 148, y: 119)), "the left eye is shut")
        XCTAssertTrue(isDark(pixel(upright, x: 172, y: 119)), "the right is open, so the face is the right way round")
        XCTAssertFalse(isYellow(pixel(try drawn(mouthOpen: 1), x: 160, y: 90)), "and the right way up")

        XCTAssertTrue(isYellow(pixel(try drawn(yaw: 0.9), x: 172, y: 119)), "turned, the eye has moved on round the head")
        XCTAssertTrue(isYellow(pixel(try drawn(pitch: -0.7), x: 172, y: 119)), "bowed, the top of the head shows there")
        let leaning = try drawn(roll: .pi / 2)
        XCTAssertTrue(isYellow(pixel(leaning, x: 128, y: 110)), "leant over, the stud is out to the left")
        XCTAssertEqual(pixel(leaning, x: 160, y: 146)[3], 0, "and no longer on top")
        XCTAssertTrue(isRed(pixel(leaning, x: 199, y: 60)), "while the body stays upright, under the neck")
        XCTAssertTrue(isYellow(pixel(leaning, x: 197, y: 110)), "which still joins the head to the shirt")
    }

    // MARK: The antennae

    func testAntennaeSproutFromTheTopOfTheHeadAndFollowIt() {
        func drawn(_ expression: FaceExpression, values: [String: EffectValue] = [:]) -> CIImage {
            let effect = WornEffect(canvas: canvas, follower: follower(from: expression), item: Antennae())
            effect.setValues(values)
            return effect.apply(to: picture, time: 0)
        }
        // A face 40 tall, so the top of its head is at (160, 78).
        let head = CGPoint(x: 160, y: 50)
        let upright = drawn(face(head))
        XCTAssertEqual(upright.extent, bounds)
        XCTAssertTrue(isGreen(pixel(upright, x: 143, y: 97)), "a ball on the left")
        XCTAssertTrue(isGreen(pixel(upright, x: 178, y: 97)), "and one on the right")
        XCTAssertTrue(isBlue(pixel(upright, x: 160, y: 97)), "with the picture between them")
        XCTAssertTrue(isBlue(pixel(upright, x: 126, y: 116)))

        let red = drawn(face(head), values: [Antennae.colorKey: .color(red: 1, green: 0, blue: 0, alpha: 1)])
        XCTAssertEqual(Array(pixel(red, x: 143, y: 97).prefix(3)), [255, 0, 0])
        let large = drawn(face(head), values: [WornEffect.sizeKey: .number(2)])
        XCTAssertTrue(isGreen(pixel(large, x: 126, y: 116)), "twice the size reaches twice as far")
        XCTAssertTrue(isGreen(pixel(large, x: 178, y: 87)), "on stalks from the head")

        let turned = drawn(FaceExpression(centre: head, height: 40, turn: 1, nod: 1))
        XCTAssertTrue(isGreen(pixel(turned, x: 149, y: 100)), "they lean the way the head faces and lift as it looks up")
        let leaning = drawn(FaceExpression(centre: head, height: 40, roll: .pi / 2))
        XCTAssertTrue(isGreen(pixel(leaning, x: 140, y: 60)), "and lean over with the head")
        let elsewhere = drawn(FaceExpression(centre: head, height: 40, crown: CGPoint(x: 60, y: 100)))
        XCTAssertTrue(isGreen(pixel(elsewhere, x: 43, y: 119)), "they grow from the top of the head, wherever that is")

        let plain = picture
        let gone = WornEffect(canvas: canvas, follower: follower(from: face(CGPoint(x: -5000, y: -5000))), item: Antennae())
        XCTAssertEqual(gone.apply(to: plain, time: 0), plain, "a head outside the picture has none to show")
        XCTAssertEqual(WornEffect.parameters(for: Antennae()).map(\.key), ["Size", "Color"])
    }

    // MARK: The sunglasses

    func testPixelSunglassesSitOnTheEyes() {
        // Eyes 50 apart, so each pixel of the glasses is 5 points across.
        let wearer = FaceExpression(centre: CGPoint(x: 160, y: 80), height: 40, eyeLine: CGPoint(x: 160, y: 90), eyeSpan: 50)
        func drawn(_ expression: FaceExpression, values: [String: EffectValue] = [:]) -> CIImage {
            let effect = WornEffect(canvas: canvas, follower: follower(from: expression), item: PixelSunglasses())
            effect.setValues(values)
            return effect.apply(to: picture, time: 0)
        }
        func isBlack(_ color: [Int]) -> Bool { color[0] < 40 && color[1] < 40 && color[2] < 40 }
        func isWhite(_ color: [Int]) -> Bool { color[0] > 220 && color[1] > 220 && color[2] > 220 }

        let worn = drawn(wearer)
        XCTAssertEqual(worn.extent, bounds)
        XCTAssertTrue(isBlack(pixel(worn, x: 107, y: 100)), "the bar across the top, past the left lens")
        XCTAssertTrue(isBlack(pixel(worn, x: 132, y: 90)), "the left lens, over the eye")
        XCTAssertTrue(isBlack(pixel(worn, x: 192, y: 90)), "and the right")
        XCTAssertTrue(isWhite(pixel(worn, x: 122, y: 95)), "a glint")
        XCTAssertTrue(isBlue(pixel(worn, x: 107, y: 95)), "nothing under the bar's end")
        XCTAssertTrue(isBlue(pixel(worn, x: 157, y: 90)), "nor between the lenses")

        let red = drawn(wearer, values: [PixelSunglasses.colorKey: .color(red: 1, green: 0, blue: 0, alpha: 1)])
        XCTAssertEqual(Array(pixel(red, x: 132, y: 90).prefix(3)), [255, 0, 0])
        XCTAssertTrue(isWhite(pixel(red, x: 122, y: 95)), "the glint stays white")
        let large = drawn(wearer, values: [WornEffect.sizeKey: .number(2)])
        XCTAssertTrue(isBlack(pixel(large, x: 52, y: 110)), "twice the size is twice as wide")

        var leaning = wearer
        leaning.roll = .pi / 2
        XCTAssertTrue(isBlack(pixel(drawn(leaning), x: 160, y: 62)), "they lean with the head")
        XCTAssertEqual(WornEffect.parameters(for: PixelSunglasses()).map(\.key), ["Size", "Color"])
    }

    // MARK: The moustache

    func testTheMoustacheSitsOnTheLipAndTakesItsColour() {
        // Eyes 50 apart, so the moustache is about 62 across.
        let wearer = FaceExpression(
            centre: CGPoint(x: 160, y: 80), height: 40, eyeLine: CGPoint(x: 160, y: 90), eyeSpan: 50,
            upperLip: CGPoint(x: 160, y: 60)
        )
        func drawn(_ expression: FaceExpression, values: [String: EffectValue] = [:]) -> CIImage {
            let effect = WornEffect(canvas: canvas, follower: follower(from: expression), item: Moustache())
            effect.setValues(values)
            return effect.apply(to: picture, time: 0)
        }
        func isBlack(_ color: [Int]) -> Bool { color[0] < 40 && color[1] < 40 && color[2] < 40 }

        let worn = drawn(wearer)
        XCTAssertTrue(isBlack(pixel(worn, x: 160, y: 61)), "black, under the middle of the nose")
        XCTAssertTrue(isBlack(pixel(worn, x: 172, y: 64)), "the right side")
        XCTAssertTrue(isBlack(pixel(worn, x: 148, y: 64)), "and the left")
        XCTAssertTrue(isBlue(pixel(worn, x: 160, y: 70)), "nothing above it")
        XCTAssertTrue(isBlue(pixel(worn, x: 200, y: 61)), "nor past its tips")

        let red = drawn(wearer, values: [Moustache.colorKey: .color(red: 1, green: 0, blue: 0, alpha: 1)])
        XCTAssertEqual(Array(pixel(red, x: 172, y: 64).prefix(3)), [255, 0, 0])

        var leaning = wearer
        leaning.roll = .pi / 2
        XCTAssertTrue(isBlack(pixel(drawn(leaning), x: 156, y: 72)), "it leans with the head")
        XCTAssertEqual(WornEffect.parameters(for: Moustache()).map(\.key), ["Size", "Color"])
    }

    // MARK: Follow me

    func testFollowMeZoomsInOnTheFaceAndKeepsThePictureEdgesOutOfFrame() {
        // A red spot where the face is.
        let spot = CIImage(color: .red).cropped(to: CGRect(x: 58, y: 83, width: 4, height: 4)).composited(over: picture)
        func framed(on centre: CGPoint, values: [String: EffectValue] = [:]) -> CIImage {
            let effect = FollowMeEffect(canvas: canvas, follower: follower(from: face(centre)))
            effect.setValues(values)
            return effect.apply(to: spot, time: 0)
        }
        // Twice as close: a frame 160 by 90, its middle 9 below the face,
        // held at the left edge. The spot lands at twice its place in it.
        let close = framed(on: CGPoint(x: 60, y: 85), values: [FollowMeEffect.zoomKey: .number(2)])
        XCTAssertEqual(close.extent, bounds)
        XCTAssertTrue(isRed(pixel(close, x: 120, y: 108)), "the face, zoomed in")
        XCTAssertTrue(isBlue(pixel(close, x: 120, y: 140)), "with nothing else red")
        // Over at the far corner the frame stops at the picture's edges.
        let corner = framed(on: CGPoint(x: 320, y: 180), values: [FollowMeEffect.zoomKey: .number(2)])
        XCTAssertTrue(isBlue(pixel(corner, x: 120, y: 108)), "the spot is out of a frame held in the top right")
        XCTAssertEqual(corner.extent, bounds)
        // At no zoom the picture is as it was.
        XCTAssertTrue(isRed(pixel(framed(on: CGPoint(x: 60, y: 85), values: [FollowMeEffect.zoomKey: .number(1)]), x: 60, y: 85)))
        XCTAssertEqual(FollowMeEffect.parameters.map(\.key), ["Zoom"])
    }

    func testFollowMeIsFramedOnThePreviewsSampleFigure() {
        let effect = FollowMeEffect(canvas: canvas, follower: follower(from: face()))
        effect.rest(at: face(CGPoint(x: 60, y: 85)))
        let spot = CIImage(color: .red).cropped(to: CGRect(x: 58, y: 83, width: 4, height: 4)).composited(over: picture)
        effect.setValues([FollowMeEffect.zoomKey: .number(2)])
        XCTAssertTrue(isRed(pixel(effect.apply(to: spot, time: 0), x: 120, y: 108)))
    }

    // MARK: Big eyes

    func testBigEyesBulgeThePictureRoundEachEyeAndNowhereElse() {
        // Red rising from left to right, so a stretched part shows as a changed shade.
        let shaded = FilterOutput.image(named: CIFilterName.linearGradient, parameters: [
            CIInputKey.point0: CIVector(x: 0, y: 0), CIInputKey.color0: CIColor(red: 0, green: 0, blue: 0),
            CIInputKey.point1: CIVector(x: 320, y: 0), CIInputKey.color1: CIColor(red: 1, green: 0, blue: 0),
        ], fallback: picture).cropped(to: bounds)
        // Eyes 80 apart: one at (120, 90), the other at (200, 90).
        let wearer = FaceExpression(centre: CGPoint(x: 160, y: 80), height: 100, eyeLine: CGPoint(x: 160, y: 90), eyeSpan: 80)
        func drawn(_ expression: FaceExpression, amount: Double? = nil) -> CIImage {
            let effect = BigEyesEffect(canvas: canvas, follower: follower(from: expression))
            if let amount { effect.setValues([BigEyesEffect.amountKey: .number(amount)]) }
            return effect.apply(to: shaded, time: 0)
        }
        func red(_ image: CIImage, x: Int, y: Int) -> Int { pixel(image, x: x, y: y)[0] }

        let big = drawn(wearer)
        XCTAssertEqual(big.extent, bounds)
        // Stretched from its middle, each eye shows what was nearer that middle.
        XCTAssertLessThan(red(big, x: 132, y: 90), red(shaded, x: 132, y: 90), "right of the left eye")
        XCTAssertGreaterThan(red(big, x: 108, y: 90), red(shaded, x: 108, y: 90), "left of it")
        XCTAssertLessThan(red(big, x: 212, y: 90), red(shaded, x: 212, y: 90), "and the same at the right eye")
        XCTAssertEqual(red(big, x: 20, y: 20), red(shaded, x: 20, y: 20), accuracy: 1, "the rest is untouched")
        XCTAssertEqual(red(big, x: 160, y: 90), red(shaded, x: 160, y: 90), accuracy: 1, "even between the eyes")

        let bigger = drawn(wearer, amount: 1)
        XCTAssertLessThan(red(bigger, x: 132, y: 90), red(big, x: 132, y: 90), "more of it stretches further")
        XCTAssertEqual(red(drawn(wearer, amount: 0), x: 132, y: 90), red(shaded, x: 132, y: 90), accuracy: 1)

        // With the head on its side the eyes are one above the other, at (160, 50) and (160, 130).
        var leaning = wearer
        leaning.roll = .pi / 2
        let turned = drawn(leaning)
        XCTAssertLessThan(red(turned, x: 172, y: 130), red(shaded, x: 172, y: 130))
        XCTAssertEqual(red(turned, x: 132, y: 90), red(shaded, x: 132, y: 90), accuracy: 1)
        XCTAssertEqual(BigEyesEffect.parameters.map(\.key), ["Amount"])
    }

    func testBigEyesLeaveThePictureAloneWithNobodyInItUnlessPosed() {
        let effect = BigEyesEffect(canvas: canvas, follower: follower(from: face()))
        let plain = picture
        for _ in 0..<patience { _ = effect.apply(to: plain, time: 0) }
        XCTAssertEqual(effect.apply(to: plain, time: 0), plain, "nobody there, no eyes to enlarge")
        effect.rest(at: face())
        XCTAssertNotEqual(effect.apply(to: plain, time: 0), plain, "a preview's face has them")
    }

    func testAntennaeGoWhenNobodyHasBeenSeenForAWhile() {
        let effect = WornEffect(canvas: canvas, follower: follower(from: face(CGPoint(x: 160, y: 50))), item: Antennae())
        let plain = picture
        for _ in 0..<patience {
            XCTAssertNotEqual(effect.apply(to: plain, time: 0), plain)
        }
        XCTAssertEqual(effect.apply(to: plain, time: 0), plain, "nobody there, nothing to wear them")

        effect.rest(at: face(CGPoint(x: 160, y: 50)))
        XCTAssertTrue(isGreen(pixel(effect.apply(to: plain, time: 0), x: 143, y: 97)), "a preview's head keeps them")
    }

    func testAPreviewStandsTheEffectOnTheSampleFiguresHead() throws {
        struct Factory: ImageEffectFactory {
            let follower: FaceFollower
            func makeEffect(named name: String, canvas: CGSize) -> ImageEffect? {
                WornEffect(canvas: canvas, follower: follower, item: Antennae())
            }
        }
        struct NoTransitions: TransitionFactory {
            func makeTransition(named name: String, canvas: CGSize) -> TransitionEffect? { nil }
        }
        let sample = EffectThumbnailer.sampleFace(size: canvas)
        XCTAssertEqual(sample.centre.x, 115.2, accuracy: 0.001)
        XCTAssertEqual(sample.centre.y, 115.2, accuracy: 0.001)
        XCTAssertEqual(sample.height, 45.9, accuracy: 0.001)

        let thumbnailer = EffectThumbnailer(
            factory: Factory(follower: follower(from: face(CGPoint(x: 300, y: 20)))), transitions: NoTransitions(),
            size: canvas
        )
        let thumbnail = CIImage(cgImage: try XCTUnwrap(thumbnailer.thumbnail(forEffectNamed: Antennae.name)))
        XCTAssertTrue(isGreen(pixel(thumbnail, x: 96, y: 169)), "the antennae are over the figure's head")
    }

    // MARK: The real things

    func testTheBuiltInEffectsAreMadeWithTheTuningTheyAreGiven() throws {
        // A face that is let go the moment it is lost: with nobody in the
        // picture the antennae are there for the first frame and gone by the second.
        var impatient = tuning
        impatient.faceFramesHeld = 0
        let antennae = try XCTUnwrap(NativeEffect.characters(tuning: impatient, tracker: RenderingSupplies.system().makeFaceTracker).first { $0.name == Antennae.name })
        let effect = antennae.make(canvas)
        let plain = picture
        XCTAssertEqual(effect.apply(to: plain, time: 0), plain, "nobody is held at all")

        let patient = try XCTUnwrap(NativeEffect.characters(tuning: tuning, tracker: RenderingSupplies.system().makeFaceTracker).first { $0.name == Antennae.name })
        XCTAssertNotEqual(patient.make(canvas).apply(to: plain, time: 0), plain, "with the usual tuning they wait")
    }

    func testTheRealEffectsDrawOnAPictureWithNobodyInIt() {
        // The system finds no face in a plain picture: the figure and the
        // antennae wait in the middle.
        XCTAssertEqual(NativeEffect.characters(tuning: tuning, tracker: RenderingSupplies.system().makeFaceTracker).map(\.name), ["Toy Figure", "Alien Antennae", "Pixel Sunglasses", "Moustache", "Big Eyes", "Follow Me"])
        for character in NativeEffect.characters(tuning: tuning, tracker: RenderingSupplies.system().makeFaceTracker) {
            let image = character.make(canvas).apply(to: picture, time: 0)
            XCTAssertEqual(image.extent, bounds, character.name)
            // Big Eyes and Follow Me only reshape the picture, which a plain one does not show.
            let marks = [(160, 130), (137, 172), (160, 121), (160, 96)].map { pixel(image, x: $0.0, y: $0.1) }
            let reshapes = [BigEyesEffect.name, FollowMeEffect.name].contains(character.name)
            XCTAssertEqual(marks.allSatisfy(isBlue), reshapes, character.name)
        }
    }
}
