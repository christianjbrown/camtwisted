import CamTwistCore
import CoreMedia
import CoreVideo
import XCTest
@testable import CamTwistRendering

private final class FakeConnection: StreamConnecting {
    var target: RTMPTarget?
    var onReady: (() -> Void)?
    var onReceive: ((Data) -> Void)?
    var onFailure: ((String) -> Void)?
    var sent: [Data] = []
    var isClosed = false

    func open(
        to target: RTMPTarget, onReady: @escaping () -> Void, onReceive: @escaping (Data) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        self.target = target
        self.onReady = onReady
        self.onReceive = onReceive
        self.onFailure = onFailure
    }

    func send(_ data: Data) { sent.append(data) }
    func close() { isClosed = true }
}

private final class FakeFrameEncoder: FrameEncoding {
    let size: CGSize
    let encoding: StreamEncoding
    let output: (EncodedFrame) -> Void
    var times: [UInt32] = []
    var isFinished = false

    init(size: CGSize, encoding: StreamEncoding, output: @escaping (EncodedFrame) -> Void) {
        self.size = size
        self.encoding = encoding
        self.output = output
    }

    func encode(_ pixelBuffer: CVPixelBuffer, atMilliseconds milliseconds: UInt32) { times.append(milliseconds) }
    func finish() { isFinished = true }
}

private final class FakeSoundEncoder: SoundEncoding {
    /// The packets handed back for each buffer of sound, in turn.
    var packets: [[Data]] = []
    func encode(_ sound: CMSampleBuffer) -> [Data] {
        packets.isEmpty ? [] : packets.removeFirst()
    }
}

private func makeFrameBuffer(_ side: Int = 64) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32BGRA, [
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    ] as CFDictionary, &buffer)
    return buffer!
}

final class RTMPOutputTests: XCTestCase {
    private var connections: [FakeConnection] = []
    private var encoders: [FakeFrameEncoder] = []
    private var soundEncoders: [FakeSoundEncoder] = []
    private var soundFormats: [SoundFormat] = []
    private var now = 10.0
    private lazy var output = RTMPOutput(
        canvas: CGSize(width: 1280, height: 720), framesPerSecond: 30,
        makeConnection: { [unowned self] in
            let connection = FakeConnection()
            self.connections.append(connection)
            return connection
        },
        makeEncoder: { [unowned self] in
            let encoder = FakeFrameEncoder(size: $0, encoding: $1, output: $2)
            self.encoders.append(encoder)
            return encoder
        },
        makeSoundEncoder: { [unowned self] format in
            let encoder = FakeSoundEncoder()
            self.soundEncoders.append(encoder)
            self.soundFormats.append(format)
            return encoder
        },
        clock: { [unowned self] in self.now }
    )
    private let settings = RTMPSettings(isOn: true, address: "rtmp://example.com/live", streamKey: "key")

    private func serverCommand(_ values: [AMF0Value]) -> Data {
        RTMPChunkWriter.chunks(
            for: RTMPMessage(typeID: RTMPMessage.Kind.command, payload: AMF0.encode(values)),
            chunkStreamID: 3, chunkSize: 128
        )
    }

    /// Plays the server's side until the stream is live.
    private func goLive(withSound: Bool = false) {
        output.apply(settings, withSound: withSound)
        let connection = connections[0]
        connection.onReady?()
        connection.onReceive?(Data([3]) + Data(count: 1536 * 2))
        connection.onReceive?(serverCommand([.string("_result"), .number(1), .null, .null]))
        connection.onReceive?(serverCommand([.string("_result"), .number(4), .null, .number(1)]))
        connection.onReceive?(serverCommand([
            .string("onStatus"), .number(0), .null,
            .object([AMF0Property("code", .string("NetStream.Publish.Start"))]),
        ]))
    }

    func testSwitchedOffNothingIsOpened() {
        XCTAssertEqual(output.status, .idle)
        output.apply(RTMPSettings(), withSound: false)
        output.apply(RTMPSettings(isOn: false, address: "rtmp://example.com/live", streamKey: "key"), withSound: false)
        output.send(makeFrameBuffer())
        XCTAssertTrue(connections.isEmpty)
        XCTAssertEqual(output.status, .idle)
    }

