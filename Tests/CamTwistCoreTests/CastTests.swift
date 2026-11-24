import XCTest
@testable import CamTwistCore

final class CastMessageTests: XCTestCase {
    private let hello = CastMessage(
        source: "sender-0", destination: "receiver-0", namespace: "urn:x-cast:test", payload: #"{"type":"PING"}"#
    )

    func testAMessageSurvivesBeingFramedAndReadBack() {
        let framed = hello.framed()
        let length = framed.prefix(4).reduce(0) { $0 << 8 | Int($1) }
        XCTAssertEqual(length, framed.count - 4, "its length goes in front, most significant byte first")
        XCTAssertEqual(CastMessage(body: Data(framed.dropFirst(4))), hello)
        // The first field is the protocol's version, which is nought.
        XCTAssertEqual(Array(framed.dropFirst(4).prefix(2)), [0x08, 0x00])
    }

    func testNumbersTakeAsFewBytesAsTheyNeed() {
        XCTAssertEqual(Array(CastMessage.varint(0)), [0])
        XCTAssertEqual(Array(CastMessage.varint(127)), [127])
        XCTAssertEqual(Array(CastMessage.varint(300)), [0xAC, 0x02])
        var reader = VarintReader(bytes: [0xAC, 0x02, 7, 8, 9])
        XCTAssertEqual(reader.next(), 300)
        XCTAssertEqual(reader.take(2), [7, 8])
        XCTAssertNil(reader.take(2), "not that many left")
        XCTAssertEqual(reader.take(1), [9])
        XCTAssertTrue(reader.isAtEnd)
        XCTAssertNil(reader.next())
        var endless = VarintReader(bytes: [UInt8](repeating: 0x80, count: 10))
        XCTAssertNil(endless.next(), "a number that never ends is no number")
    }

    func testWhatIsNotAMessageIsRefused() {
        XCTAssertNil(CastMessage(body: Data([0x80])), "a tag cut short")
        XCTAssertNil(CastMessage(body: Data([0x08])), "a number with no value")
        XCTAssertNil(CastMessage(body: Data([0x12, 5, 1])), "text shorter than it says")
        XCTAssertNil(CastMessage(body: Data([0x12])), "text with no length")
        XCTAssertNil(CastMessage(body: Data([0x0D, 0, 0, 0, 0])), "a layout messages never use")
        XCTAssertEqual(CastMessage(body: Data()), CastMessage(source: "", destination: "", namespace: "", payload: ""))
    }

    func testBytesAreGatheredIntoWholeMessagesAsTheyArrive() {
        var reader = CastFrameReader()
        let stream = hello.framed() + hello.framed()
        XCTAssertEqual(reader.append(stream.prefix(3)), [])
        XCTAssertEqual(reader.append(stream.dropFirst(3).prefix(10)), [])
        XCTAssertEqual(reader.append(stream.dropFirst(13)), [hello, hello])
        XCTAssertFalse(reader.isBroken)

        var huge = CastFrameReader()
        XCTAssertEqual(huge.append(Data([0xFF, 0xFF, 0xFF, 0xFF])), [])
        XCTAssertTrue(huge.isBroken, "no message is that long")
        XCTAssertEqual(huge.append(hello.framed()), [], "and nothing after it is trusted")

        var garbled = CastFrameReader()
        XCTAssertEqual(garbled.append(hello.framed() + Data([0, 0, 0, 1, 0x80])), [hello])
        XCTAssertTrue(garbled.isBroken)
    }
}

final class CastSessionTests: XCTestCase {
    private let address = "http://192.168.0.2:8090/stream.m3u8"

    private func fromDevice(_ namespace: String, _ payload: String, from source: String = "receiver-0") -> CastMessage {
        CastMessage(source: source, destination: "sender-0", namespace: "urn:x-cast:com.google.cast." + namespace, payload: payload)
    }

    private let running = #"{"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"CC1AD845","transportId":"web-5","sessionId":"abc"}]}}"#

