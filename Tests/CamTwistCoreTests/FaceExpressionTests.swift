import CoreGraphics
import XCTest
@testable import CamTwistCore

final class FaceExpressionTests: XCTestCase {
    private let accuracy: CGFloat = 1e-6
    /// The top of the head of the usual drawn face.
    private let crown = CGPoint(x: 500, y: 587)
    /// The point between its eyes, which are 100 apart.
    private let eyes = CGPoint(x: 500, y: 400)

    /// A face drawn from measures in eye distances, the way the reader
    /// takes them, then leant over and put somewhere in a picture.
    private struct Drawn {
        var span: CGFloat = 100
        var middle = CGPoint(x: 500, y: 400)
        var roll: CGFloat = 0
        var leftEye: CGFloat = 0.28
        var rightEye: CGFloat = 0.28
        var leftBrow: CGFloat = 0.35
        var rightBrow: CGFloat = 0.35
        var nose = CGPoint(x: 0, y: -0.5)
        var mouthWidth: CGFloat = 0.8
        var lipGap: CGFloat = 0.06
        var eyeWidth: CGFloat = 0.3

        private func placed(_ points: [CGPoint]) -> [CGPoint] {
            let place = CGAffineTransform(scaleX: span, y: span)
                .concatenating(CGAffineTransform(rotationAngle: roll))
                .concatenating(CGAffineTransform(translationX: middle.x, y: middle.y))
            return points.map { $0.applying(place) }
        }

        private func eye(at x: CGFloat, openness: CGFloat) -> [CGPoint] {
            let half = eyeWidth / 2, tall = eyeWidth * openness / 2
            return placed([
                CGPoint(x: x - half, y: 0), CGPoint(x: x + half, y: 0), CGPoint(x: x, y: tall), CGPoint(x: x, y: -tall),
            ])
        }

        private func brow(at x: CGFloat, lift: CGFloat) -> [CGPoint] {
            placed([CGPoint(x: x - 0.2, y: lift), CGPoint(x: x + 0.2, y: lift)])
        }

        var landmarks: FaceLandmarks {
            FaceLandmarks(
                box: CGRect(x: middle.x - 120, y: middle.y - 150, width: 240, height: 260),
                eyes: [eye(at: -0.5, openness: leftEye), eye(at: 0.5, openness: rightEye)],
                brows: [brow(at: -0.5, lift: leftBrow), brow(at: 0.5, lift: rightBrow)],
                nose: placed([CGPoint(x: nose.x - 0.1, y: nose.y), CGPoint(x: nose.x + 0.1, y: nose.y)]),
                outerLips: placed([CGPoint(x: -mouthWidth / 2, y: -1.1), CGPoint(x: mouthWidth / 2, y: -1.1)]),
                innerLips: placed([
                    CGPoint(x: -0.2, y: -1.1), CGPoint(x: 0.2, y: -1.1),
                    CGPoint(x: 0, y: -1.1 + lipGap / 2), CGPoint(x: 0, y: -1.1 - lipGap / 2),
                ])
            )
        }
    }

    private func read(_ face: Drawn, file: StaticString = #filePath, line: UInt = #line) throws -> FaceExpression {
        try XCTUnwrap(FaceExpressionReader.expression(of: face.landmarks), file: file, line: line)
    }

    private func assertClose(
        _ expression: FaceExpression, _ expected: FaceExpression, file: StaticString = #filePath, line: UInt = #line
    ) {
        let paths: [KeyPath<FaceExpression, CGFloat>] = [
            \.centre.x, \.centre.y, \.height, \.crown.x, \.crown.y, \.eyeLine.x, \.eyeLine.y, \.eyeSpan, \.roll, \.turn, \.nod, \.leftEyeOpen, \.rightEyeOpen,
            \.leftBrow, \.rightBrow, \.mouthOpen, \.smile,
        ]
        for path in paths {
            XCTAssertEqual(
                expression[keyPath: path], expected[keyPath: path], accuracy: accuracy, "\(path)", file: file, line: line
            )
        }
    }