    func testAnAddressThatIsNotRTMPIsReported() {
        output.apply(RTMPSettings(isOn: true, address: "https://example.com", streamKey: "key"), withSound: false)
        XCTAssertEqual(
            output.status, .failed("Enter a server address that starts rtmp:// or rtmps://, and a stream key")
        )
        XCTAssertTrue(connections.isEmpty)
    }

    func testItConnectsTalksToTheServerAndGoesLive() {
        output.apply(settings, withSound: false)
        output.apply(settings, withSound: false)
        XCTAssertEqual(connections.count, 1, "the same settings change nothing")
        XCTAssertEqual(connections[0].target?.host, "example.com")
        XCTAssertEqual(output.status, .connecting)
        output.send(makeFrameBuffer())
        XCTAssertEqual(encoders[0].times, [], "nothing is compressed until the server is taking the stream")

        goLive()
        XCTAssertEqual(output.status, .live)
        XCTAssertEqual(connections[0].sent.first?.count, 1 + 1536, "the handshake went out first")
        XCTAssertGreaterThan(connections[0].sent.count, 3)
    }

    func testFramesAreTimedFromTheFirstAndTheDecoderDetailsGoFirst() {
        goLive()
        output.send(makeFrameBuffer())
        now = 10.5
        output.send(makeFrameBuffer())
        XCTAssertEqual(encoders[0].times, [0, 500])

        let before = connections[0].sent.count
        // A frame with no decoder details, before any key frame, is no use and is not sent.
        encoders[0].output(EncodedFrame(data: Data([1]), isKeyFrame: false, milliseconds: 0, parameterSets: nil))
        XCTAssertEqual(connections[0].sent.count, before)
        // Nor is one whose details are too short to read.
        encoders[0].output(EncodedFrame(
            data: Data([1]), isKeyFrame: true, milliseconds: 0, parameterSets: (Data([0x67]), Data([0x68]))
        ))
        XCTAssertEqual(connections[0].sent.count, before)

        let sets = (sequence: Data([0x67, 0x64, 0x00, 0x1F]), picture: Data([0x68, 0xEE]))
        encoders[0].output(EncodedFrame(data: Data([9, 9]), isKeyFrame: true, milliseconds: 33, parameterSets: sets))
        encoders[0].output(EncodedFrame(data: Data([8, 8]), isKeyFrame: false, milliseconds: 66, parameterSets: nil))

        var reader = RTMPChunkReader()
        _ = reader.append(RTMPChunkWriter.chunks(
            for: RTMPMessage(typeID: 1, payload: Data([0, 0, 0x10, 0])), chunkStreamID: 2, chunkSize: 128
        ))
        let video = connections[0].sent.dropFirst(before).flatMap { reader.append($0) }
        XCTAssertEqual(video.map(\.typeID), [9, 9, 9])
        XCTAssertEqual(video.map(\.timestamp), [33, 33, 66])
        XCTAssertEqual(video[0].payload.prefix(2), Data([0x17, 0x00]), "the decoder's details")
        XCTAssertEqual(video[1].payload, Data([0x17, 0x01, 0, 0, 0, 9, 9]))
        XCTAssertEqual(video[2].payload, Data([0x27, 0x01, 0, 0, 0, 8, 8]))
    }

