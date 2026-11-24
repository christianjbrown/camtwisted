import XCTest
@testable import CamTwistCore

final class CastTargetTests: XCTestCase {
    func testThereIsATargetOnlyWhenCastingIsOnAndBothPartsAreNamed() {
        XCTAssertEqual(
            CastTarget.wanted(isOn: true, address: "http://stream", deviceName: "Lounge"),
            CastTarget(address: "http://stream", device: "Lounge")
        )
        XCTAssertNil(CastTarget.wanted(isOn: false, address: "http://stream", deviceName: "Lounge"))
        XCTAssertNil(CastTarget.wanted(isOn: true, address: nil, deviceName: "Lounge"))
        XCTAssertNil(CastTarget.wanted(isOn: true, address: "http://stream", deviceName: nil))
    }

    func testAFailureIsLeftAloneUntilTheDelayHasPassed() {
        let failed = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(CastRetry.mayTry(failedAt: nil, now: failed, delay: 5))
        XCTAssertFalse(CastRetry.mayTry(failedAt: failed, now: failed.addingTimeInterval(4), delay: 5))
        XCTAssertTrue(CastRetry.mayTry(failedAt: failed, now: failed.addingTimeInterval(5), delay: 5))
    }
}
