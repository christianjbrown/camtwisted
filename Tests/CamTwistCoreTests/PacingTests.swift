import XCTest
@testable import CamTwistCore

final class PacingTests: XCTestCase {
    private func defaults(_ values: [String: Any]) -> UserDefaults {
        let suite = UserDefaults(suiteName: "pacing-\(UUID().uuidString)")!
        for (key, value) in values { suite.set(value, forKey: key) }
        return suite
    }

    func testWithNothingSetEverySettingHasItsUsualValue() {
        XCTAssertEqual(Pacing.load(defaults: defaults([:])), Pacing.usual)
    }

    func testEveryNumberCanBeTurnedByItsOwnName() {
        for (key, value) in Pacing.numbers {
            let turned = Pacing.load(defaults: defaults([key: Pacing.usual[keyPath: value] + 1.5]))
            var expected = Pacing.usual
            expected[keyPath: value] += 1.5
            XCTAssertEqual(turned, expected, key)
        }
    }

    func testEveryCountCanBeTurnedByItsOwnName() {
        for (key, value) in Pacing.counts {
            let turned = Pacing.load(defaults: defaults([key: Pacing.usual[keyPath: value] + 7]))
            var expected = Pacing.usual
            expected[keyPath: value] += 7
            XCTAssertEqual(turned, expected, key)
        }
    }

    func testASettingOfNoughtOrLessCountsAsNotSet() {
        for (key, _) in Pacing.numbers + Pacing.counts {
            XCTAssertEqual(Pacing.load(defaults: defaults([key: 0])), Pacing.usual, key)
            XCTAssertEqual(Pacing.load(defaults: defaults([key: -3])), Pacing.usual, key)
        }
    }

    func testTheTablesCoverEverySettingOnce() {
        let keys = (Pacing.numbers.map(\.key) + Pacing.counts.map(\.key))
        XCTAssertEqual(Set(keys).count, keys.count, "no name is used twice")
        XCTAssertEqual(keys.count, Mirror(reflecting: Pacing.usual).children.count, "every setting has a name")
    }

    func testTheNamesAreTheSettingsInUpperCamelCase() {
        XCTAssertEqual(Pacing.Key.castPingInterval, "CastPingInterval")
        XCTAssertEqual(Pacing.Key.streamPiecesKept, "StreamPiecesKept")
    }
}