    func testTheStreamIsPlayedByStartingThePlayerAndHandingItTheAddress() {
        var session = CastSession(streamAddress: address)
        XCTAssertEqual(session.state, .idle)

        let opening = session.connected()
        XCTAssertEqual(session.state, .starting)
        XCTAssertEqual(opening.map(\.payload), [#"{"type":"CONNECT"}"#, #"{"appId":"CC1AD845","requestId":1,"type":"LAUNCH"}"#])
        XCTAssertEqual(opening.map(\.destination), ["receiver-0", "receiver-0"])
        XCTAssertEqual(opening.map(\.namespace), [
            "urn:x-cast:com.google.cast.tp.connection", "urn:x-cast:com.google.cast.receiver",
        ])

        // Before the player is up the device reports running something else.
        XCTAssertEqual(session.received(fromDevice("receiver", #"{"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"OTHER"}]}}"#)), [])
        XCTAssertEqual(session.state, .starting)

        let loading = session.received(fromDevice("receiver", running))
        XCTAssertEqual(session.state, .loading)
        XCTAssertEqual(loading.map(\.destination), ["web-5", "web-5"])
        XCTAssertEqual(loading[0].payload, #"{"type":"CONNECT"}"#)
        XCTAssertEqual(
            loading[1].payload,
            #"{"autoplay":true,"media":{"contentId":"http://192.168.0.2:8090/stream.m3u8","contentType":"application/x-mpegURL","#
                + #""hlsSegmentFormat":"fmp4","hlsVideoSegmentFormat":"fmp4","streamType":"LIVE"},"requestId":2,"type":"LOAD"}"#
        )
        XCTAssertEqual(session.received(fromDevice("receiver", running)), [], "told again, it is not loaded twice")

        XCTAssertEqual(session.received(fromDevice("media", #"{"type":"MEDIA_STATUS","status":[{"playerState":"IDLE"}]}"#)), [])
        XCTAssertEqual(session.state, .loading)
        XCTAssertEqual(session.received(fromDevice("media", #"{"type":"MEDIA_STATUS","status":[{"playerState":"BUFFERING"}]}"#)), [])
        XCTAssertEqual(session.state, .playing)

        let goodbye = session.stop()
        XCTAssertEqual(goodbye.map(\.payload), [#"{"requestId":3,"sessionId":"abc","type":"STOP"}"#, #"{"type":"CLOSE"}"#])
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.stop().map(\.payload), [#"{"type":"CLOSE"}"#], "with no player to stop, only goodbye")
    }

    func testPingsAreAnsweredAndSent() {
        var session = CastSession(streamAddress: address)
        XCTAssertEqual(session.ping().payload, #"{"type":"PING"}"#)
        XCTAssertEqual(session.ping().namespace, "urn:x-cast:com.google.cast.tp.heartbeat")
        XCTAssertEqual(session.received(fromDevice("tp.heartbeat", #"{"type":"PING"}"#)).map(\.payload), [#"{"type":"PONG"}"#])
        XCTAssertEqual(session.received(fromDevice("tp.heartbeat", #"{"type":"PONG"}"#)), [])
        XCTAssertEqual(session.received(fromDevice("receiver", "not json")), [])
        XCTAssertEqual(session.received(fromDevice("receiver", #"{"no":"type"}"#)), [])
        XCTAssertEqual(CastSession.text(["when": Date()]), "", "what cannot be written as JSON is written as nothing")
    }

    func testEveryWayItCanGoWrongIsReported() {
        func failure(after messages: [CastMessage]) -> CastState {
            var session = CastSession(streamAddress: address)
            _ = session.connected()
            messages.forEach { _ = session.received($0) }
            return session.state
        }
        XCTAssertEqual(
            failure(after: [fromDevice("receiver", #"{"type":"LAUNCH_ERROR"}"#)]), .failed("The device could not start its player.")
        )
        XCTAssertEqual(
            failure(after: [fromDevice("tp.connection", #"{"type":"CLOSE"}"#)]), .failed("The device closed the connection.")
        )
        for refusal in ["LOAD_FAILED", "LOAD_CANCELLED", "INVALID_REQUEST"] {
            XCTAssertEqual(
                failure(after: [fromDevice("receiver", running), fromDevice("media", "{\"type\":\"\(refusal)\"}")]),
                .failed("The device could not play the stream.")
            )
        }
        // The player going away after it was up means somebody stopped it there.
        XCTAssertEqual(
            failure(after: [fromDevice("receiver", running), fromDevice("receiver", #"{"type":"RECEIVER_STATUS","status":{}}"#)]),
            .failed("It was stopped on the device.")
        )
        var session = CastSession(streamAddress: address)
        session.lost("The network went away.")
        XCTAssertEqual(session.state, .failed("The network went away."))
    }
}
