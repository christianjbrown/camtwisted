import XCTest
@testable import CamTwistCore

final class RFBFramebufferTests: XCTestCase {
    func testPixelsArePutCopiedAndKeptOnTheScreen() {
        var screen = RFBFramebuffer(width: 4, height: 2)
        XCTAssertEqual(screen.pixels.count, 32)
        // Two red pixels in the top left corner: blue, green, red, spare.
        screen.put(Data([0, 0, 255, 0, 0, 0, 255, 9]), x: 0, y: 0, width: 2, height: 1)
        XCTAssertEqual(Array(screen.pixels.prefix(8)), [0, 0, 255, 255, 0, 0, 255, 255], "the spare byte becomes solid")

        // Copied to the bottom right corner.
        screen.copy(fromX: 0, fromY: 0, toX: 2, toY: 1, width: 2, height: 1)
        XCTAssertEqual(Array(screen.pixels.suffix(8)), [0, 0, 255, 255, 0, 0, 255, 255])

        // What does not fit, or is the wrong length, changes nothing.
        let before = screen
        screen.put(Data(repeating: 1, count: 8), x: 3, y: 0, width: 2, height: 1)
        screen.put(Data(repeating: 1, count: 3), x: 0, y: 0, width: 2, height: 1)
        screen.copy(fromX: 3, fromY: 0, toX: 0, toY: 0, width: 2, height: 1)
        screen.copy(fromX: 0, fromY: 0, toX: 3, toY: 1, width: 2, height: 1)
        XCTAssertEqual(screen, before)
        XCTAssertFalse(screen.contains(x: -1, y: 0, width: 1, height: 1))
        XCTAssertFalse(screen.contains(x: 0, y: -1, width: 1, height: 1))
        XCTAssertFalse(screen.contains(x: 0, y: 0, width: -1, height: 1))
        XCTAssertFalse(screen.contains(x: 0, y: 0, width: 1, height: -1))
        XCTAssertFalse(screen.contains(x: 0, y: 1, width: 1, height: 2))
    }
}

final class RFBSessionTests: XCTestCase {
    private func number(_ value: Int, _ count: Int) -> Data { Data(RFBSession.bytes(of: value, count: count)) }

    /// What a server says once it lets a viewer in: its size, how it would
    /// send pixels, and its name.
    private func serverInit(width: Int, height: Int, name: String = "Desk") -> Data {
        number(width, 2) + number(height, 2) + Data(repeating: 0, count: 16) + number(name.utf8.count, 4) + Data(name.utf8)
    }

    private func rectangle(x: Int, y: Int, width: Int, height: Int, encoding: Int32) -> Data {
        number(x, 2) + number(y, 2) + number(width, 2) + number(height, 2)
            + number(Int(UInt32(bitPattern: encoding)), 4)
    }

    /// A session taken as far as a running screen of some size, with no password.
    private func running(width: Int = 2, height: Int = 2) -> RFBSession {
        var session = RFBSession(password: "")
        _ = session.receive(Data("RFB 003.008\n".utf8))
        _ = session.receive(Data([1, 1]))
        _ = session.receive(number(0, 4))
        _ = session.receive(serverInit(width: width, height: height))
        return session
    }

    func testSigningInWithNoPasswordAsksForTheScreen() {
        var session = RFBSession(password: "")
        XCTAssertEqual(session.state, .connecting)
        XCTAssertEqual(session.receive(Data("RFB 003".utf8)), [], "it waits for the whole greeting")
        XCTAssertEqual(session.receive(Data(".008\n".utf8)), [Data("RFB 003.008\n".utf8)])
        XCTAssertEqual(session.receive(Data([2, 2, 1])), [Data([1])], "no password where none is asked for")
        XCTAssertEqual(session.receive(number(0, 4)), [Data([1])], "the screen is shared with other viewers")

        let replies = session.receive(serverInit(width: 800, height: 600))
        XCTAssertEqual(session.state, .running)
        XCTAssertEqual(session.framebuffer.width, 800)
        XCTAssertEqual(session.framebuffer.height, 600)
        XCTAssertEqual(replies.count, 3)
        XCTAssertEqual(
            Array(replies[0]), [0, 0, 0, 0, 32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0],
            "pixels are asked for as blue, green, red and a spare byte"
        )
        XCTAssertEqual(
            Array(replies[1]), [2, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 1, 0xFF, 0xFF, 0xFF, 0x21],
            "raw pixels, copies, and changes of size are understood"
        )
        XCTAssertEqual(Array(replies[2]), [3, 0, 0, 0, 0, 0, 3, 32, 2, 88], "then the whole screen is asked for")
    }

