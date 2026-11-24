import AVFoundation
import CamTwistCore
import CoreMedia
import CoreVideo
import XCTest
@testable import CamTwistRendering

private final class FakeServer: StreamServing {
    var port: Int?
    var handler: ((HTTPRequest) -> StreamReply)?
    var onFailure: ((String) -> Void)?
    var stops = 0
    var broadcasts: [Data] = []

    func start(port: Int, handler: @escaping (HTTPRequest) -> StreamReply, onFailure: @escaping (String) -> Void) {
        self.port = port
        self.handler = handler
        self.onFailure = onFailure
    }

    func stop() { stops += 1 }
    func broadcast(_ data: Data) { broadcasts.append(data) }
}

private final class FakeEncoder: SegmentEncoding {
    let size: CGSize
    let encoding: StreamEncoding
    let sound: SoundFormat?
    let callbacks: SegmentCallbacks
    var times: [Double] = []
    var soundOrigins: [Double] = []
    var isFinished = false

    init(plan: WebStreamOutput.EncoderPlan, callbacks: SegmentCallbacks) {
        size = plan.size
        encoding = plan.encoding
        sound = plan.sound
        self.callbacks = callbacks
    }

    func append(_ pixelBuffer: CVPixelBuffer, at seconds: Double) { times.append(seconds) }
    func appendSound(_ sound: CMSampleBuffer, startingFrom origin: Double) { soundOrigins.append(origin) }
    func finish() { isFinished = true }
}

private func makeBuffer(width: Int = 64, height: Int = 64) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    ] as CFDictionary, &buffer)
    return buffer!
}

final class WebStreamOutputTests: XCTestCase {
    private let server = FakeServer()
    private var encoders: [FakeEncoder] = []
    private var now = 100.0
    private lazy var output = make(.hls)
    private lazy var movie = make(.movie)

    private func make(_ kind: WebStreamKind) -> WebStreamOutput {
        WebStreamOutput(
            kind: kind, title: "Camera", canvas: CGSize(width: 1280, height: 720), framesPerSecond: 30,
            server: server,
            makeEncoder: { [unowned self] in
                let encoder = FakeEncoder(plan: $0, callbacks: $1)
                self.encoders.append(encoder)
                return encoder
            },
            clock: { [unowned self] in self.now },
            today: { [unowned self] in Date(timeIntervalSince1970: 1_800_000_000 + self.now) }
        )
    }

    private func body(_ reply: StreamReply) -> (status: Int, text: String)? {
        guard case .whole(let response) = reply else { return nil }
        return (response.status, String(decoding: response.body, as: UTF8.self))
    }

    private func get(_ path: String) -> StreamReply {
        output.reply(to: HTTPRequest(Data("GET \(path) HTTP/1.1\r\n\r\n".utf8))!)
    }

    func testSwitchedOffNothingIsEncodedOrServed() {
        XCTAssertEqual(output.status, .off)
        output.send(makeBuffer())
        output.apply(WebStreamSettings(), withSound: false)
        output.send(makeBuffer())
        XCTAssertTrue(encoders.isEmpty)
        XCTAssertNil(server.port)
    }

    func testEachKindOfStreamAnswersItsOwnAddresses() {
        output.apply(WebStreamSettings(isOn: true, port: 9000), withSound: false)
        XCTAssertEqual(body(get("/stream.m3u8"))?.status, HTTPResponse.ok)
        XCTAssertEqual(body(get("/stream.mp4"))?.status, HTTPResponse.notFound)

        movie.apply(WebStreamSettings(isOn: true, port: 9001), withSound: false)
        let request = HTTPRequest(Data("GET /stream.mp4 HTTP/1.1\r\n\r\n".utf8))!
        guard case .live = movie.reply(to: request) else { return XCTFail("the movie is served") }
        let playlist = HTTPRequest(Data("GET /stream.m3u8 HTTP/1.1\r\n\r\n".utf8))!
        XCTAssertEqual(body(movie.reply(to: playlist))?.status, HTTPResponse.notFound)
    }

