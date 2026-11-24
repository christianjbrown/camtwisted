import XCTest
@testable import CamTwistCore

final class RTMPTargetTests: XCTestCase {
    func testAServerAddressAndAKeyMakeATarget() {
        let target = RTMPTarget(address: " rtmp://example.com/live ", streamKey: " abc-123 ")
        XCTAssertEqual(target?.host, "example.com")
        XCTAssertEqual(target?.port, 1935)
        XCTAssertEqual(target?.isSecure, false)
        XCTAssertEqual(target?.application, "live")
        XCTAssertEqual(target?.streamKey, "abc-123")
        XCTAssertEqual(target?.serverAddress, "rtmp://example.com:1935/live")

        let secure = RTMPTarget(address: "RTMPS://example.com/app/instance/", streamKey: "key")
        XCTAssertEqual(secure?.isSecure, true)
        XCTAssertEqual(secure?.port, 443)
        XCTAssertEqual(secure?.application, "app/instance")
        XCTAssertEqual(RTMPTarget(address: "rtmp://example.com:1936/live", streamKey: "key")?.port, 1936)
    }

    func testOtherAddressesAndMissingPartsAreRefused() {
        XCTAssertNil(RTMPTarget(address: "https://example.com/live", streamKey: "key"))
        XCTAssertNil(RTMPTarget(address: "rtmp://example.com/", streamKey: "key"), "no application")
        XCTAssertNil(RTMPTarget(address: "rtmp:///live", streamKey: "key"), "no server")
        XCTAssertNil(RTMPTarget(address: "rtmp://example.com/live", streamKey: "  "), "no key")
        XCTAssertNil(RTMPTarget(address: "example.com/live", streamKey: "key"), "no scheme")
        XCTAssertNil(RTMPTarget(address: "", streamKey: "key"))
    }
}

final class FLVVideoTests: XCTestCase {
    func testTheSequenceHeaderCarriesTheParameterSets() {
        let header = FLVVideo.sequenceHeader(
            sequenceParameters: Data([0x67, 0x64, 0x00, 0x1F, 0xAA]), pictureParameters: Data([0x68, 0xEE])
        )
        XCTAssertEqual(header, Data([
            0x17, 0x00, 0, 0, 0,          // key frame, AVC, sequence header
            0x01, 0x64, 0x00, 0x1F,       // version, then profile, compatibility and level
            0xFF, 0xE1,                   // four-byte lengths, one sequence set
            0x00, 0x05, 0x67, 0x64, 0x00, 0x1F, 0xAA,
            0x01, 0x00, 0x02, 0x68, 0xEE, // one picture set
        ]))
        XCTAssertNil(FLVVideo.sequenceHeader(sequenceParameters: Data([0x67, 0x64]), pictureParameters: Data()))
        // A slice of a larger buffer reads the same.
        let slice = Data([0, 0, 0x67, 0x64, 0x00, 0x1F]).dropFirst(2)
        XCTAssertEqual(FLVVideo.sequenceHeader(sequenceParameters: slice, pictureParameters: Data())?[6], 0x64)
    }

    func testFramesSayWhetherTheyAreKeyFrames() {
        XCTAssertEqual(FLVVideo.frame(Data([9]), isKeyFrame: true), Data([0x17, 0x01, 0, 0, 0, 9]))
        XCTAssertEqual(FLVVideo.frame(Data([9]), isKeyFrame: false), Data([0x27, 0x01, 0, 0, 0, 9]))
    }
}

final class RTMPSessionTests: XCTestCase {
    private let target = RTMPTarget(address: "rtmp://example.com/live", streamKey: "secret-key")!
    private let details = RTMPVideoDetails(width: 1280, height: 720, framesPerSecond: 30, bitsPerSecond: 4_000_000)

    /// What the client sent, as commands, once the handshake bytes are taken off.
    private func commands(in data: Data, using reader: inout RTMPChunkReader) -> [[AMF0Value]] {
        reader.append(data).filter { $0.typeID == RTMPMessage.Kind.command || $0.typeID == RTMPMessage.Kind.data }
            .map { AMF0.decode($0.payload) }
    }

    private func serverCommand(_ values: [AMF0Value], stream: UInt32 = 0) -> Data {
        RTMPChunkWriter.chunks(
            for: RTMPMessage(typeID: RTMPMessage.Kind.command, streamID: stream, payload: AMF0.encode(values)),
            chunkStreamID: 3, chunkSize: 128
        )
    }

    private func name(_ command: [AMF0Value]) -> String? {
        if case .string(let name)? = command.first { return name }
        return nil
    }

