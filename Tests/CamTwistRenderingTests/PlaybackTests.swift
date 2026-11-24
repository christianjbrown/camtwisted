import AVFoundation
import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

/// Makes a short movie of one solid colour.
enum TestMovie {
    static let size = 64
    static let frames = 30
    static let framesPerSecond: Int32 = 30

    /// - Parameter withSound: whether the movie has a tone on a sound track too.
    static func write(to url: URL, red: UInt8, green: UInt8, blue: UInt8, withSound: Bool = false) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size,
            AVVideoHeightKey: size,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: size,
                kCVPixelBufferHeightKey as String: size,
            ]
        )
        writer.add(input)
        let sound = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
        ])
        if withSound { writer.add(sound) }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixelBuffer = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            let base = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
            for y in 0..<size {
                for x in 0..<size {
                    let offset = y * rowBytes + x * 4
                    base[offset] = blue
                    base[offset + 1] = green
                    base[offset + 2] = red
                    base[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: framesPerSecond))
        }
        if withSound {
            // A second of tone, alongside the second of picture.
            let packet = 1024.0 / TestSound.rate
            var time = 0.0
            while time < Double(frames) / Double(framesPerSecond) {
                while !sound.isReadyForMoreMediaData { usleep(1000) }
                sound.append(TestSound.buffer(at: time))
                time += packet
            }
            sound.markAsFinished()
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
    }
}

private func centrePixel(of image: CIImage) -> [UInt8] {
    var pixel = [UInt8](repeating: 0, count: 4)
    CIContext().render(
        image, toBitmap: &pixel, rowBytes: 4,
        bounds: CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1),
        format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
    )
    return pixel
}

final class StreamSourceTests: XCTestCase {
    private static let timeout: TimeInterval = 15
    private static let pollInterval: TimeInterval = 0.05
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testAStreamPlaysFromItsAddressAndTakesAVolumeChangeAsItPlays() throws {
        let clip = folder.appendingPathComponent("green.mov")
        try TestMovie.write(to: clip, red: 0, green: 255, blue: 0)
        let settings = StreamSettings(address: clip.absoluteString, volume: 0)
        let source = try XCTUnwrap(StreamSourceProvider().makeSource(for: .stream(settings)))
        XCTAssertNil(source.latestFrame, "nothing before it starts")
        source.start()
        source.start()

        let deadline = Date().addingTimeInterval(Self.timeout)
        var seen: [UInt8]?
        while seen == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(Self.pollInterval))
            seen = source.latestFrame.map(centrePixel)
        }
        XCTAssertGreaterThan(try XCTUnwrap(seen)[1], 180, "the green clip is showing")

        XCTAssertTrue(source.update(to: .stream(StreamSettings(address: clip.absoluteString, volume: 0.5))))
        XCTAssertFalse(source.update(to: .stream(StreamSettings(address: "https://example.com/other.m3u8"))))
        XCTAssertFalse(source.update(to: .colorBars))
        source.stop()
        XCTAssertNil(source.latestFrame)
    }

    func testAVideoFilesSoundIsHandedOnAsItPlays() throws {
        let clip = folder.appendingPathComponent("loud.mov")
        try TestMovie.write(to: clip, red: 0, green: 0, blue: 255, withSound: true)
        let source = StreamSource(settings: StreamSettings(address: clip.path, volume: 0))
        XCTAssertNil(source.onSound)
        let lock = NSLock()
        var heard = 0
        source.onSound = { _ in lock.lock(); heard += 1; lock.unlock() }
        XCTAssertNotNil(source.onSound)
        source.start()
        let deadline = Date().addingTimeInterval(Self.timeout)
        var count = 0
        while count == 0, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(Self.pollInterval))
            lock.lock(); count = heard; lock.unlock()
        }
        source.stop()
        XCTAssertGreaterThan(count, 0, "its sound was heard")
    }

    func testWithNoAddressNothingPlays() {
        let source = StreamSource(settings: StreamSettings())
        source.start()
        XCTAssertNil(source.latestFrame)
        XCTAssertNil(StreamSourceProvider().makeSource(for: .colorBars))
    }
}