    func testTheEncoderIsMadeFromTheStreamsOptions() {
        var settings = WebStreamSettings(isOn: true, port: 9000)
        settings.options = StreamOptions(
            height: 360, videoKilobits: 1500, keyFrameSeconds: 3, soundKilobits: 96, soundChannels: 1, sampleRate: 44100,
            codec: .hevc
        )
        output.apply(settings, withSound: true)
        output.send(TestSound.buffer(at: 99))
        output.send(makeBuffer())
        XCTAssertEqual(encoders.first?.size, CGSize(width: 640, height: 360))
        XCTAssertEqual(
            encoders.first?.encoding,
            StreamEncoding(segmentSeconds: 3, bitsPerSecond: 1_500_000, framesPerSecond: 30, codec: .hevc)
        )
        XCTAssertEqual(encoders.first?.sound, SoundFormat(sampleRate: 44100, channels: 1, bitsPerSecond: 96000))
    }

    func testSwitchedOnTheStreamBeginsWithItsFirstFrameAndPiecesAreServed() {
        output.apply(WebStreamSettings(isOn: true, port: 9000), withSound: false)
        XCTAssertEqual(output.status, .running)
        XCTAssertEqual(server.port, 9000)
        XCTAssertTrue(encoders.isEmpty, "nothing is encoded until there is a frame")
        output.send(makeBuffer())
        now = 100.5
        output.send(makeBuffer())
        XCTAssertEqual(encoders.count, 1)
        XCTAssertEqual(encoders.first?.times, [0, 0.5])
        XCTAssertNil(encoders.first?.sound)
        output.send(TestSound.buffer(at: 100.6))
        XCTAssertEqual(encoders.first?.soundOrigins, [], "sound that was not asked for is left out")

        XCTAssertEqual(body(get("/init.mp4"))?.status, HTTPResponse.notFound, "no header yet")

        encoders.first?.callbacks.initialization(Data("head".utf8))
        encoders.first?.callbacks.segment(Data("one".utf8), 1)
        XCTAssertEqual(server.broadcasts, [Data("head".utf8), Data("one".utf8)])
        XCTAssertEqual(body(get("/init.mp4"))?.text, "head")
        XCTAssertEqual(body(get("/segment-0.m4s"))?.text, "one")
        XCTAssertEqual(body(get("/segment-9.m4s"))?.status, HTTPResponse.notFound)
        XCTAssertEqual(body(get("/stream.m3u8"))?.text.contains("segment-0.m4s"), true)
        XCTAssertEqual(body(get("/"))?.text.contains("<title>Camera</title>"), true)
        XCTAssertEqual(body(get("/nothing"))?.status, HTTPResponse.notFound)

        // The server's own handler is the same thing.
        XCTAssertEqual(server.handler.map { body($0(HTTPRequest(Data("GET /init.mp4 HTTP/1.1\r\n".utf8))!))?.text }, "head")
    }

    func testTheEndlessMovieSendsItsHeaderFirstToWhoeverJoins() {
        movie.apply(WebStreamSettings(isOn: true, port: 9001), withSound: false)
        let request = HTTPRequest(Data("GET /stream.mp4 HTTP/1.1\r\n\r\n".utf8))!
        guard case .live(let early) = movie.reply(to: request) else { return XCTFail("the movie is a live answer") }
        XCTAssertTrue(String(decoding: early, as: UTF8.self).hasSuffix("\r\n\r\n"), "headers only so far")
        movie.send(makeBuffer())
        encoders.first?.callbacks.initialization(Data("head".utf8))
        guard case .live(let later) = movie.reply(to: request) else { return XCTFail("the movie is a live answer") }
        XCTAssertTrue(String(decoding: later, as: UTF8.self).hasSuffix("head"), "a late player gets the header first")
    }

    func testAnHLSStreamNotesSceneChangesInItsPlaylistWhenSetTo() {
        var settings = WebStreamSettings(isOn: true, port: 9000)
        output.apply(settings, withSound: false)
        output.send(makeBuffer())
        encoders.first?.callbacks.segment(Data("one".utf8), 1)
        output.markScene(named: "Wide")
        XCTAssertEqual(body(get("/stream.m3u8"))?.text.contains("X-SCENE"), false, "not set to mark them")

        settings.options.marksScenes = true
        output.apply(settings, withSound: false)
        output.send(makeBuffer())
        now = 101
        encoders.last?.callbacks.segment(Data("one".utf8), 1)
        output.markScene(named: "Wide")
        let playlist = body(get("/stream.m3u8"))?.text ?? ""
        XCTAssertTrue(playlist.contains("#EXT-X-PROGRAM-DATE-TIME:"), playlist)
        XCTAssertTrue(playlist.contains("X-SCENE=\"Wide\""), playlist)
        XCTAssertTrue(server.broadcasts.allSatisfy { $0 == Data("one".utf8) }, "an HLS stream sends no event box")
    }

