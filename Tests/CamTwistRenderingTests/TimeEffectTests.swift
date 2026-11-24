import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

final class TimeEffectTests: XCTestCase {
    private let canvas = CGSize(width: 320, height: 180)
    private let access = makePixelAccess()
    private var bounds: CGRect { CGRect(origin: .zero, size: canvas) }

    private func solid(_ color: CIColor) -> CIImage { CIImage(color: color).cropped(to: bounds) }

    private var keeper: FrameKeeper { FrameKeeper(pixels: access, canvas: canvas, widest: canvas.width) }

    private func stopMotion() -> StopMotionEffect {
        StopMotionEffect(keeper: keeper) { StopMotionClock(picturesPerSecond: $0) }
    }

    /// A tape that keeps twelve frames a second and may fall two and a half seconds behind.
    private func slowMotion() -> SlowMotionEffect {
        SlowMotionEffect(
            canvas: canvas, keeper: keeper, tape: SlowMotionTape<CIImage>(captureInterval: 1.0 / 12, longestLag: 2.5)
        )
    }

    private func centre(_ image: CIImage) -> [Int] {
        let bytes = access.rgba(of: image.cropped(to: bounds), width: 3, height: 3)
        return bytes[16..<19].map(Int.init)
    }

    func testAKeptFrameIsACopyTheSizeOfTheCanvasHoweverSmallItIsKept() {
        let whole = FrameKeeper(pixels: access, canvas: canvas, widest: 320).copy(of: solid(.red))
        XCTAssertEqual(whole.extent, bounds)
        XCTAssertEqual(centre(whole), [255, 0, 0])
        let small = FrameKeeper(pixels: access, canvas: canvas, widest: 80).copy(of: solid(.green))
        XCTAssertEqual(small.extent, bounds, "kept a quarter of the size, shown at the full size")
        XCTAssertEqual(centre(small), [0, 255, 0])
    }

    func testStopMotionHoldsEachPictureUntilTheNextIsDue() {
        let effect = stopMotion()
        effect.setValues([StopMotionEffect.rateKey: .number(2)])
        XCTAssertEqual(centre(effect.apply(to: solid(.red), time: 0)), [255, 0, 0], "the first picture")
        XCTAssertEqual(centre(effect.apply(to: solid(.blue), time: 0.2)), [255, 0, 0], "still held")
        XCTAssertEqual(centre(effect.apply(to: solid(.blue), time: 0.5)), [0, 0, 255], "the next one is due")
        XCTAssertEqual(centre(effect.apply(to: solid(.green), time: 0.7)), [0, 0, 255])

        effect.setValues([StopMotionEffect.rateKey: .number(2)])
        XCTAssertEqual(centre(effect.apply(to: solid(.green), time: 0.8)), [0, 0, 255], "the same rate again changes nothing")
        effect.setValues([StopMotionEffect.rateKey: .number(10)])
        XCTAssertEqual(centre(effect.apply(to: solid(.green), time: 0.9)), [0, 255, 0], "a new rate starts a new film")
        XCTAssertEqual(StopMotionEffect.parameters.map(\.key), ["Pictures_A_Second"])
    }

    func testSlowMotionShowsWhatHappenedAMomentAgo() {
        let effect = slowMotion()
        XCTAssertEqual(centre(effect.apply(to: solid(.red), time: 0)), [255, 0, 0])
        // Red for the first four tenths of a second, blue ever since. At
        // half speed the tape is only half as far on as the clock.
        var shown: [Int: [Int]] = [:]
        for step in 1...12 {
            let time = Double(step) / 10
            let picture = effect.apply(to: solid(step <= 4 ? .red : .blue), time: time)
            XCTAssertEqual(picture.extent, bounds)
            shown[step] = centre(picture)
        }
        XCTAssertEqual(shown[6], [255, 0, 0], "six tenths in, blue has begun, but the tape is at three: still red")
        XCTAssertEqual(shown[12], [0, 0, 255], "at twelve tenths the tape has reached the blue")
        XCTAssertEqual(SlowMotionEffect.parameters.map(\.key), ["Speed"])
    }

    func testSlowMotionBlendsBetweenTheFramesItKept() {
        let effect = slowMotion()
        _ = effect.apply(to: solid(.red), time: 0)
        // A tenth of a second on, the tape is half way from the red frame to the blue.
        let mixed = centre(effect.apply(to: solid(.blue), time: 0.1))
        XCTAssertGreaterThan(mixed[0], 60)
        XCTAssertGreaterThan(mixed[2], 60, "part red and part blue")
        _ = effect.apply(to: solid(.blue), time: 0.2)
        XCTAssertEqual(centre(effect.apply(to: solid(.blue), time: 0.3)), [0, 0, 255], "and then wholly the blue")
    }

    func testAtFullSpeedThePicturePassesStraightThrough() {
        let effect = slowMotion()
        _ = effect.apply(to: solid(.red), time: 0)
        effect.setValues([SlowMotionEffect.speedKey: .number(1)])
        let blue = solid(.blue)
        XCTAssertEqual(effect.apply(to: blue, time: 0.5), blue)
    }

    func testTheTimeEffectsAreBuiltIn() {
        let tuning = EffectTuning(
            slowMotionFramesPerSecond: 12, slowMotionLongestLag: 2.5, slowMotionWidestFrame: 1280, faceFramesHeld: 10,
            characterSmoothing: 0.6, wornSmoothing: 0.85
        )
        let effects = NativeEffect.timeEffects(pixels: access, tuning: tuning)
        XCTAssertEqual(effects.map(\.name), ["Stop Motion", "Slow Motion"])
        for effect in effects {
            XCTAssertEqual(effect.make(canvas).apply(to: solid(.red), time: 0).extent, bounds, effect.name)
        }
    }
}