    func testSoundJoinsOncePictureHasStartedWithItsDetailsFirst() {
        goLive(withSound: true)
        let encoder = soundEncoders[0]
        encoder.packets = [[Data([1])]]
        output.send(TestSound.buffer(at: 10))
        XCTAssertTrue(encoder.packets.count == 1, "no sound is taken before the picture starts")

        output.send(makeFrameBuffer())
        let before = connections[0].sent.count
        // The picture began at 10 seconds. Sound made half a second later
        // lands at 500 milliseconds, and each packet after it one packet on.
        encoder.packets = [[Data([1]), Data([2])], [], [Data([3])]]
        output.send(TestSound.buffer(at: 10.5))
        output.send(TestSound.buffer(at: 10.6))
        output.send(TestSound.buffer(at: 99))

        var reader = RTMPChunkReader()
        _ = reader.append(RTMPChunkWriter.chunks(
            for: RTMPMessage(typeID: 1, payload: Data([0, 0, 0x10, 0])), chunkStreamID: 2, chunkSize: 128
        ))
        let audio = connections[0].sent.dropFirst(before).flatMap { reader.append($0) }
        XCTAssertEqual(audio.map(\.typeID), [8, 8, 8, 8])
        XCTAssertEqual(audio.map(\.payload), [
            Data([0xAF, 0x00, 0x11, 0x90]), Data([0xAF, 0x01, 1]), Data([0xAF, 0x01, 2]), Data([0xAF, 0x01, 3]),
        ])
        XCTAssertEqual(audio.map(\.timestamp), [500, 500, 521, 542])
    }

    func testAStreamWithoutSoundIgnoresTheMicrophoneAndSoundSwitchedOnStartsAfresh() {
        goLive()
        output.send(makeFrameBuffer())
        let before = connections[0].sent.count
        output.send(TestSound.buffer(at: 10.5))
        XCTAssertEqual(connections[0].sent.count, before)
        XCTAssertTrue(soundEncoders.isEmpty)

        output.apply(settings, withSound: true)
        XCTAssertTrue(connections[0].isClosed)
        XCTAssertEqual(connections.count, 2)
        XCTAssertEqual(soundEncoders.count, 1)
    }

    func testTheEncodersAreMadeFromTheStreamsOptions() {
        var chosen = settings
        chosen.options = StreamOptions(
            height: 480, videoKilobits: 2500, keyFrameSeconds: 4, soundKilobits: 192, soundChannels: 1, sampleRate: 44100
        )
        output.apply(chosen, withSound: true)
        XCTAssertEqual(encoders.first?.size, CGSize(width: 854, height: 480))
        XCTAssertEqual(
            encoders.first?.encoding, StreamEncoding(segmentSeconds: 4, bitsPerSecond: 2_500_000, framesPerSecond: 30)
        )
        XCTAssertEqual(soundFormats, [SoundFormat(sampleRate: 44100, channels: 1, bitsPerSecond: 192_000)])
    }

    func testSceneChangesGoOutAsCuePointsWhenSetToAndLive() {
        var marking = settings
        marking.options.marksScenes = true
        output.apply(marking, withSound: false)
        output.markScene(named: "Early")
        let connection = connections[0]
        connection.onReady?()
        connection.onReceive?(Data([3]) + Data(count: 1536 * 2))
        connection.onReceive?(serverCommand([.string("_result"), .number(1), .null, .null]))
        connection.onReceive?(serverCommand([.string("_result"), .number(4), .null, .number(1)]))
        connection.onReceive?(serverCommand([
            .string("onStatus"), .number(0), .null,
            .object([AMF0Property("code", .string("NetStream.Publish.Start"))]),
        ]))
        output.markScene(named: "No picture yet")
        output.send(makeFrameBuffer())
        let before = connection.sent.count
        now = 12.5
        output.markScene(named: "Wide")

        var reader = RTMPChunkReader()
        _ = reader.append(RTMPChunkWriter.chunks(
            for: RTMPMessage(typeID: 1, payload: Data([0, 0, 0x10, 0])), chunkStreamID: 2, chunkSize: 128
        ))
        let sent = connection.sent.dropFirst(before).flatMap { reader.append($0) }
        XCTAssertEqual(sent.map(\.typeID), [RTMPMessage.Kind.data])
        XCTAssertEqual(sent.first?.timestamp, 2500)
        XCTAssertEqual(sent.first.map { AMF0.decode($0.payload) }?.first, .string("onCuePoint"))
    }