    func testAnEndlessMovieCarriesSceneChangesAsEventsOnceItHasBegun() {
        var settings = WebStreamSettings(isOn: true, port: 9001)
        settings.options.marksScenes = true
        movie.apply(settings, withSound: false)
        movie.markScene(named: "Early")
        XCTAssertEqual(server.broadcasts, [], "no frame yet, so no time in the stream to place it at")
        movie.send(makeBuffer())
        now = 102.5
        movie.markScene(named: "Wide")
        XCTAssertEqual(server.broadcasts, [EventMessageBox.data(scene: "Wide", number: 2, atSeconds: 2.5)])

        movie.apply(WebStreamSettings(isOn: false, port: 9001), withSound: false)
        movie.markScene(named: "Off")
        XCTAssertEqual(server.broadcasts.count, 1, "switched off, nothing is marked")
    }

    func testAStreamWithSoundWaitsToHearSomeAndThenCarriesIt() {
        output.apply(WebStreamSettings(isOn: true, port: 9000), withSound: true)
        output.send(makeBuffer())
        now = 101
        output.send(makeBuffer())
        XCTAssertTrue(encoders.isEmpty, "it holds on to hear whether there is any sound")
        output.send(TestSound.buffer(at: 101.1))
        now = 101.2
        output.send(makeBuffer())
        XCTAssertEqual(encoders.count, 1)
        XCTAssertEqual(encoders.first?.sound, StreamOptions.web.sound)
        XCTAssertEqual(encoders.first?.times, [0])
        output.send(TestSound.buffer(at: 101.3))
        XCTAssertEqual(encoders.first?.soundOrigins, [101.2], "sound is placed from when the stream began")
    }

    func testAStreamThatHearsNothingStartsWithoutSound() {
        output.apply(WebStreamSettings(isOn: true, port: 9000), withSound: true)
        output.send(makeBuffer())
        now = 102.5
        output.send(makeBuffer())
        XCTAssertEqual(encoders.count, 1, "after two seconds of silence it stops waiting")
        XCTAssertNil(encoders.first?.sound)
        output.send(TestSound.buffer(at: 102.6))
        XCTAssertEqual(encoders.first?.soundOrigins, [])

        // Sound having been heard, the next stream to start has it at once.
        output.apply(WebStreamSettings(isOn: true, port: 9001), withSound: true)
        output.send(makeBuffer())
        XCTAssertEqual(encoders.count, 2)
        XCTAssertEqual(encoders.last?.sound, StreamOptions.web.sound)
    }

    func testAChangeOfPortOrOfSoundStartsAgainAndSwitchingOffStops() {
        output.apply(WebStreamSettings(isOn: true, port: 9000), withSound: false)
        output.apply(WebStreamSettings(isOn: true, port: 9000), withSound: false)
        output.send(makeBuffer())
        XCTAssertEqual(encoders.count, 1, "the same settings change nothing")
        encoders.first?.callbacks.segment(Data("one".utf8), 1)

        output.apply(WebStreamSettings(isOn: true, port: 9001), withSound: false)
        XCTAssertEqual(server.stops, 1)
        XCTAssertEqual(encoders.first?.isFinished, true)
        XCTAssertEqual(server.port, 9001)
        XCTAssertEqual(body(get("/segment-0.m4s"))?.status, HTTPResponse.notFound, "the old pieces are gone")
        output.send(makeBuffer())
        XCTAssertEqual(encoders.count, 2)

        output.apply(WebStreamSettings(isOn: true, port: 9001), withSound: true)
        XCTAssertEqual(server.stops, 2, "sound switched on is a new stream")

        output.apply(WebStreamSettings(isOn: false, port: 9001), withSound: true)
        XCTAssertEqual(output.status, .off)
        XCTAssertEqual(server.stops, 3)
        output.send(makeBuffer())
        XCTAssertEqual(encoders.last?.times, [0])
    }