    func testAFaceAtRestReadsAsCalmWithItsEyesOpen() throws {
        // The mouth is 1.1 eye distances below the eyes, so the top of the head is 1.87 above them.
        assertClose(try read(Drawn()), FaceExpression(centre: CGPoint(x: 500, y: 380), height: 260, crown: crown, eyeLine: eyes, eyeSpan: 100))
    }

    func testEachPartOfTheFaceMovesItsOwnMeasure() throws {
        var face = Drawn()
        face.leftEye = 0.14
        face.rightEye = 0.21
        face.leftBrow = 0.47
        face.rightBrow = 0.29
        face.nose = CGPoint(x: 0.15, y: -0.6)
        face.mouthWidth = 0.9
        face.lipGap = 0.28
        assertClose(try read(face), FaceExpression(
            centre: CGPoint(x: 500, y: 380), height: 260, crown: crown, eyeLine: eyes, eyeSpan: 100, turn: 0.5, nod: -0.5,
            leftEyeOpen: 0, rightEyeOpen: 0.5, leftBrow: 1, rightBrow: -0.5, mouthOpen: 0.5, smile: 0.5
        ))
    }

    func testMeasuresStopAtTheirEnds() throws {
        var face = Drawn()
        face.leftEye = 0.01
        face.rightEye = 0.9
        face.leftBrow = 0.9
        face.rightBrow = 0
        face.nose = CGPoint(x: -2, y: 2)
        face.mouthWidth = 0.1
        face.lipGap = 3
        assertClose(try read(face), FaceExpression(
            centre: CGPoint(x: 500, y: 380), height: 260, crown: crown, eyeLine: eyes, eyeSpan: 100, turn: -1, nod: 1,
            leftEyeOpen: 0, rightEyeOpen: 1, leftBrow: 1, rightBrow: -1, mouthOpen: 1, smile: -1
        ))
    }

    func testALeaningFaceOfAnySizeReadsTheSameApartFromItsLean() throws {
        var face = Drawn()
        face.span = 37
        face.roll = 0.4
        face.rightEye = 0.21
        face.leftBrow = 0.41
        let expression = try read(face)
        XCTAssertEqual(expression.roll, 0.4, accuracy: accuracy)
        XCTAssertEqual(expression.rightEyeOpen, 0.5, accuracy: accuracy)
        XCTAssertEqual(expression.leftBrow, 0.5, accuracy: accuracy)
        XCTAssertEqual(expression.turn, 0, accuracy: accuracy)
        // The top of the head is up the face's own upright, not the picture's.
        XCTAssertEqual(expression.crown.x, 500 - sin(0.4) * 69.19, accuracy: 0.001)
        XCTAssertEqual(expression.crown.y, 400 + cos(0.4) * 69.19, accuracy: 0.001)
        XCTAssertEqual(expression.eyeSpan, 37, accuracy: 0.001)
    }

    func testThePairsAreSortedByWhereTheySit() throws {
        var face = Drawn()
        face.leftEye = 0.14
        face.leftBrow = 0.47
        var marks = face.landmarks
        marks.eyes.reverse()
        marks.brows.reverse()
        let expression = try XCTUnwrap(FaceExpressionReader.expression(of: marks))
        XCTAssertEqual(expression.leftEyeOpen, 0, accuracy: accuracy)
        XCTAssertEqual(expression.rightEyeOpen, 1, accuracy: accuracy)
        XCTAssertEqual(expression.leftBrow, 1, accuracy: accuracy)
        XCTAssertEqual(expression.roll, 0, accuracy: accuracy)
    }

    func testTheMeasuringReaderReadsAsTheMeasuresDo() {
        let face = Drawn().landmarks
        XCTAssertEqual(MeasuringFaceReader().expression(of: face), FaceExpressionReader.expression(of: face))
    }