    func testAStreamNotSetToMarkScenesSendsNoCuePoints() {
        goLive()
        output.send(makeFrameBuffer())
        let before = connections[0].sent.count
        output.markScene(named: "Wide")
        XCTAssertEqual(connections[0].sent.count, before)
    }

    func testAFailureIsReportedAndStands() {
        output.apply(settings, withSound: false)
        connections[0].onFailure?("Connection refused")
        XCTAssertEqual(output.status, .failed("Connection refused"))
        connections[0].onReceive?(Data([3]))
        XCTAssertEqual(output.status, .failed("Connection refused"), "later chatter does not hide it")
    }

    func testSwitchingOffOrMovingClosesTheLineAndStartsAfresh() {
        goLive()
        var moved = settings
        moved.streamKey = "other"
        output.apply(moved, withSound: false)
        XCTAssertTrue(connections[0].isClosed)
        XCTAssertTrue(encoders[0].isFinished)
        XCTAssertEqual(connections.count, 2)
        XCTAssertEqual(output.status, .connecting)

        output.apply(RTMPSettings(), withSound: false)
        XCTAssertTrue(connections[1].isClosed)
        XCTAssertEqual(output.status, .idle)
        // What the old line and encoder say afterwards goes nowhere.
        connections[1].onReady?()
        connections[1].onReceive?(Data([3]))
        encoders[1].output(EncodedFrame(data: Data(), isKeyFrame: true, milliseconds: 0, parameterSets: nil))
        XCTAssertEqual(connections[1].sent, [])
        XCTAssertEqual(output.status, .idle)
    }

    func testAnOutputThatHasGoneIgnoresItsLine() {
        var gone: RTMPOutput? = RTMPOutput(
            canvas: CGSize(width: 1280, height: 720), framesPerSecond: 30,
            makeConnection: { [unowned self] in
                let connection = FakeConnection()
                self.connections.append(connection)
                return connection
            },
            makeEncoder: { [unowned self] in
                let encoder = FakeFrameEncoder(size: $0, encoding: $1, output: $2)
                self.encoders.append(encoder)
                return encoder
            },
            makeSoundEncoder: { _ in FakeSoundEncoder() },
            clock: { 0 }
        )
        gone?.apply(settings, withSound: false)
        gone = nil
        connections[0].onReady?()
        connections[0].onReceive?(Data([3]))
        connections[0].onFailure?("gone")
        encoders[0].output(EncodedFrame(data: Data(), isKeyFrame: true, milliseconds: 0, parameterSets: nil))
        XCTAssertEqual(connections[0].sent, [])
    }
}

final class AACEncoderTests: XCTestCase {
    func testSoundComesOutAsPacketsOfAAC() {
        let encoder = AACEncoder(format: .standard)
        var packets: [Data] = []
        for index in 0..<20 {
            packets += encoder.encode(TestSound.buffer(at: Double(index) * 1024 / TestSound.rate))
        }
        XCTAssertGreaterThan(packets.count, 10, "about one packet for each buffer, once it has got going")
        XCTAssertTrue(packets.allSatisfy { !$0.isEmpty })
        // A short buffer may not complete a packet by itself.
        XCTAssertLessThanOrEqual(encoder.encode(TestSound.buffer(samples: 100, at: 1)).count, 1)
    }
}

final class H264EncoderTests: XCTestCase {
    func testFramesComeOutCompressedStartingWithAKeyFrameAndItsDetails() {
        let lock = NSLock()
        var frames: [EncodedFrame] = []
        let got = expectation(description: "frames are compressed")
        got.assertForOverFulfill = false
        let encoder = H264Encoder(
            size: CGSize(width: 64, height: 64),
            encoding: StreamEncoding(segmentSeconds: 1, bitsPerSecond: 500_000, framesPerSecond: 30)
        ) { frame in
            lock.lock()
            frames.append(frame)
            let count = frames.count
            lock.unlock()
            if count >= 3 { got.fulfill() }
        }
        let buffer = makeFrameBuffer()
        for frame in 0..<10 {
            encoder.encode(buffer, atMilliseconds: UInt32(frame * 33))
        }
        encoder.finish()
        encoder.finish()
        encoder.encode(buffer, atMilliseconds: 999)
        wait(for: [got], timeout: 15)
        lock.lock()
        defer { lock.unlock() }
        XCTAssertEqual(frames.first?.isKeyFrame, true)
        XCTAssertGreaterThan(frames.first?.parameterSets?.sequence.count ?? 0, 3)
        XCTAssertGreaterThan(frames.first?.parameterSets?.picture.count ?? 0, 0)
        XCTAssertEqual(frames.first?.milliseconds, 0)
        XCTAssertGreaterThan(frames.first?.data.count ?? 0, 4)
        XCTAssertEqual(frames.dropFirst().first?.isKeyFrame, false)
    }
}