    func testAFailureToListenIsReported() {
        output.apply(WebStreamSettings(isOn: true, port: 80), withSound: false)
        XCTAssertEqual(server.port, WebStreamSettings.portRange.lowerBound, "held to a port an app may use")
        server.onFailure?("Address already in use")
        XCTAssertEqual(output.status, .failed("Address already in use"))
    }

    func testAnOutputThatHasGoneAnswersNothing() {
        var made: [FakeEncoder] = []
        var gone: WebStreamOutput? = WebStreamOutput(
            kind: .hls, title: "Camera", canvas: CGSize(width: 1280, height: 720), framesPerSecond: 30,
            server: server,
            makeEncoder: {
                let encoder = FakeEncoder(plan: $0, callbacks: $1)
                made.append(encoder)
                return encoder
            },
            clock: { 0 }, today: Date.init
        )
        gone?.apply(WebStreamSettings(isOn: true), withSound: false)
        gone?.send(makeBuffer())
        gone = nil
        let reply = server.handler?(HTTPRequest(Data("GET / HTTP/1.1\r\n".utf8))!)
        XCTAssertEqual(reply.flatMap(body)?.status, HTTPResponse.notFound)
        made.first?.callbacks.initialization(Data([1]))
        made.first?.callbacks.segment(Data([2]), 1)
        server.onFailure?("gone")
        XCTAssertEqual(server.broadcasts, [])
    }
}

final class SegmentedEncoderTests: XCTestCase {
    func testFramesComeOutAsAHeaderAndPieces() {
        let lock = NSLock()
        var header: Data?
        var pieces: [(data: Data, duration: Double)] = []
        let gotPiece = expectation(description: "a piece is made")
        gotPiece.assertForOverFulfill = false
        let encoder = SegmentedEncoder(
            size: CGSize(width: 64, height: 64),
            encoding: StreamEncoding(segmentSeconds: 0.5, bitsPerSecond: 500_000, framesPerSecond: 30),
            sound: nil,
            callbacks: SegmentCallbacks(
                initialization: { data in lock.lock(); header = data; lock.unlock() },
                segment: { data, duration in
                    lock.lock(); pieces.append((data, duration)); lock.unlock()
                    gotPiece.fulfill()
                }
            )
        )
        let buffer = makeBuffer()
        for frame in 0..<60 {
            encoder.append(buffer, at: Double(frame) / 30)
            usleep(2000)
        }
        encoder.finish()
        wait(for: [gotPiece], timeout: 15)
        lock.lock()
        defer { lock.unlock() }
        XCTAssertGreaterThan(header?.count ?? 0, 100)
        XCTAssertEqual(pieces.first?.duration, 0.5)
        // A fragmented MP4 header starts with a file type box, and each piece with a movie fragment.
        XCTAssertEqual(header.map { String(decoding: $0[4..<8], as: UTF8.self) }, "ftyp")
        XCTAssertEqual(pieces.first.map { String(decoding: $0.data.prefix(64), as: UTF8.self).contains("moof") }, true)
    }

    func testHEVCComesOutInAHeaderThatSaysSo() {
        let lock = NSLock()
        var header = Data()
        let gotPiece = expectation(description: "a piece is made")
        gotPiece.assertForOverFulfill = false
        let encoder = SegmentedEncoder(
            size: CGSize(width: 64, height: 64),
            encoding: StreamEncoding(segmentSeconds: 0.5, bitsPerSecond: 500_000, framesPerSecond: 30, codec: .hevc),
            sound: nil,
            callbacks: SegmentCallbacks(
                initialization: { data in lock.lock(); header = data; lock.unlock() },
                segment: { _, _ in gotPiece.fulfill() }
            )
        )
        let buffer = makeBuffer()
        for frame in 0..<60 {
            encoder.append(buffer, at: Double(frame) / 30)
            usleep(2000)
        }
        encoder.finish()
        wait(for: [gotPiece], timeout: 15)
        lock.lock()
        defer { lock.unlock() }
        XCTAssertTrue(String(decoding: header, as: UTF8.self).contains("hvc1"), "the header names HEVC")
    }