final class MovieSourceTests: XCTestCase {
    private static let timeout: TimeInterval = 15
    private static let pollInterval: TimeInterval = 0.05
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Runs the main run loop until the source shows a frame that passes.
    private func waitForFrame(from source: MovieSource, where passes: ([UInt8]) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(Self.timeout)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(Self.pollInterval))
            if let frame = source.latestFrame, passes(centrePixel(of: frame)) { return true }
        }
        return false
    }

    func testPlaysAClipAndMovesOnToTheNext() throws {
        let red = folder.appendingPathComponent("a-red.mov")
        let blue = folder.appendingPathComponent("b-blue.mov")
        try TestMovie.write(to: red, red: 255, green: 0, blue: 0)
        try TestMovie.write(to: blue, red: 0, green: 0, blue: 255)
        let source = makeMovieSource(settings: MovieSettings(
            files: [red.path, blue.path], playMode: .playAllAndStop, isMuted: true
        ))
        source.start()
        defer { source.stop() }

        XCTAssertTrue(waitForFrame(from: source) { $0[0] > 180 && $0[2] < 80 }, "the red clip plays first")
        XCTAssertTrue(waitForFrame(from: source) { $0[2] > 180 && $0[0] < 80 }, "then the blue one")
        XCTAssertEqual(source.currentTrackFile, blue.path)
    }

    func testAClipsSoundIsHandedOnAsItPlays() throws {
        let clip = folder.appendingPathComponent("loud.mov")
        try TestMovie.write(to: clip, red: 255, green: 0, blue: 0, withSound: true)
        let source = makeMovieSource(settings: MovieSettings(files: [clip.path], isMuted: true))
        XCTAssertNil(source.onSound)
        let lock = NSLock()
        var heard = 0
        source.onSound = { _ in lock.lock(); heard += 1; lock.unlock() }
        XCTAssertNotNil(source.onSound)
        source.start()
        defer { source.stop() }
        let deadline = Date().addingTimeInterval(Self.timeout)
        var count = 0
        while count == 0, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(Self.pollInterval))
            _ = source.latestFrame
            lock.lock(); count = heard; lock.unlock()
        }
        XCTAssertGreaterThan(count, 0, "its sound was heard")
    }

    func testACaptionIsDrawn() throws {
        let clip = folder.appendingPathComponent("black.mov")
        try TestMovie.write(to: clip, red: 0, green: 0, blue: 0)
        let source = makeMovieSource(settings: MovieSettings(
            files: [clip.path], playMode: .playOneAndRepeat, isMuted: true,
            captions: [clip.path: "MMMMMMMMMMMMMMMM"]
        ))
        source.start()
        defer { source.stop() }

        // The clip is black, so any bright pixel along the bottom is caption text.
        let deadline = Date().addingTimeInterval(Self.timeout)
        var brightest: UInt8 = 0
        while Date() < deadline, brightest < 200 {
            RunLoop.main.run(until: Date().addingTimeInterval(Self.pollInterval))
            guard let frame = source.latestFrame else { continue }
            let y = frame.extent.minY + frame.extent.height * 0.085
            for step in stride(from: 0.2, through: 0.8, by: 0.02) {
                var pixel = [UInt8](repeating: 0, count: 4)
                CIContext().render(
                    frame, toBitmap: &pixel, rowBytes: 4,
                    bounds: CGRect(x: frame.extent.minX + frame.extent.width * step, y: y, width: 1, height: 1),
                    format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
                )
                brightest = max(brightest, pixel[0])
            }
        }
        XCTAssertGreaterThan(brightest, 200, "white caption text shows over the black clip")
    }

    func testHotFolderClipsJoinThePlaylistAndHiddenWhenStoppedShowsNothing() throws {
        let green = folder.appendingPathComponent("green.mov")
        try TestMovie.write(to: green, red: 0, green: 255, blue: 0)
        var settings = MovieSettings(hotFolder: folder.path, playMode: .playOneAndRepeat, isMuted: true)
        let source = makeMovieSource(settings: settings)
        source.start()
        defer { source.stop() }

        XCTAssertTrue(waitForFrame(from: source) { $0[1] > 180 && $0[0] < 80 })

        settings.isPlaying = false
        settings.hidesWhenStopped = true
        XCTAssertTrue(source.update(to: .movie(settings)))
        XCTAssertNil(source.latestFrame)
        XCTAssertFalse(source.update(to: .colorBars))
    }
}

final class WebsiteSourceRenderingTests: XCTestCase {
    private static let timeout: TimeInterval = 15
    private static let pollInterval: TimeInterval = 0.1

    func testALocalPageIsPhotographed() throws {
        let page = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".html")
        try Data("<html><body style=\"background:#ff0000\"></body></html>".utf8).write(to: page)
        defer { try? FileManager.default.removeItem(at: page) }
        let source = makeWebsiteSource(
            address: page.path, snapshotsPerSecond: Pacing.usual.websiteSnapshotsPerSecond,
            canvas: CGSize(width: 320, height: 180)
        )
        source.start()
        defer { source.stop() }

        let deadline = Date().addingTimeInterval(Self.timeout)
        var seen: [UInt8]?
        while Date() < deadline, seen == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(Self.pollInterval))
            if let frame = source.latestFrame {
                let pixel = centrePixel(of: frame)
                if pixel[0] > 180, pixel[1] < 80 { seen = pixel }
            }
        }
        XCTAssertNotNil(seen, "the page's red background should show up")
    }
}