    func testThePasswordIsProvedWithoutBeingSent() {
        var session = RFBSession(password: "secret")
        _ = session.receive(Data("RFB 003.008\n".utf8))
        XCTAssertEqual(session.receive(Data([1, 2])), [Data([2])])
        let challenge = Data((0..<16).map { UInt8($0) })
        let answer = session.receive(challenge)
        XCTAssertEqual(answer.first?.map { String(format: "%02x", $0) }.joined(), "ee22539f33a5983ec12f9c2edbc995dd")
        XCTAssertEqual(session.receive(number(0, 4)), [Data([1])])

        // A password longer than eight letters counts only for its first eight.
        XCTAssertEqual(
            RFBPassword.response(to: challenge, password: "secret\0\0andmore"),
            RFBPassword.response(to: challenge, password: "secret")
        )
    }

    func testAWrongPasswordAndAServerThatRefusesAreReported() {
        var wrong = RFBSession(password: "nope")
        _ = wrong.receive(Data("RFB 003.008\n".utf8) + Data([1, 2]) + Data(repeating: 0, count: 16))
        XCTAssertEqual(wrong.receive(number(1, 4)), [])
        XCTAssertEqual(wrong.state, .failed("The password was not accepted."))
        XCTAssertEqual(wrong.receive(Data([0, 0])), [], "nothing more is said")

        var refused = RFBSession(password: "")
        _ = refused.receive(Data("RFB 003.008\n".utf8))
        XCTAssertEqual(refused.receive(Data([0]) + number(8, 4) + Data("Too m".utf8)), [], "the reason has not all arrived")
        XCTAssertEqual(refused.state, .connecting)
        _ = refused.receive(Data("any".utf8))
        XCTAssertEqual(refused.state, .failed("Too many"))

        var unknown = RFBSession(password: "")
        _ = unknown.receive(Data("RFB 003.008\n".utf8) + Data([2, 30, 35]))
        XCTAssertEqual(unknown.state, .failed("The server offers no way of signing in that this app knows."))

        var other = RFBSession(password: "")
        _ = other.receive(Data("HTTP/1.1 200".utf8))
        XCTAssertEqual(other.state, .failed("That is not a VNC server."))
        var garbled = RFBSession(password: "")
        _ = garbled.receive(Data("RFB 003.xyz\n".utf8))
        XCTAssertEqual(garbled.state, .failed("That is not a VNC server."))
    }

    func testAnOlderServerIsSpokenToTheOldWay() {
        // The oldest version does not offer a choice of how to sign in.
        var open = RFBSession(password: "")
        XCTAssertEqual(open.receive(Data("RFB 003.003\n".utf8)), [Data("RFB 003.003\n".utf8)])
        XCTAssertEqual(open.receive(number(1, 4)), [Data([1])])
        _ = open.receive(serverInit(width: 2, height: 2))
        XCTAssertEqual(open.state, .running)

        var locked = RFBSession(password: "secret")
        _ = locked.receive(Data("RFB 003.007\n".utf8))
        XCTAssertEqual(locked.receive(number(2, 4)), [])
        XCTAssertEqual(locked.receive(Data(repeating: 0, count: 16)).count, 1, "the challenge is answered")

        var refused = RFBSession(password: "")
        _ = refused.receive(Data("RFB 003.003\n".utf8) + number(0, 4))
        XCTAssertEqual(refused.state, .failed("The server offers no way of signing in that this app knows."))
    }

    func testTheScreenIsFilledInMovedAndResizedAsUpdatesArrive() {
        var session = running()
        // The top row turns red, sent as raw pixels.
        var update = Data([0, 0]) + number(1, 2) + rectangle(x: 0, y: 0, width: 2, height: 1, encoding: 0)
        update += Data([0, 0, 255, 0, 0, 0, 255, 0])
        XCTAssertEqual(session.receive(update.prefix(10)), [], "an update is taken whole, once it has all arrived")
        XCTAssertEqual(session.receive(update.dropFirst(10).prefix(8)), [])
        let reply = session.receive(update.dropFirst(18))
        XCTAssertEqual(reply.map(Array.init), [[3, 1, 0, 0, 0, 0, 0, 2, 0, 2]], "then only what changes is asked for")
        XCTAssertEqual(Array(session.framebuffer.pixels.prefix(8)), [0, 0, 255, 255, 0, 0, 255, 255])
        XCTAssertEqual(session.updateCount, 1)

        // The top row is copied onto the bottom row.
        let copy = Data([0, 0]) + number(1, 2) + rectangle(x: 0, y: 1, width: 2, height: 1, encoding: 1)
            + number(0, 2) + number(0, 2)
        _ = session.receive(copy)
        XCTAssertEqual(Array(session.framebuffer.pixels.suffix(8)), [0, 0, 255, 255, 0, 0, 255, 255])

        // The server's screen changes size: the picture starts again.
        let resize = Data([0, 0]) + number(1, 2) + rectangle(x: 0, y: 0, width: 3, height: 1, encoding: -223)
        XCTAssertEqual(session.receive(resize).map(Array.init), [[3, 1, 0, 0, 0, 0, 0, 3, 0, 1]])
        XCTAssertEqual(session.framebuffer, RFBFramebuffer(width: 3, height: 1))
        XCTAssertEqual(session.updateCount, 3)
    }

