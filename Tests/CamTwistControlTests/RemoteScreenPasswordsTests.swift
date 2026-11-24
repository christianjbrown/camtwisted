import CamTwistCore
import XCTest
@testable import CamTwistControl

final class RemoteScreenPasswordsTests: XCTestCase {
    func testAComputersPasswordIsKeptUnderItsAddressAndPort() {
        let kept = FakePasswords()
        let passwords = RemoteScreenPasswords(passwords: kept)
        let computer = VNCSettings(address: "studio.local")
        XCTAssertNil(passwords.password(for: computer))
        passwords.setPassword("secret", for: computer)
        XCTAssertEqual(passwords.password(for: computer), "secret")
        XCTAssertEqual(kept.kept, [computer.account: "secret"])
        XCTAssertNil(
            passwords.password(for: VNCSettings(address: "studio.local:5901")), "another port is another computer"
        )
        passwords.setPassword("", for: computer)
        XCTAssertNil(passwords.password(for: computer))
    }
}