    func testFramesAndSoundComeOutTogetherInThePieces() {
        let lock = NSLock()
        var header: Data?
        var pieces = 0
        let gotPiece = expectation(description: "a piece with sound is made")
        gotPiece.assertForOverFulfill = false
        let encoder = SegmentedEncoder(
            size: CGSize(width: 64, height: 64),
            encoding: StreamEncoding(segmentSeconds: 0.5, bitsPerSecond: 500_000, framesPerSecond: 30),
            sound: SoundFormat(sampleRate: 48000, channels: 2, bitsPerSecond: 96000),
            callbacks: SegmentCallbacks(
                initialization: { data in lock.lock(); header = data; lock.unlock() },
                segment: { _, _ in
                    lock.lock(); pieces += 1; lock.unlock()
                    gotPiece.fulfill()
                }
            )
        )
        let buffer = makeBuffer()
        // The stream began at 50 seconds on the sound's clock. Sound from
        // before then is dropped; the rest runs alongside the frames.
        encoder.appendSound(TestSound.buffer(at: 49.5), startingFrom: 50)
        let packet = 1024.0 / TestSound.rate
        var soundTime = 50.0
        for frame in 0..<60 {
            encoder.append(buffer, at: Double(frame) / 30)
            while soundTime < 50 + Double(frame + 1) / 30 {
                encoder.appendSound(TestSound.buffer(at: soundTime), startingFrom: 50)
                soundTime += packet
            }
            usleep(2000)
        }
        encoder.finish()
        wait(for: [gotPiece], timeout: 15)
        lock.lock()
        defer { lock.unlock() }
        // The header describes two tracks: the picture and the sound.
        let text = header.map { String(decoding: $0, as: UTF8.self) } ?? ""
        XCTAssertTrue(text.contains("mp4a"), "the header names an AAC sound track")
        XCTAssertTrue(text.contains("avc1"))
        XCTAssertGreaterThan(pieces, 0)
    }

    func testTheRealOutputServesItsPageAndPlaylistOverTheNetwork() throws {
        let port = 18_973
        let output = WebStreamOutput(
            kind: .hls, title: "Camera", canvas: CGSize(width: 1280, height: 720), framesPerSecond: 30,
            piecesKept: Pacing.usual.streamPiecesKept, longestWaitForSound: Pacing.usual.longestWaitForSound,
            largestRequest: Pacing.usual.webLargestRequest, queues: DispatchQueues(), clocks: .system
        )
        var settings = WebStreamSettings(isOn: true, port: port)
        // Small and with short pieces, so the test is quick. The frames fed
        // in are a different size from the stream's, and are scaled to fit.
        settings.options = StreamOptions(height: 360, videoKilobits: 500, keyFrameSeconds: 0.5)
        output.apply(settings, withSound: false)
        XCTAssertEqual(output.status, .running)
        let buffer = makeBuffer()

        func fetch(_ path: String) -> (status: Int, body: String)? {
            var result: (Int, String)?
            let done = expectation(description: path)
            let url = URL(string: "http://127.0.0.1:\(port)/\(path)")!
            URLSession(configuration: .ephemeral).dataTask(with: url) { data, response, _ in
                if let data, let response = response as? HTTPURLResponse {
                    result = (response.statusCode, String(decoding: data, as: UTF8.self))
                }
                done.fulfill()
            }.resume()
            wait(for: [done], timeout: 10)
            return result
        }

        // Frames go in until a piece appears in the playlist.
        var playlist: (status: Int, body: String)?
        for _ in 0..<40 where playlist?.body.contains("segment-0.m4s") != true {
            for _ in 0..<8 {
                output.send(buffer)
                usleep(33_000)
            }
            playlist = fetch("stream.m3u8")
        }
        XCTAssertEqual(playlist?.status, 200)
        XCTAssertEqual(playlist?.body.contains("segment-0.m4s"), true)
        XCTAssertEqual(fetch("")?.body.contains("<video"), true)
        XCTAssertEqual(fetch("nothing-here")?.status, 404)

        output.apply(WebStreamSettings(isOn: false, port: port), withSound: false)
        XCTAssertEqual(output.status, .off)
    }
}
