import CamTwistCore
import CamTwistRendering
import XCTest
@testable import CamTwistControl

final class TunablesTests: XCTestCase {
    private func defaults(_ values: [String: Any]) -> UserDefaults {
        let suite = UserDefaults(suiteName: "tunables-\(UUID().uuidString)")!
        for (key, value) in values { suite.set(value, forKey: key) }
        return suite
    }

    func testWithNothingSetEverySettingHasItsUsualValue() {
        let usual = Tunables.load(defaults: defaults([:]))
        XCTAssertEqual(usual.effects, EffectTuning(
            slowMotionFramesPerSecond: 12, slowMotionLongestLag: 2.5, slowMotionWidestFrame: 1280, faceFramesHeld: 10,
            characterSmoothing: 0.6, wornSmoothing: 0.85
        ))
        XCTAssertEqual(usual.refreshInterval, 2)
        XCTAssertEqual(usual.pacing, Pacing.usual)
    }

    func testEachSettingCanBeTurnedByItsOwnName() {
        let turned = Tunables.load(defaults: defaults([
            Tunables.Key.slowMotionFramesPerSecond: 24, Tunables.Key.slowMotionLongestLag: 4,
            Tunables.Key.slowMotionWidestFrame: 640, Tunables.Key.faceFramesHeld: 30,
            Tunables.Key.characterSmoothing: 0.3, Tunables.Key.wornSmoothing: 0.9, Tunables.Key.refreshInterval: 5,
            Pacing.Key.castPingInterval: 9, Pacing.Key.streamPiecesKept: 3,
        ]))
        var pacing = Pacing.usual
        pacing.castPingInterval = 9
        pacing.streamPiecesKept = 3
        XCTAssertEqual(turned, Tunables(
            effects: EffectTuning(
                slowMotionFramesPerSecond: 24, slowMotionLongestLag: 4, slowMotionWidestFrame: 640, faceFramesHeld: 30,
                characterSmoothing: 0.3, wornSmoothing: 0.9
            ),
            refreshInterval: 5,
            pacing: pacing
        ))
    }

    func testASettingOfNoughtOrLessCountsAsNotSet() {
        let unusable = Tunables.load(defaults: defaults([
            Tunables.Key.refreshInterval: 0, Tunables.Key.slowMotionLongestLag: -3,
        ]))
        XCTAssertEqual(unusable.refreshInterval, 2)
        XCTAssertEqual(unusable.effects.slowMotionLongestLag, 2.5)
    }

    func testAFaceCanBeHeldForNoFramesAtAll() {
        XCTAssertEqual(Tunables.load(defaults: defaults([Tunables.Key.faceFramesHeld: 0])).effects.faceFramesHeld, 0)
        XCTAssertEqual(
            Tunables.load(defaults: defaults([Tunables.Key.faceFramesHeld: -4])).effects.faceFramesHeld, 0,
            "fewer than none is none"
        )
    }
}