/// Sends a real stream to a real RTMP server, when one can be had: ffmpeg
/// listening on this Mac. Skipped where ffmpeg is not installed.
final class RTMPLiveTests: XCTestCase {
    private static let ffmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]

    func testARealServerTakesTheStreamAndSeesItsPicture() throws {
        guard let ffmpeg = Self.ffmpegPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw XCTSkip("ffmpeg is not installed, so there is no RTMP server to send to")
        }
        let port = 19_435
        let recording = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".flv")
        defer { try? FileManager.default.removeItem(at: recording) }
        let server = Process()
        server.executableURL = URL(fileURLWithPath: ffmpeg)
        server.arguments = [
            "-loglevel", "error", "-listen", "1", "-timeout", "20",
            "-i", "rtmp://127.0.0.1:\(port)/live/key", "-t", "1", "-c", "copy", "-y", recording.path,
        ]
        server.standardError = Pipe()
        try server.run()
        defer { if server.isRunning { server.terminate() } }
        // Give the server a moment to start listening.
        Thread.sleep(forTimeInterval: 1)

        let output = RTMPOutput(
            canvas: CGSize(width: 1280, height: 720), framesPerSecond: 30, chunkSize: Pacing.usual.streamChunkSize,
            largestRead: Pacing.usual.streamLargestRead, queues: DispatchQueues(), clocks: .system
        )
        // Small, so the test is quick. The frames fed in are a different
        // size from the stream's, and are scaled to fit.
        output.apply(
            RTMPSettings(
                isOn: true, address: "rtmp://127.0.0.1:\(port)/live", streamKey: "key",
                options: StreamOptions(height: 360, videoKilobits: 500, keyFrameSeconds: 1)
            ),
            withSound: true
        )
        let buffer = makeFrameBuffer()
        let deadline = Date().addingTimeInterval(20)
        var wentLive = false
        // Frames and sound go in side by side, both timed by the system's clock.
        var soundTime = ProcessInfo.processInfo.systemUptime
        while server.isRunning, Date() < deadline {
            output.send(buffer)
            let now = ProcessInfo.processInfo.systemUptime
            while soundTime < now {
                output.send(TestSound.buffer(at: soundTime))
                soundTime += 1024.0 / TestSound.rate
            }
            wentLive = wentLive || output.status == .live
            Thread.sleep(forTimeInterval: 0.033)
        }
        output.apply(RTMPSettings(), withSound: false)
        server.waitUntilExit()

        XCTAssertTrue(wentLive, "the server accepted the stream: \(output.status)")
        XCTAssertEqual(server.terminationStatus, 0, "the server read a second of video and finished")
        let size = (try? FileManager.default.attributesOfItem(atPath: recording.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 500, "and wrote the video it received")

        // What it recorded has a picture track and a sound track.
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().appendingPathComponent("ffprobe")
        probe.arguments = ["-v", "error", "-show_entries", "stream=codec_name", "-of", "csv=p=0", recording.path]
        let found = Pipe()
        probe.standardOutput = found
        if (try? probe.run()) != nil {
            probe.waitUntilExit()
            let codecs = String(decoding: found.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertTrue(codecs.contains("h264"), codecs)
            XCTAssertTrue(codecs.contains("aac"), codecs)
        }
    }
}
