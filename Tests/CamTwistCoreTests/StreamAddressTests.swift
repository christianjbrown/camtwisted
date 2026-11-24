import XCTest
@testable import CamTwistCore

final class StreamAddressTests: XCTestCase {
    func testWebAddressesAndFilesCanBePlayed() {
        XCTAssertEqual(
            StreamAddress.url(from: " https://example.com/live/stream.m3u8 ")?.absoluteString,
            "https://example.com/live/stream.m3u8"
        )
        XCTAssertEqual(StreamAddress.url(from: "HTTP://example.com/clip.mp4")?.host, "example.com")
        XCTAssertEqual(StreamAddress.url(from: "example.com/clip.mp4")?.absoluteString, "https://example.com/clip.mp4")
        XCTAssertEqual(StreamAddress.url(from: "/tmp/clip.mp4"), URL(fileURLWithPath: "/tmp/clip.mp4"))
        XCTAssertEqual(StreamAddress.url(from: "file:///tmp/clip.mp4")?.path, "/tmp/clip.mp4")
    }

    func testNothingAndUnplayableKindsGiveNothing() {
        XCTAssertNil(StreamAddress.url(from: "   "))
        XCTAssertNil(StreamAddress.url(from: "rtmp://example.com/live/key"))
        XCTAssertNil(StreamAddress.url(from: "://"))
    }

    func testAStreamStartsWithNoAddressAtFullVolume() {
        let stream = StreamSettings()
        XCTAssertEqual(stream.address, "")
        XCTAssertEqual(stream.volume, StreamSettings.fullVolume)
    }
}
