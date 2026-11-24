import XCTest
@testable import CamTwistCore

final class AMF0Tests: XCTestCase {
    func testEachKindOfValueIsWrittenAsTheFormatSays() {
        XCTAssertEqual(AMF0.encode(.number(1)), Data([0x00, 0x3F, 0xF0, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(AMF0.encode(.boolean(true)), Data([0x01, 0x01]))
        XCTAssertEqual(AMF0.encode(.boolean(false)), Data([0x01, 0x00]))
        XCTAssertEqual(AMF0.encode(.string("hi")), Data([0x02, 0x00, 0x02, 0x68, 0x69]))
        XCTAssertEqual(AMF0.encode(.null), Data([0x05]))
        XCTAssertEqual(
            AMF0.encode(.object([AMF0Property("a", .null)])), Data([0x03, 0x00, 0x01, 0x61, 0x05, 0x00, 0x00, 0x09])
        )
        XCTAssertEqual(
            AMF0.encode(.array([AMF0Property("a", .null)])),
            Data([0x08, 0, 0, 0, 1, 0x00, 0x01, 0x61, 0x05, 0x00, 0x00, 0x09])
        )
    }

    func testWhatIsWrittenReadsBackTheSame() {
        let values: [AMF0Value] = [
            .string("connect"), .number(1),
            .object([
                AMF0Property("app", .string("live")),
                AMF0Property("nested", .object([AMF0Property("flag", .boolean(true))])),
            ]),
            .null,
            .array([AMF0Property("width", .number(1280))]),
        ]
        XCTAssertEqual(AMF0.decode(AMF0.encode(values)), values)
        XCTAssertEqual(AMF0.decode(Data([0x06])), [.null], "undefined reads as nothing")
    }

    func testReadingStopsAtAnythingCutShortOrUnknown() {
        XCTAssertEqual(AMF0.decode(Data([0x05, 0x00, 0x3F])), [.null], "a number cut short")
        XCTAssertEqual(AMF0.decode(Data([0x05, 0x01])), [.null], "a flag with no byte")
        XCTAssertEqual(AMF0.decode(Data([0x05, 0x02, 0x00, 0x05, 0x68])), [.null], "a string cut short")
        XCTAssertEqual(AMF0.decode(Data([0x05, 0x02, 0x00])), [.null], "a string with half a length")
        XCTAssertEqual(AMF0.decode(Data([0x05, 0x0A])), [.null], "a kind this does not read")
        XCTAssertEqual(AMF0.decode(Data([0x05, 0x03, 0x00, 0x01, 0x61])), [.null], "an object with a name and no value")
        XCTAssertEqual(AMF0.decode(Data([0x05, 0x03, 0x00, 0x01, 0x61, 0x05])), [.null], "an object with no end")
        XCTAssertEqual(AMF0.decode(Data([0x05, 0x03, 0x00, 0x00, 0x07])), [.null], "an object ended with the wrong mark")
        XCTAssertEqual(AMF0.decode(Data([0x05, 0x08, 0x00])), [.null], "an array with half a count")
        XCTAssertEqual(AMF0.decode(Data()), [])
    }

    func testNumbersAreWrittenInEitherByteOrder() {
        XCTAssertEqual(ByteOrder.bigEndian(0x0102_03, bytes: 3), Data([1, 2, 3]))
        XCTAssertEqual(ByteOrder.littleEndian(0x0102_03, bytes: 4), Data([3, 2, 1, 0]))
        var reader = ByteReader(Data([1, 2, 3, 4, 5]).dropFirst())
        XCTAssertEqual(reader.integer(bytes: 2), 0x0203)
        XCTAssertEqual(reader.integer(bytes: 2), 0x0405)
        XCTAssertNil(reader.byte())
        XCTAssertNil(reader.bytes(-1))
        XCTAssertNil(reader.integer(bytes: 1))
        XCTAssertTrue(reader.isAtEnd)
    }
}
