import XCTest
@testable import CamTwistCore

final class RTMPChunkTests: XCTestCase {
    private func message(_ bytes: Int, type: UInt8 = 20, stream: UInt32 = 0, time: UInt32 = 0) -> RTMPMessage {
        RTMPMessage(typeID: type, streamID: stream, timestamp: time, payload: Data((0..<bytes).map { UInt8($0 % 251) }))
    }

    func testAShortMessageIsOneChunkWithAFullHeader() {
        let chunk = RTMPChunkWriter.chunks(
            for: RTMPMessage(typeID: 20, streamID: 1, timestamp: 0x010203, payload: Data([0xAA, 0xBB])),
            chunkStreamID: 3, chunkSize: 128
        )
        XCTAssertEqual(chunk, Data([
            0x03,             // full header, chunk stream 3
            0x01, 0x02, 0x03, // timestamp
            0x00, 0x00, 0x02, // length
            20,               // type
            0x01, 0, 0, 0,    // message stream, least significant byte first
            0xAA, 0xBB,
        ]))
    }

    func testALongMessageIsCutIntoPiecesWithAOneByteHeaderBetween() {
        let long = message(300)
        let chunks = RTMPChunkWriter.chunks(for: long, chunkStreamID: 4, chunkSize: 128)
        XCTAssertEqual(chunks.count, 12 + 300 + 2)
        XCTAssertEqual(chunks[12 + 128], 0xC4)
        XCTAssertEqual(chunks[12 + 128 + 1 + 128], 0xC4)
        // A chunk size of nothing still makes progress.
        XCTAssertEqual(RTMPChunkWriter.chunks(for: message(2), chunkStreamID: 4, chunkSize: 0).count, 12 + 2 + 1)
    }

    func testWhatIsWrittenIsReadBackWhateverPiecesItArrivesIn() {
        let sent = [message(10), message(300, type: 9, stream: 1, time: 40), message(0, time: 80)]
        let wire = sent.reduce(Data()) { $0 + RTMPChunkWriter.chunks(for: $1, chunkStreamID: 5, chunkSize: 128) }
        var whole = RTMPChunkReader()
        XCTAssertEqual(whole.append(wire), sent)

        var dripped = RTMPChunkReader()
        var received: [RTMPMessage] = []
        for byte in wire {
            received += dripped.append(Data([byte]))
        }
        XCTAssertEqual(received, sent)
    }

    func testLateTimestampsAreWrittenAfterTheHeaderAndReadBack() {
        let late = message(200, type: 9, stream: 1, time: 0x0100_0000)
        let wire = RTMPChunkWriter.chunks(for: late, chunkStreamID: 6, chunkSize: 128)
        XCTAssertEqual(Array(wire[1...3]), [0xFF, 0xFF, 0xFF])
        XCTAssertEqual(Array(wire[12...15]), [0x01, 0, 0, 0])
        XCTAssertEqual(wire.count, 12 + 4 + 200 + 1 + 4, "the continuation repeats the long timestamp")
        var reader = RTMPChunkReader()
        XCTAssertEqual(reader.append(wire), [late])
        XCTAssertEqual(reader.append(wire.prefix(14)), [], "a header cut short waits for the rest")
    }

    func testTheShorterHeadersServersSendAreUnderstood() {
        var reader = RTMPChunkReader()
        // A full header at time 100, then the same stream with only a
        // time step of 20 and a new length, then one with only a step,
        // then one with no header at all, which steps the same again.
        var wire = Data([0x03, 0, 0, 100, 0, 0, 1, 20, 1, 0, 0, 0, 0xA1])
        wire += Data([0x43, 0, 0, 20, 0, 0, 2, 20, 0xB1, 0xB2])
        wire += Data([0x83, 0, 0, 5, 0xC1, 0xC2])
        wire += Data([0xC3, 0xD1, 0xD2])
        let messages = reader.append(wire)
        XCTAssertEqual(messages.map(\.timestamp), [100, 120, 125, 130])
        XCTAssertEqual(messages.map(\.payload), [Data([0xA1]), Data([0xB1, 0xB2]), Data([0xC1, 0xC2]), Data([0xD1, 0xD2])])
        XCTAssertEqual(messages.map(\.streamID), [1, 1, 1, 1])
    }

    func testChunkStreamIDsBeyondSixtyThreeAreUnderstood() {
        var reader = RTMPChunkReader()
        // Id 0 means one more byte holds the id less 64; id 1 means two.
        let oneByte = Data([0x00, 10, 0, 0, 0, 0, 0, 1, 20, 0, 0, 0, 0, 0x11])
        let twoByte = Data([0x01, 10, 1, 0, 0, 0, 0, 0, 1, 20, 0, 0, 0, 0, 0x22])
        XCTAssertEqual(reader.append(oneByte + twoByte).map(\.payload), [Data([0x11]), Data([0x22])])
        XCTAssertEqual(reader.append(Data([0x00])), [], "an id cut short waits")
        var other = RTMPChunkReader()
        XCTAssertEqual(other.append(Data([0x01, 10])), [])
    }

    func testAChangeOfChunkSizeIsObeyed() {
        var reader = RTMPChunkReader()
        let bigger = RTMPMessage(typeID: RTMPMessage.Kind.setChunkSize, payload: Data([0, 0, 0x10, 0]))
        let long = message(300)
        let wire = RTMPChunkWriter.chunks(for: bigger, chunkStreamID: 2, chunkSize: 128)
            + RTMPChunkWriter.chunks(for: long, chunkStreamID: 3, chunkSize: 4096)
        XCTAssertEqual(reader.append(wire), [bigger, long])
        // A size of nothing, or one cut short, is ignored.
        let none = RTMPMessage(typeID: RTMPMessage.Kind.setChunkSize, payload: Data([0, 0, 0, 0]))
        let short = RTMPMessage(typeID: RTMPMessage.Kind.setChunkSize, payload: Data([0, 0]))
        let after = RTMPChunkWriter.chunks(for: none, chunkStreamID: 2, chunkSize: 4096)
            + RTMPChunkWriter.chunks(for: short, chunkStreamID: 2, chunkSize: 4096)
            + RTMPChunkWriter.chunks(for: long, chunkStreamID: 3, chunkSize: 4096)
        XCTAssertEqual(reader.append(after), [none, short, long])
    }
}
