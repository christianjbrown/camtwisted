import CamTwistCore
import CoreMedia
import CoreVideo
import XCTest
@testable import CamTwistRendering

private final class FakeMovieWriter: MovieWriting {
    var frames: [Double] = []
    var sounds: [Double] = []
    var chapters: [(name: String, seconds: Double)] = []
    var finishedAt: Double?
    func append(_ pixelBuffer: CVPixelBuffer, at seconds: Double) { frames.append(seconds) }
    func appendSound(_ sound: CMSampleBuffer, startingFrom origin: Double) { sounds.append(origin) }
    func startChapter(named name: String, at seconds: Double) { chapters.append((name, seconds)) }
    func finish(at seconds: Double, completion: @escaping () -> Void) {
        finishedAt = seconds
        completion()
    }
}

final class RecordingOutputTests: XCTestCase {
    private var now = 100.0
    private var writers: [(url: URL, plan: RecordingPlan, writer: FakeMovieWriter)] = []
    private var refuses = false
    private let folder = URL(fileURLWithPath: "/recordings")
    private struct Refused: Error {}
    private static let bitsPerPixel = 6
    private let usual = RecordingOptions()

    private lazy var output = RecordingOutput(
        makeWriter: { [unowned self] url, plan in
            if self.refuses { throw Refused() }
            let writer = FakeMovieWriter()
            self.writers.append((url, plan, writer))
            return writer
        },
        bitsPerPixelPerSecond: Self.bitsPerPixel,
        clock: { [unowned self] in self.now },
        today: { Date(timeIntervalSince1970: 1_907_744_707) }
    )

    private func frame() -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 36, kCVPixelFormatType_32BGRA, nil, &buffer)
        return buffer!
    }

    func testNothingIsRecordedUntilItIsSwitchedOn() {
        output.send(frame())
        output.send(TestSound.buffer(at: now))
        output.markScene(named: "Welcome")
        XCTAssertTrue(writers.isEmpty)
        XCTAssertEqual(output.status, .off)
    }

    func testARecordingBeginsWithItsFirstFrameAndHasAChapterForEachScene() {
        output.apply(isOn: true, folder: folder, sceneName: "Welcome", options: usual)
        XCTAssertTrue(writers.isEmpty, "nothing is written until there is a frame")
        output.send(TestSound.buffer(at: now))

        output.send(frame())
        XCTAssertEqual(writers.count, 1)
        XCTAssertEqual(writers[0].url.deletingLastPathComponent().path, "/recordings")
        XCTAssertTrue(writers[0].url.lastPathComponent.hasPrefix("CamTwisted 2030-06-15 at "))
        XCTAssertTrue(writers[0].url.lastPathComponent.hasSuffix(".mp4"))
        XCTAssertEqual(writers[0].plan.width, 1920, "the frame's own shape, at the size chosen")
        XCTAssertEqual(writers[0].plan.height, 1080)
        XCTAssertEqual(writers[0].plan.pictureBitsPerSecond, 1920 * 1080 * Self.bitsPerPixel)
        XCTAssertEqual(output.status, .recording(writers[0].url.lastPathComponent))
        let writer = writers[0].writer
        XCTAssertEqual(writer.frames, [0])
        XCTAssertEqual(writer.chapters.map(\.name), ["Welcome"])

        now = 102
        output.send(frame())
        output.send(TestSound.buffer(at: now))
        XCTAssertEqual(writer.frames, [0, 2])
        XCTAssertEqual(writer.sounds, [100], "sound is placed from when the recording began")

        now = 105
        output.markScene(named: "Slides")
        XCTAssertEqual(writer.chapters.map(\.seconds), [0, 5])
        XCTAssertEqual(writer.chapters.last?.name, "Slides")

        // Switched on again while under way, it carries on in the same file.
        output.apply(isOn: true, folder: folder, sceneName: "Slides", options: usual)
        output.send(frame())
        XCTAssertEqual(writers.count, 1)

        now = 110
        output.apply(isOn: false, folder: folder, sceneName: "Slides", options: usual)
        XCTAssertEqual(writer.finishedAt, 10)
        XCTAssertEqual(output.status, .off)
        output.send(frame())
        XCTAssertEqual(writer.frames.count, 3, "nothing more is written")

        // The next recording is a new file, starting on the scene named then.
        output.markScene(named: "Back in five")
        output.apply(isOn: true, folder: folder, sceneName: "Back in five", options: usual)
        output.send(frame())
        XCTAssertEqual(writers.count, 2)
        XCTAssertEqual(writers[1].writer.chapters.map(\.name), ["Back in five"])
    }

    func testARecordingIsMadeTheWayItsOptionsSayWhenItWasSwitchedOn() {
        let small = RecordingOptions(
            container: .quickTime, pictureCodec: .hevc, height: 720, pictureKilobits: 8000, soundKilobits: 128
        )
        output.apply(isOn: true, folder: folder, sceneName: "Welcome", options: small)
        // Changed while it is wanted, the options wait for the next recording.
        output.apply(isOn: true, folder: folder, sceneName: "Welcome", options: usual)
        output.send(frame())
        XCTAssertTrue(writers[0].url.lastPathComponent.hasSuffix(".mov"), "the name follows the kind of file")
        XCTAssertEqual(writers[0].plan, RecordingPlan(
            container: .quickTime, pictureCodec: .hevc, width: 1280, height: 720, pictureBitsPerSecond: 8_000_000,
            soundCodec: .aac, soundBitsPerSecond: 128_000
        ))

        output.apply(isOn: false, folder: folder, sceneName: "Welcome", options: usual)
        output.apply(isOn: true, folder: folder, sceneName: "Welcome", options: usual)
        output.send(frame())
        XCTAssertEqual(writers[1].plan.container, .mpeg4)
    }

    func testARecordingThatCannotStartSaysSoAndDoesNotKeepTrying() {
        refuses = true
        output.apply(isOn: true, folder: folder, sceneName: "Welcome", options: usual)
        output.send(frame())
        XCTAssertEqual(output.status, .failed("The recording could not be started in that folder."))
        refuses = false
        output.send(frame())
        XCTAssertTrue(writers.isEmpty, "it waits to be switched off and on again")

        output.apply(isOn: false, folder: folder, sceneName: "Welcome", options: usual)
        XCTAssertEqual(output.status, .off)
        output.apply(isOn: true, folder: folder, sceneName: "Welcome", options: usual)
        output.send(frame())
        XCTAssertEqual(writers.count, 1)
    }

    func testTheRealOutputWritesAMovie() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let real = RecordingOutput(
            soundRate: Pacing.usual.recordingSoundRate,
            bitsPerPixelPerSecond: Pacing.usual.recordingBitsPerPixelPerSecond, clocks: .system
        )
        real.apply(isOn: true, folder: folder, sceneName: "Welcome", options: usual)
        for _ in 0..<5 {
            real.send(frame())
            usleep(20000)
        }
        guard case .recording(let name) = real.status else { return XCTFail("it is recording") }
        real.apply(isOn: false, folder: folder, sceneName: "Welcome", options: usual)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path))
    }
}