private func pixel(of image: CIImage, x: CGFloat, y: CGFloat) -> [UInt8] {
    var pixel = [UInt8](repeating: 0, count: 4)
    CIContext().render(
        image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
        format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
    )
    return pixel
}

final class HTMLEffectTests: XCTestCase {
    private static let timeout: TimeInterval = 15
    private static let pollInterval: TimeInterval = 0.1
    private let canvas = CGSize(width: 320, height: 180)
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let page = "<html><body style=\"margin:0\"><div style=\"position:absolute;left:0;top:0;width:50%;height:100%;background:#ff0000\"></div></body></html>"
        try Data(page.utf8).write(to: folder.appendingPathComponent("Half.html"))
        try Data().write(to: folder.appendingPathComponent("Zoom.txt"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testThePageIsDrawnOverThePictureAndClearElsewhere() throws {
        let library = makeHTMLEffectLibrary(directory: folder)
        XCTAssertEqual(library.availableEffects(), [EffectListing(name: "Half", kind: .overlay)])
        XCTAssertEqual(library.parameters(forEffectNamed: "Half"), [])
        XCTAssertNil(library.makeEffect(named: "Zoom", canvas: canvas))
        let effect = try XCTUnwrap(library.makeEffect(named: "Half", canvas: canvas))
        effect.setValues([:])
        let green = CIImage(color: .green).cropped(to: CGRect(origin: .zero, size: canvas))

        let deadline = Date().addingTimeInterval(Self.timeout)
        var left: [UInt8] = []
        var right: [UInt8] = []
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(Self.pollInterval))
            let output = effect.apply(to: green, time: 0)
            left = pixel(of: output, x: 40, y: 90)
            right = pixel(of: output, x: 280, y: 90)
            if left[0] > 180 { break }
        }
        XCTAssertGreaterThan(left[0], 180, "the page's red half covers the left")
        XCTAssertLessThan(left[1], 80)
        XCTAssertGreaterThan(right[1], 180, "the picture shows through the clear half")
        XCTAssertLessThan(right[0], 80)
    }
}

private final class StubLibrary: EffectLibrary, ImageEffectFactory {
    let directory: URL
    let names: [String]

    init(directory: String, names: [String]) {
        self.directory = URL(fileURLWithPath: directory)
        self.names = names
    }

    func availableEffects() -> [EffectListing] { names.map { EffectListing(name: $0, kind: .filter) } }

    func parameters(forEffectNamed name: String) -> [EffectParameter] {
        names.contains(name)
            ? [EffectParameter(key: name, displayName: name, kind: .boolean, defaultValue: .boolean(true))]
            : []
    }

    func makeEffect(named name: String, canvas: CGSize) -> ImageEffect? {
        names.contains(name) ? makeHTMLEffect(file: directory, canvas: canvas) : nil
    }
}

final class CombinedEffectLibraryTests: XCTestCase {
    func testMembersAreListedTogetherAndAskedInOrder() {
        let library = CombinedEffectLibrary(primary: StubLibrary(directory: "/first", names: ["Zoom"]), others: [
            StubLibrary(directory: "/second", names: ["Bump"]),
        ])

        XCTAssertEqual(library.directory.path, "/first")
        XCTAssertEqual(library.availableEffects().map(\.name), ["Bump", "Zoom"])
        let doubled = CombinedEffectLibrary(primary: StubLibrary(directory: "/first", names: ["Zoom"]), others: [
            StubLibrary(directory: "/second", names: ["Zoom", "Bump"]),
        ])
        XCTAssertEqual(doubled.availableEffects().map(\.name), ["Bump", "Zoom"], "a repeated name is listed once")
        let renamed = CombinedEffectLibrary(
            primary: StubLibrary(directory: "/first", names: ["Whirlpool", "Dodgy Signal", "Sobel", "Twirl"]), others: []
        )
        XCTAssertEqual(
            renamed.availableEffects().map(\.name), ["Dodgy Signal", "Sobel", "Twirl", "Whirlpool"],
            "in the order of the names they are shown under: Bad TV, Sobel Edges, Twirl, Vortex"
        )
        XCTAssertEqual(library.parameters(forEffectNamed: "Bump").map(\.key), ["Bump"])
        XCTAssertEqual(library.parameters(forEffectNamed: "Missing"), [])
        XCTAssertNotNil(library.makeEffect(named: "Bump", canvas: CGSize(width: 8, height: 8)))
        XCTAssertNil(library.makeEffect(named: "Missing", canvas: CGSize(width: 8, height: 8)))
    }
}
