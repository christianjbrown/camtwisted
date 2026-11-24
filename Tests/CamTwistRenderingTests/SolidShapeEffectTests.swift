import CamTwistCore
import CoreImage
import Metal
import XCTest
@testable import CamTwistRendering

private final class RecordingStage: SolidRendering {
    var answer: CIImage?
    var asked: [(shape: SolidShape, turn: Double, tilt: Double, size: Double, position: CGPoint)] = []

    func picture(
        of image: CIImage, on shape: SolidShape, turn: Double, tilt: Double, size: Double, position: CGPoint
    ) -> CIImage? {
        asked.append((shape, turn, tilt, size, position))
        return answer
    }
}

final class SolidShapeEffectTests: XCTestCase {
    private let canvas = CGSize(width: 320, height: 180)
    private let access = makePixelAccess()
    private var bounds: CGRect { CGRect(origin: .zero, size: canvas) }

    /// Red across the top half, blue across the bottom.
    private let twoTone = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 90, width: 320, height: 90))
        .composited(over: CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180)))

    /// Red, green, blue and alpha at a point given in fractions of the
    /// picture, with y measured up from the bottom.
    private func pixel(_ image: CIImage, x: Double, y: Double) -> [Int] {
        let whole = image.cropped(to: bounds).composited(over: CIImage(color: .clear).cropped(to: bounds))
        let bytes = access.rgba(of: whole, width: 320, height: 180)
        let row = min(Int((1 - y) * 180), 179)
        let index = (row * 320 + min(Int(x * 320), 319)) * 4
        return bytes[index..<index + 4].map(Int.init)
    }

    func testTheEffectTurnsWithTimeAndPassesItsSettingsOn() {
        let stage = RecordingStage()
        stage.answer = CIImage(color: .green).cropped(to: bounds)
        let effect = SolidShapeEffect(stage: stage)
        effect.setValues([
            SolidShapeEffect.shapeKey: .string("Sphere"), SolidShapeEffect.turnRateKey: .number(0.25),
            SolidShapeEffect.tumbleRateKey: .number(0.125),
            SolidShapeEffect.turnKey: .number(10), SolidShapeEffect.tiltKey: .number(20),
            SolidShapeEffect.sizeKey: .number(0.5),
            SolidShapeEffect.xKey: .number(0.25), SolidShapeEffect.yKey: .number(-0.5),
        ])
        XCTAssertEqual(effect.apply(to: twoTone, time: 1), stage.answer)
        XCTAssertEqual(stage.asked.first?.shape, .sphere)
        XCTAssertEqual(stage.asked.first?.turn ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(stage.asked.first?.tilt ?? 0, 65, accuracy: 0.0001, "an eighth of a tumble on from 20")
        XCTAssertEqual(stage.asked.first?.size, 0.5)
        XCTAssertEqual(stage.asked.first?.position, CGPoint(x: 0.25, y: -0.5))

        stage.answer = nil
        XCTAssertEqual(effect.apply(to: twoTone, time: 1), twoTone, "nothing drawn, so the picture passes through")
        XCTAssertEqual(SolidShapeEffect(stage: nil).apply(to: twoTone, time: 0), twoTone)
        XCTAssertEqual(SolidShapeEffect.parameters.map(\.displayName), ["Shape", "Turns a second", "Tumbles a second", "Turn", "Tilt", "Size", "X Position", "Y Position"])
        XCTAssertEqual(SolidShapeEffect.parameters.first?.choices, ["Cube", "Box", "Sphere", "Cylinder", "Cone", "Pyramid"])
        XCTAssertEqual(NativeEffect.solidShape.name, "3D Shape")
        XCTAssertTrue(NativeEffect.solidShape.make(canvas) is SolidShapeEffect)
    }

    func testWithNoGraphicsCardThereIsNoStage() {
        XCTAssertNil(SceneKitSolidStage(device: nil, canvas: canvas))
    }

    func testACubeFacingTheCameraShowsThePictureTheRightWayUpWithClearAroundIt() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let stage = try XCTUnwrap(SceneKitSolidStage(device: device, canvas: canvas))
        let drawn = try XCTUnwrap(stage.picture(of: twoTone, on: .cube, turn: 0, tilt: 0, size: 0.6, position: .zero))

        let upper = pixel(drawn, x: 0.5, y: 0.65)
        XCTAssertGreaterThan(upper[0], upper[2] + 60, "the top of the face is red")
        let lower = pixel(drawn, x: 0.5, y: 0.35)
        XCTAssertGreaterThan(lower[2], lower[0] + 60, "the bottom is blue")
        XCTAssertEqual(pixel(drawn, x: 0.03, y: 0.5)[3], 0, "beside the cube is clear")
        XCTAssertEqual(pixel(drawn, x: 0.5, y: 0.03)[3], 0, "and so is beneath it")

        // Bigger covers more; the same shape again reuses its geometry.
        let large = try XCTUnwrap(stage.picture(of: twoTone, on: .cube, turn: 0, tilt: 0, size: 1.4, position: .zero))
        XCTAssertEqual(pixel(large, x: 0.5, y: 0.03)[3], 255)

        // A cube is as wide as it is tall; a box is as wide as the picture's shape makes it.
        // Each picture is read before the next is drawn: they share the stage.
        let cube = try XCTUnwrap(stage.picture(of: twoTone, on: .cube, turn: 0, tilt: 0, size: 0.8, position: .zero))
        XCTAssertEqual(pixel(cube, x: 0.1, y: 0.5)[3], 0, "beside the cube's square face")
        let box = try XCTUnwrap(stage.picture(of: twoTone, on: .box, turn: 0, tilt: 0, size: 0.8, position: .zero))
        XCTAssertEqual(pixel(box, x: 0.1, y: 0.5)[3], 255, "where the box's wide face reaches")

        // Moved half way to the left edge, a small cube leaves the middle clear.
        let moved = try XCTUnwrap(
            stage.picture(of: twoTone, on: .cube, turn: 0, tilt: 0, size: 0.3, position: CGPoint(x: -0.5, y: 0))
        )
        XCTAssertEqual(pixel(moved, x: 0.25, y: 0.5)[3], 255)
        XCTAssertEqual(pixel(moved, x: 0.5, y: 0.5)[3], 0)
    }

    func testEverySolidDrawsSomethingInTheMiddle() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let stage = try XCTUnwrap(SceneKitSolidStage(device: device, canvas: canvas))
        for shape in SolidShape.allCases {
            let drawn = try XCTUnwrap(stage.picture(of: twoTone, on: shape, turn: 30, tilt: 15, size: 0.8, position: .zero))
            XCTAssertEqual(pixel(drawn, x: 0.5, y: 0.4)[3], 255, shape.rawValue)
            XCTAssertEqual(pixel(drawn, x: 0.02, y: 0.02)[3], 0, shape.rawValue)
        }
    }
}
