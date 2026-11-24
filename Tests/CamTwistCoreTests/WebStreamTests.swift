import XCTest
@testable import CamTwistCore

final class WebStreamTests: XCTestCase {
    func testSettingsStartOffOnTheDefaultPortAndHoldThePortInRange() {
        let settings = WebStreamSettings()
        XCTAssertFalse(settings.isOn)
        XCTAssertEqual(settings.usablePort, WebStreamSettings.defaultPort)
        XCTAssertEqual(WebStreamSettings(port: 80).usablePort, 1024)
        XCTAssertEqual(WebStreamSettings(port: 99999).usablePort, 65535)
        XCTAssertEqual(settings.options, .web)
        var changed = settings
        changed.options.height = 360
        XCTAssertEqual(changed.options.height, 360)
        let old = try? JSONDecoder().decode(WebStreamSettings.self, from: Data(#"{"isOn":true,"port":9000}"#.utf8))
        XCTAssertEqual(old?.options, .web, "settings saved before streams had options still load")
        let server = try? JSONDecoder().decode(
            RTMPSettings.self, from: Data(#"{"isOn":false,"address":"","streamKey":""}"#.utf8)
        )
        XCTAssertEqual(server?.options, .server)
        var stream = RTMPSettings()
        stream.options.videoKilobits = 6000
        XCTAssertEqual(stream.options.videoKilobits, 6000)
    }

    func testTheWindowKeepsTheLastFewPiecesAndNumbersThemOn() {
        var window = SegmentWindow()
        XCTAssertNil(window.initialization)
        window.setInitialization(Data([1]))
        for index in 0..<8 {
            let segment = window.append(Data([UInt8(index)]), duration: 1)
            XCTAssertEqual(segment.sequence, index)
        }
        XCTAssertEqual(window.initialization, Data([1]))
        XCTAssertEqual(window.segments.map(\.sequence), [2, 3, 4, 5, 6, 7])
        XCTAssertEqual(window.segment(numbered: 7)?.data, Data([7]))
        XCTAssertNil(window.segment(numbered: 1), "it has fallen off the end")
    }

    func testTheWindowKeepsAsManyPiecesAsItIsGiven() {
        var window = SegmentWindow(capacity: 2)
        for index in 0..<5 {
            window.append(Data([UInt8(index)]), duration: 1)
        }
        XCTAssertEqual(window.segments.map(\.sequence), [3, 4])
    }

    func testThePlaylistListsThePiecesInTheWindow() {
        var window = SegmentWindow()
        XCTAssertEqual(HLSPlaylist.text(for: window), """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:1
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-MAP:URI="init.mp4"

        """)
        window.append(Data(), duration: 1)
        window.append(Data(), duration: 1.5)
        XCTAssertEqual(HLSPlaylist.text(for: window), """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:2
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-MAP:URI="init.mp4"
        #EXTINF:1.000,
        segment-0.m4s
        #EXTINF:1.500,
        segment-1.m4s

        """)
    }

    func testSceneChangesAreMarkedInThePlaylistOnceTheStreamsBeginningIsKnown() {
        var window = SegmentWindow()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        window.mark(scene: "Early", at: start)
        XCTAssertFalse(HLSPlaylist.text(for: window).contains("DATERANGE"), "no beginning yet, so nothing to place")

        window.setOrigin(start)
        window.setOrigin(start.addingTimeInterval(99))
        XCTAssertEqual(window.origin, start, "the beginning is set once")
        XCTAssertNil(window.firstSegmentDate, "no pieces yet")
        window.append(Data(), duration: 1)
        window.mark(scene: "Camera \"wide\"\nshot", at: start.addingTimeInterval(0.5))
        let text = HLSPlaylist.text(for: window)
        XCTAssertTrue(text.contains("#EXT-X-PROGRAM-DATE-TIME:2027-01-15T08:00:00.000Z"))
        XCTAssertTrue(text.contains("#EXT-X-DATERANGE:ID=\"scene-0\",START-DATE=\"2027-01-15T08:00:00.000Z\",X-SCENE=\"Early\""))
        XCTAssertTrue(text.contains(
            "#EXT-X-DATERANGE:ID=\"scene-1\",START-DATE=\"2027-01-15T08:00:00.500Z\",X-SCENE=\"Camera wideshot\""
        ))

        // As pieces fall off the front, so do the markers from before them,
        // bar the latest, which says what scene the stream is on.
        for _ in 0..<8 { window.append(Data(), duration: 1) }
        XCTAssertEqual(window.markers.map(\.name), ["Camera \"wide\"\nshot"])
        XCTAssertEqual(window.firstSegmentDate, start.addingTimeInterval(3))
        window.mark(scene: "Late", at: start.addingTimeInterval(8))
        XCTAssertEqual(window.markers.map(\.number), [1, 2])
    }

    func testAnEventBoxCarriesASceneChange() {
        let box = EventMessageBox.data(scene: "Wide", number: 3, atSeconds: 2.5)
        XCTAssertEqual(box.count, Int(box[3]), "the box says how long it is")
        XCTAssertEqual(String(decoding: box[4..<8], as: UTF8.self), "emsg")
        XCTAssertEqual(box[8], 1, "the version that carries a moment in the stream")
        XCTAssertEqual(Array(box[12..<16]), [0, 0, 0x03, 0xE8], "times are in milliseconds")
        XCTAssertEqual(Array(box[16..<24]), [0, 0, 0, 0, 0, 0, 0x09, 0xC4], "2500 milliseconds in")
        XCTAssertEqual(Array(box[28..<32]), [0, 0, 0, 3])
        XCTAssertTrue(String(decoding: box, as: UTF8.self).contains("urn:camtwisted:scene"))
        XCTAssertTrue(box.suffix(4).elementsEqual(Data("Wide".utf8)))
        XCTAssertEqual(Array(EventMessageBox.data(scene: "", number: 0, atSeconds: -1)[16..<24]), [0, 0, 0, 0, 0, 0, 0, 0])
    }

    func testAddressesAreReadAsWhatTheyAskFor() {
        XCTAssertEqual(WebStreamRoute(path: "/"), .page)
        XCTAssertEqual(WebStreamRoute(path: ""), .page)
        XCTAssertEqual(WebStreamRoute(path: "/stream.m3u8?_=123"), .playlist)
        XCTAssertEqual(WebStreamRoute(path: "/init.mp4"), .initialization)
        XCTAssertEqual(WebStreamRoute(path: "/stream.mp4"), .movie)
        XCTAssertEqual(WebStreamRoute(path: "/segment-42.m4s"), .segment(42))
        XCTAssertEqual(WebStreamRoute(path: "/segment-x.m4s"), .unknown)
        XCTAssertEqual(WebStreamRoute(path: "/favicon.ico"), .unknown)
        XCTAssertEqual(WebStreamRoute.segmentName(3), "segment-3.m4s")
    }

    func testARequestLineIsRead() {
        let request = HTTPRequest(Data("GET /stream.m3u8 HTTP/1.1\r\nHost: example\r\n\r\n".utf8))
        XCTAssertEqual(request?.method, "GET")
        XCTAssertEqual(request?.path, "/stream.m3u8")
        XCTAssertNil(HTTPRequest(Data("hello\r\n".utf8)))
        XCTAssertNil(HTTPRequest(Data([0xFF, 0xFE, 0xFD])))
    }

    func testAnAnswerHasItsHeadersThenItsBody() {
        let answer = HTTPResponse(contentType: .playlist, body: Data("abc".utf8))
        let text = String(decoding: answer.data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\nContent-Type: application/vnd.apple.mpegurl\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 3\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\nabc"))

        let missing = String(decoding: HTTPResponse.missing.data, as: UTF8.self)
        XCTAssertTrue(missing.hasPrefix("HTTP/1.1 404 Not Found\r\n"))

        let endless = String(decoding: HTTPResponse.head(contentType: .video, length: nil), as: UTF8.self)
        XCTAssertFalse(endless.contains("Content-Length"))
        XCTAssertTrue(endless.hasSuffix("Connection: close\r\n\r\n"))
        XCTAssertTrue(
            String(decoding: HTTPResponse.head(status: 500, contentType: .text, length: 0), as: UTF8.self)
                .hasPrefix("HTTP/1.1 500 \r\n")
        )
    }

    func testThePagePlaysThePlaylist() {
        let page = WebStreamPage.html(title: "Camera")
        XCTAssertTrue(page.contains("<title>Camera</title>"))
        XCTAssertTrue(page.contains("src=\"stream.m3u8\""))
    }
}
