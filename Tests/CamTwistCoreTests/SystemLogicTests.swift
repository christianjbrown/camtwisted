import XCTest
@testable import CamTwistCore

final class SystemLogicTests: XCTestCase {
    private let up = Int32(IFF_UP)
    private let loopback = Int32(IFF_LOOPBACK)
    private let ipv4 = UInt8(AF_INET)

    func testAnInterfaceQualifiesWhenItIsUpOnIPv4AndNotLoopback() {
        XCTAssertTrue(ReachableInterface.qualifies(flags: up, family: ipv4))
        XCTAssertFalse(ReachableInterface.qualifies(flags: 0, family: ipv4))
        XCTAssertFalse(ReachableInterface.qualifies(flags: up | loopback, family: ipv4))
        XCTAssertFalse(ReachableInterface.qualifies(flags: up, family: UInt8(AF_INET6)))
    }

    func testAWindowIsNoBiggerThanTheRoomAndKeepsItsSizeWithNoScreen() {
        let wanted = CGSize(width: 800, height: 600)
        XCTAssertEqual(WindowFit.size(wanted: wanted, room: nil), wanted)
        XCTAssertEqual(WindowFit.size(wanted: wanted, room: CGSize(width: 1000, height: 700)), wanted)
        XCTAssertEqual(
            WindowFit.size(wanted: wanted, room: CGSize(width: 500, height: 900)), CGSize(width: 500, height: 600)
        )
        XCTAssertEqual(
            WindowFit.size(wanted: wanted, room: CGSize(width: 900, height: 400)), CGSize(width: 800, height: 400)
        )
    }
}
