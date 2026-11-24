import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

/// Paints a block whose place comes from its controls, or nothing at all.
private final class BlockEffect: ImageEffect {
    private var values: [String: EffectValue] = [:]

    func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        guard case .number(let x)? = values["x"] else { return image }
        let block = CIImage(color: .red).cropped(to: CGRect(x: x, y: 40, width: 160, height: 20))
        return block.composited(over: image)
    }
}

private final class BlockFactory: ImageEffectFactory {
    private(set) var made = 0

    func makeEffect(named name: String, canvas: CGSize) -> ImageEffect? {
        guard name == "Block" else { return nil }
        made += 1
        return BlockEffect()
    }
}

final class OverlayMeasurerTests: XCTestCase {
    private let canvas = CGSize(width: 640, height: 360)

    func testTheBoxIsRoundWhatTheEffectDraws() throws {
        let measurer = OverlayMeasurer(factory: BlockFactory(), pixels: makePixelAccess(), canvas: canvas)
        // 160 by 20 at (320, 40) on a 640 by 360 canvas.
        let bounds = try XCTUnwrap(measurer.bounds(ofEffectNamed: "Block", values: ["x": .number(320)]))
        XCTAssertEqual(bounds.minX, 0.5, accuracy: 0.01)
        XCTAssertEqual(bounds.width, 0.25, accuracy: 0.01)
        XCTAssertEqual(bounds.minY, 40.0 / 360, accuracy: 0.01)
        XCTAssertEqual(bounds.height, 20.0 / 360, accuracy: 0.01)
    }

    func testAnEffectThatDrawsNothingOrDoesNotExistHasNoBox() {
        let measurer = OverlayMeasurer(factory: BlockFactory(), pixels: makePixelAccess(), canvas: canvas)
        XCTAssertNil(measurer.bounds(ofEffectNamed: "Block", values: [:]))
        XCTAssertNil(measurer.bounds(ofEffectNamed: "Missing", values: [:]))
    }

    func testTheAnswerIsKeptUntilTheControlsChange() {
        let factory = BlockFactory()
        let measurer = OverlayMeasurer(factory: factory, pixels: makePixelAccess(), canvas: canvas)
        let first = measurer.bounds(ofEffectNamed: "Block", values: ["x": .number(0)])
        XCTAssertEqual(measurer.bounds(ofEffectNamed: "Block", values: ["x": .number(0)]), first)
        XCTAssertEqual(factory.made, 1)
        XCTAssertNotEqual(measurer.bounds(ofEffectNamed: "Block", values: ["x": .number(320)]), first)
        XCTAssertEqual(factory.made, 2)
    }

    func testAlphaBoundsCoverEverythingThatIsNotClear() {
        // Four across and three down, first row at the top: one faint pixel
        // that does not count, and two solid ones.
        var bytes = [UInt8](repeating: 0, count: 4 * 3 * 4)
        func setAlpha(_ alpha: UInt8, column: Int, row: Int) { bytes[(row * 4 + column) * 4 + 3] = alpha }
        setAlpha(2, column: 0, row: 0)
        setAlpha(255, column: 2, row: 1)
        setAlpha(255, column: 1, row: 2)
        let bounds = AlphaBounds.unitRect(rgba: bytes, width: 4, height: 3, faintestAlpha: 8)
        XCTAssertEqual(bounds?.minX ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(bounds?.width ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(bounds?.minY ?? 1, 0, accuracy: 0.0001)
        XCTAssertEqual(bounds?.height ?? 0, 2.0 / 3, accuracy: 0.0001)
        XCTAssertNil(AlphaBounds.unitRect(rgba: [UInt8](repeating: 0, count: 16), width: 2, height: 2, faintestAlpha: 8))
    }
}