    func testAFaceWithAPartMissingCannotBeRead() {
        var noNose = Drawn().landmarks
        noNose.nose = []
        XCTAssertNil(FaceExpressionReader.expression(of: noNose))

        var oneEye = Drawn().landmarks
        oneEye.eyes.removeLast()
        XCTAssertNil(FaceExpressionReader.expression(of: oneEye))

        var oneBrow = Drawn().landmarks
        oneBrow.brows.removeLast()
        XCTAssertNil(FaceExpressionReader.expression(of: oneBrow))

        var sameEyes = Drawn().landmarks
        sameEyes.eyes[1] = sameEyes.eyes[0]
        XCTAssertNil(FaceExpressionReader.expression(of: sameEyes), "eyes in one place cannot be told apart")
    }

    func testAnEyeWithNoWidthIsTakenAsShut() throws {
        var face = Drawn()
        face.eyeWidth = 0
        let expression = try read(face)
        XCTAssertEqual(expression.leftEyeOpen, 0)
        XCTAssertEqual(expression.rightEyeOpen, 0)
    }

    func testARestingFaceSitsInTheMiddleOfThePicture() {
        let resting = FaceExpression.resting(in: CGSize(width: 1000, height: 500))
        XCTAssertEqual(resting, FaceExpression(centre: CGPoint(x: 500, y: 300), height: 150, smile: 0.5))
        XCTAssertEqual(resting.crown, CGPoint(x: 500, y: 405), "the top of the head is straight above the face")
        XCTAssertEqual(resting.eyeLine, CGPoint(x: 500, y: 322.5), "and the eyes are where a face's usually are")
        XCTAssertEqual(resting.eyeSpan, 67.5)
        let measured = FaceExpression(centre: .zero, height: 10, eyeLine: CGPoint(x: 3, y: 4), eyeSpan: 5)
        XCTAssertEqual(measured.eyeLine, CGPoint(x: 3, y: 4))
        XCTAssertEqual(measured.eyeSpan, 5)
        XCTAssertEqual(
            FaceExpression(centre: .zero, height: 10, crown: CGPoint(x: 1, y: 2)).crown, CGPoint(x: 1, y: 2)
        )
    }

    func testBlendingMovesEveryMeasurePartOfTheWay() {
        let from = FaceExpression(centre: .zero, height: 100)
        let to = FaceExpression(
            centre: CGPoint(x: 10, y: 20), height: 200, roll: 1, turn: 1, nod: -1, leftEyeOpen: 0, rightEyeOpen: 0.5,
            leftBrow: 1, rightBrow: -1, mouthOpen: 1, smile: 0.5
        )
        assertClose(from.blended(towards: to, by: 0.5), FaceExpression(
            centre: CGPoint(x: 5, y: 10), height: 150, roll: 0.5, turn: 0.5, nod: -0.5, leftEyeOpen: 0.5,
            rightEyeOpen: 0.75, leftBrow: 0.5, rightBrow: -0.5, mouthOpen: 0.5, smile: 0.25
        ))
        assertClose(from.blended(towards: to, by: 1), to)
        assertClose(from.blended(towards: to, by: 0), from)
    }

    func testTheSmootherTakesTheFirstFaceWholeThenGlidesAndHolds() {
        let start = FaceExpression(centre: .zero, height: 10)
        let first = FaceExpression(centre: CGPoint(x: 100, y: 100), height: 100)
        let second = FaceExpression(centre: CGPoint(x: 200, y: 100), height: 100, mouthOpen: 1)
        let smoother = ExpressionSmoother(start: start, share: 0.5)

        XCTAssertEqual(smoother.settle(on: nil), start, "nobody yet, so the starting face shows")
        XCTAssertEqual(smoother.settle(on: first), first, "the first face is taken as it is")
        let glided = smoother.settle(on: second)
        XCTAssertEqual(glided.centre.x, 150, accuracy: accuracy)
        XCTAssertEqual(glided.mouthOpen, 0.5, accuracy: accuracy)
        XCTAssertEqual(smoother.settle(on: nil), glided, "a face lost from view is held where it was")

        smoother.rest(at: start)
        XCTAssertEqual(smoother.settle(on: nil), start, "put somewhere by hand, it stays there")
        XCTAssertEqual(ExpressionSmoother(start: start, share: 1).settle(on: nil), start)
    }
}