    /// Runs the handshake and returns the session, ready for the server's answers.
    private func connected() -> (session: RTMPSession, reader: RTMPChunkReader, sent: [[AMF0Value]]) {
        var session = RTMPSession(target: target, details: details)
        XCTAssertEqual(session.state, .idle)
        let hello = session.start()
        XCTAssertEqual(session.state, .connecting)
        XCTAssertEqual(hello.count, 1 + 1536)
        XCTAssertEqual(hello.first, 3)

        // The server's reply arrives in two pieces; nothing is sent until it is whole.
        let block = Data((0..<1536).map { UInt8($0 % 256) })
        XCTAssertEqual(session.received(Data([3]) + block), Data())
        let reply = session.received(Data(count: 1536))
        XCTAssertEqual(reply.prefix(1536), block, "the server's block is sent back")

        var reader = RTMPChunkReader()
        let sent = commands(in: Data(reply.dropFirst(1536)), using: &reader)
        return (session, reader, sent)
    }

    func testAfterTheHandshakeItAsksToConnectToTheApplication() {
        let sent = connected().sent
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(name(sent[0]), "connect")
        guard case .object(let properties) = sent[0][2] else { return XCTFail("no connect details") }
        XCTAssertEqual(properties.first { $0.name == "app" }?.value, .string("live"))
        XCTAssertEqual(properties.first { $0.name == "tcUrl" }?.value, .string("rtmp://example.com:1935/live"))
    }

    func testItCreatesAStreamPublishesAndGoesLive() {
        var (session, reader, _) = connected()

        let afterConnect = session.received(serverCommand([.string("_result"), .number(1), .null, .null]))
        let asked = commands(in: afterConnect, using: &reader)
        XCTAssertEqual(asked.compactMap(name), ["releaseStream", "FCPublish", "createStream"])
        XCTAssertEqual(asked[0].last, .string("secret-key"))

        let afterCreate = session.received(serverCommand([.string("_result"), .number(4), .null, .number(7)]))
        let publish = commands(in: afterCreate, using: &reader)
        XCTAssertEqual(publish.compactMap(name), ["publish"])
        XCTAssertEqual(Array(publish[0].suffix(2)), [.string("secret-key"), .string("live")])
        XCTAssertEqual(session.video(Data([1]), atMilliseconds: 0), Data(), "no video until the server says go")
        XCTAssertEqual(session.marker(scene: "Wide", atMilliseconds: 0), Data(), "nor markers")

        let started = serverCommand([
            .string("onStatus"), .number(0), .null,
            .object([AMF0Property("level", .string("status")), AMF0Property("code", .string("NetStream.Publish.Start"))]),
        ], stream: 7)
        let afterStart = session.received(started)
        XCTAssertEqual(session.state, .live)
        let details = commands(in: afterStart, using: &reader)
        XCTAssertEqual(details.compactMap(name), ["@setDataFrame"])
        guard case .array(let properties) = details[0][2] else { return XCTFail("no stream details") }
        XCTAssertEqual(properties.first { $0.name == "width" }?.value, .number(1280))
        XCTAssertEqual(properties.first { $0.name == "videodatarate" }?.value, .number(4000))

        // A scene change goes out as a cue point on the same stream.
        var markerReader = RTMPChunkReader()
        _ = markerReader.append(RTMPChunkWriter.chunks(
            for: RTMPMessage(typeID: 1, payload: Data([0, 0, 0x10, 0])), chunkStreamID: 2, chunkSize: 128
        ))
        let marker = markerReader.append(session.marker(scene: "Wide", atMilliseconds: 2500))
        XCTAssertEqual(marker.first?.typeID, RTMPMessage.Kind.data)
        XCTAssertEqual(marker.first?.streamID, 7)
        XCTAssertEqual(marker.first.map { AMF0.decode($0.payload) }, [
            .string("onCuePoint"),
            .object([
                AMF0Property("name", .string("Wide")), AMF0Property("time", .number(2.5)),
                AMF0Property("type", .string("navigation")),
            ]),
        ])

        // Video now goes out on the stream the server made.
        var videoReader = RTMPChunkReader()
        _ = videoReader.append(RTMPChunkWriter.chunks(
            for: RTMPMessage(typeID: 1, payload: Data([0, 0, 0x10, 0])), chunkStreamID: 2, chunkSize: 128
        ))
        let frame = videoReader.append(session.video(Data([0x17, 1, 0, 0, 0, 9]), atMilliseconds: 40))
        XCTAssertEqual(frame, [RTMPMessage(typeID: 9, streamID: 7, timestamp: 40, payload: Data([0x17, 1, 0, 0, 0, 9]))])
    }

