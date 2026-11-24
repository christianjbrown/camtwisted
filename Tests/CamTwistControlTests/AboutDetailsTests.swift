import XCTest
@testable import CamTwistControl

final class AboutDetailsTests: XCTestCase {
    func testTheDetailsComeFromTheAppsInformation() {
        let details = AboutDetails(information: [
            AboutDetails.Key.name: "Sample", AboutDetails.Key.version: "1.2", AboutDetails.Key.build: "7",
            AboutDetails.Key.copyright: "© Somebody", AboutDetails.Key.maker: "Somebody",
            AboutDetails.Key.supportAddress: "https://example.com/help",
            AboutDetails.Key.inspiration: ["Inspired by Sample One.", "Not affiliated with it."],
        ])
        XCTAssertEqual(details.name, "Sample")
        XCTAssertEqual(details.versionLine, "Version 1.2 (7)")
        XCTAssertEqual(details.copyright, "© Somebody")
        XCTAssertEqual(details.maker, "Somebody")
        XCTAssertEqual(details.supportAddress, URL(string: "https://example.com/help"))
        XCTAssertEqual(details.inspiration, ["Inspired by Sample One.", "Not affiliated with it."])
    }

    func testWhatIsMissingIsLeftOut() {
        let empty = AboutDetails(information: [:])
        XCTAssertEqual(empty.name, "")
        XCTAssertEqual(empty.versionLine, "")
        XCTAssertEqual(empty.maker, "")
        XCTAssertNil(empty.supportAddress)
        XCTAssertEqual(empty.inspiration, [])
        XCTAssertEqual(AboutDetails(information: [AboutDetails.Key.version: "2"]).versionLine, "Version 2")
        XCTAssertEqual(AboutDetails(information: [AboutDetails.Key.build: "9"]).versionLine, "Version (9)")
        XCTAssertEqual(AboutDetails(information: [AboutDetails.Key.name: 3]).name, "", "a value of the wrong kind is no value")
    }
}