    func testEveryPartOfTheConversationWaitsForItsBytes() {
        // The list of ways to sign in, cut short.
        var session = RFBSession(password: "")
        _ = session.receive(Data("RFB 003.008\n".utf8))
        XCTAssertEqual(session.receive(Data([2, 2])), [])
        XCTAssertEqual(session.receive(Data([1])), [Data([1])])
        _ = session.receive(number(0, 4))
        // The server's name, cut short.
        let hello = serverInit(width: 2, height: 2, name: "A long name")
        XCTAssertEqual(session.receive(hello.prefix(28)), [])
        XCTAssertEqual(session.state, .connecting)
        XCTAssertEqual(session.receive(hello.dropFirst(28)).count, 3)
        // The start of an update, cut short.
        XCTAssertEqual(session.receive(Data([0, 0])), [])
        XCTAssertEqual(session.receive(number(0, 2)).count, 1)

        // The length of a refusal, cut short.
        var refused = RFBSession(password: "")
        _ = refused.receive(Data("RFB 003.008\n".utf8))
        XCTAssertEqual(refused.receive(Data([0, 0, 0])), [])
        XCTAssertEqual(refused.state, .connecting)
        _ = refused.receive(Data([0, 2]) + Data("No".utf8))
        XCTAssertEqual(refused.state, .failed("No"))
    }

    func testOtherMessagesArePassedOverAndNonsenseEndsIt() {
        var session = running()
        // A bell, a colour map of two entries, and some copied text, then an update.
        let colourMap = Data([1, 0]) + number(0, 2) + number(2, 2) + Data(repeating: 7, count: 12)
        let cutText = Data([3, 0, 0, 0]) + number(5, 4) + Data("hello".utf8)
        let update = Data([0, 0]) + number(0, 2)
        XCTAssertEqual(session.receive(Data([2]) + colourMap.prefix(4)), [], "the colour map has not all arrived")
        XCTAssertEqual(session.receive(colourMap.dropFirst(4) + cutText.prefix(6)), [])
        XCTAssertEqual(session.receive(cutText.dropFirst(6) + update).count, 1)
        XCTAssertEqual(session.updateCount, 1)

        _ = session.receive(Data([99]))
        XCTAssertEqual(session.state, .failed("The server sent something that made no sense."))

        var odd = running()
        _ = odd.receive(Data([0, 0]) + number(1, 2) + rectangle(x: 0, y: 0, width: 1, height: 1, encoding: 16))
        XCTAssertEqual(odd.state, .failed("The server sent something that made no sense."), "a way of sending pixels that was not asked for")

        var short = running()
        XCTAssertEqual(short.receive(Data([0, 0]) + number(1, 2) + Data([0, 0])), [], "a rectangle cut short waits for the rest")
        XCTAssertEqual(short.state, .running)
    }
}

final class VNCSettingsTests: XCTestCase {
    func testAnAddressIsAComputerAndSometimesAPort() {
        XCTAssertEqual(VNCSettings().host, "")
        XCTAssertEqual(VNCSettings().port, 5900)
        let plain = VNCSettings(address: " studio.local ")
        XCTAssertEqual(plain.host, "studio.local")
        XCTAssertEqual(plain.port, 5900)
        XCTAssertEqual(plain.account, "studio.local:5900")
        let withPort = VNCSettings(address: "192.0.2.10:5901")
        XCTAssertEqual(withPort.host, "192.0.2.10")
        XCTAssertEqual(withPort.port, 5901)
        XCTAssertEqual(withPort.account, "192.0.2.10:5901")
        // What follows a colon and is no port is left as part of the name.
        XCTAssertEqual(VNCSettings(address: "desk:left").host, "desk:left")
        XCTAssertEqual(VNCSettings(address: "desk:left").port, 5900)
        XCTAssertEqual(VNCSettings(address: "desk:99999").port, 5900, "no such port, so the usual one")
        XCTAssertEqual(VNCSettings(address: "desk:99999").host, "desk")
    }
}