    func testTheChunkSizeItAnnouncesIsTheOneItIsGiven() {
        var session = RTMPSession(target: target, details: details, chunkSize: 1000)
        _ = session.start()
        let reply = session.received(Data([3]) + Data(count: 1536 * 2))
        var reader = RTMPChunkReader()
        let announced = reader.append(Data(reply.dropFirst(1536))).first { $0.typeID == RTMPMessage.Kind.setChunkSize }
        XCTAssertEqual(announced?.payload, Data([0, 0, 0x03, 0xE8]))
    }

    func testAStreamWithSoundSaysSoAndCarriesAudioOnceLive() {
        var session = RTMPSession(target: target, details: details, sound: .standard)
        _ = session.start()
        let reply = session.received(Data([3]) + Data(count: 1536 * 2))
        var reader = RTMPChunkReader()
        _ = commands(in: Data(reply.dropFirst(1536)), using: &reader)
        XCTAssertEqual(session.audio(Data([1]), atMilliseconds: 0), Data(), "no sound until the server says go")
        _ = session.received(serverCommand([.string("_result"), .number(1), .null, .null]))
        _ = session.received(serverCommand([.string("_result"), .number(4), .null, .number(3)]))
        let afterStart = session.received(serverCommand([
            .string("onStatus"), .number(0), .null,
            .object([AMF0Property("code", .string("NetStream.Publish.Start"))]),
        ]))
        var sent = RTMPChunkReader()
        _ = sent.append(RTMPChunkWriter.chunks(
            for: RTMPMessage(typeID: 1, payload: Data([0, 0, 0x10, 0])), chunkStreamID: 2, chunkSize: 128
        ))
        let details = sent.append(afterStart).map { AMF0.decode($0.payload) }
        guard case .array(let properties)? = details.first?.last else { return XCTFail("no stream details") }
        XCTAssertEqual(properties.first { $0.name == "audiocodecid" }?.value, .number(10))
        XCTAssertEqual(properties.first { $0.name == "audiosamplerate" }?.value, .number(48000))
        XCTAssertEqual(properties.first { $0.name == "stereo" }?.value, .boolean(true))

        let audio = sent.append(session.audio(Data([0xAF, 1, 7]), atMilliseconds: 21))
        XCTAssertEqual(audio, [RTMPMessage(typeID: 8, streamID: 3, timestamp: 21, payload: Data([0xAF, 1, 7]))])
    }

    func testARefusalOrAnErrorStatusFailsTheStream() {
        var refused = connected().session
        _ = refused.received(serverCommand([.string("_error"), .number(1), .null, .null]))
        XCTAssertEqual(refused.state, .failed("The server refused the stream"))

        var badKey = connected().session
        _ = badKey.received(serverCommand([
            .string("onStatus"), .number(0), .null,
            .object([AMF0Property("level", .string("error")), AMF0Property("code", .string("NetStream.Publish.BadName"))]),
        ]))
        XCTAssertEqual(badKey.state, .failed("NetStream.Publish.BadName"))

        var nameless = connected().session
        _ = nameless.received(serverCommand([
            .string("onStatus"), .number(0), .null, .object([AMF0Property("level", .string("error"))]),
        ]))
        XCTAssertEqual(nameless.state, .failed("The server refused the stream"))
    }

    func testOtherThingsTheServerSaysAreLetPass() {
        var session = connected().session
        // A status that is neither a start nor an error, one with no details,
        // a command with no name, a result nobody asked for, a call the
        // server makes, and a message that is not a command at all.
        let quiet = serverCommand([
            .string("onStatus"), .number(0), .null, .object([AMF0Property("level", .string("status"))]),
        ]) + serverCommand([.string("onStatus"), .number(0), .null])
            + serverCommand([.number(1)])
            + serverCommand([.string("_result"), .number(99)])
            + serverCommand([.string("_result")])
            + serverCommand([.string("onBWDone"), .number(0), .null])
            + RTMPChunkWriter.chunks(for: RTMPMessage(typeID: 5, payload: Data([0, 0, 0, 1])), chunkStreamID: 2, chunkSize: 128)
        XCTAssertEqual(session.received(quiet), Data())
        XCTAssertEqual(session.state, .connecting)

        // A stream made with no number keeps stream zero.
        var odd = connected()
        _ = odd.session.received(serverCommand([.string("_result"), .number(1), .null, .null]))
        let publish = odd.session.received(serverCommand([.string("_result"), .number(4), .null, .null]))
        XCTAssertEqual(odd.reader.append(Data()), [])
        XCTAssertFalse(publish.isEmpty)
    }
}
