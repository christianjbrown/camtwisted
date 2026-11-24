import AVFoundation
import CamTwistCore
import CoreVideo
import XCTest
@testable import CamTwistRendering

final class MovieWriterTests: XCTestCase {
    private func frame() -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ] as CFDictionary, &buffer)
        return buffer!
    }

    /// What a movie file turned out to hold.
    private struct Written {
        var duration: Double
        var pictureSize: CGSize
        var pictureCodec: FourCharCode?
        var soundFormat: AudioFormatID?
        var soundRate: Double?
        var chapterTitles: [String]
        var chapterStarts: [Double]
    }

    private static let soundRate = Pacing.usual.recordingSoundRate
    private static let scenes = ["Welcome", "Slides", "Back in five"]

    private func plan(_ options: RecordingOptions) -> RecordingPlan {
        RecordingRules.plan(
            for: options, canvasAspect: 16.0 / 9.0,
            automaticBitsPerPixelPerSecond: Pacing.usual.recordingBitsPerPixelPerSecond
        )
    }

    /// Writes three seconds of pictures and sound, a scene a second, and reads the file back.
    private func record(_ plan: RecordingPlan) async throws -> Written {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(plan.container.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try ChapteredMovieWriter(url: url, plan: plan, soundRate: Self.soundRate)
        let picture = frame()

        writer.startChapter(named: Self.scenes[0], at: 0)
        for index in 0..<90 {
            let seconds = Double(index) / 30
            if index == 30 { writer.startChapter(named: Self.scenes[1], at: seconds) }
            if index == 60 { writer.startChapter(named: Self.scenes[2], at: seconds) }
            writer.append(picture, at: seconds)
            writer.appendSound(TestSound.buffer(samples: 1600, at: 100 + seconds), startingFrom: 100)
            usleep(2000)
        }
        // Sound from before the recording began is left out.
        writer.appendSound(TestSound.buffer(at: 50), startingFrom: 100)
        let finished = expectation(description: "the file is whole")
        writer.finish(at: 3) { finished.fulfill() }
        await fulfillment(of: [finished], timeout: 20)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let movie = AVURLAsset(url: url)
        let videoTracks = try await movie.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
        let soundTracks = try await movie.loadTracks(withMediaType: .audio)
        XCTAssertEqual(soundTracks.count, 1)
        let pictureFormat = try await videoTracks[0].load(.formatDescriptions).first
        let soundFormat = try await soundTracks[0].load(.formatDescriptions).first

        let languages = try await movie.load(.availableChapterLocales).map(\.identifier)
        let chapters = try await movie.loadChapterMetadataGroups(bestMatchingPreferredLanguages: languages + ["en"])
        var titles: [String] = []
        for chapter in chapters {
            for item in chapter.items {
                if let title = try await item.load(.stringValue) { titles.append(title) }
            }
        }
        return Written(
            duration: try await movie.load(.duration).seconds,
            pictureSize: try await videoTracks[0].load(.naturalSize),
            pictureCodec: pictureFormat.map(CMFormatDescriptionGetMediaSubType),
            soundFormat: soundFormat?.audioStreamBasicDescription?.mFormatID,
            soundRate: soundFormat?.audioStreamBasicDescription?.mSampleRate,
            chapterTitles: titles,
            chapterStarts: chapters.map { $0.timeRange.start.seconds.rounded() }
        )
    }

    func testARecordingHasPicturesSoundAndAChapterForEachScene() async throws {
        let written = try await record(plan(RecordingOptions(height: 360)))
        XCTAssertEqual(written.duration, 3, accuracy: 0.3)
        XCTAssertEqual(written.pictureSize, CGSize(width: 640, height: 360), "frames are scaled to the size chosen")
        XCTAssertEqual(written.pictureCodec, kCMVideoCodecType_H264)
        XCTAssertEqual(written.soundFormat, kAudioFormatMPEG4AAC)
        XCTAssertEqual(written.soundRate, Double(Self.soundRate))
        XCTAssertEqual(written.chapterTitles, Self.scenes)
        XCTAssertEqual(written.chapterStarts, [0, 1, 2])
    }

    func testEveryKindOfFileIsWrittenWithEachEncodingItTakes() async throws {
        let pictures: [RecordingPictureCodec: FourCharCode] = [
            .h264: kCMVideoCodecType_H264, .hevc: kCMVideoCodecType_HEVC, .proRes422: kCMVideoCodecType_AppleProRes422,
        ]
        let sounds: [RecordingSoundCodec: AudioFormatID] = [.aac: kAudioFormatMPEG4AAC, .linearPCM: kAudioFormatLinearPCM]
        var combinations = 0
        for container in RecordingContainer.allCases {
            for picture in RecordingRules.pictureCodecs(in: container) {
                for sound in RecordingRules.soundCodecs(in: container) {
                    combinations += 1
                    let options = RecordingOptions(
                        container: container, pictureCodec: picture, height: 480, pictureKilobits: 2000,
                        soundCodec: sound, soundKilobits: 320
                    )
                    let written = try await record(plan(options))
                    let what = "\(container) \(picture) \(sound)"
                    XCTAssertEqual(written.duration, 3, accuracy: 0.3, what)
                    XCTAssertEqual(written.pictureSize, CGSize(width: 854, height: 480), what)
                    XCTAssertEqual(written.pictureCodec, pictures[picture], what)
                    XCTAssertEqual(written.soundFormat, sounds[sound], what)
                    XCTAssertEqual(written.soundRate, Double(Self.soundRate), what)
                    // Found out here, with a real file: an MPEG-4 file takes
                    // the chapter track just as a QuickTime movie does.
                    XCTAssertEqual(written.chapterTitles, Self.scenes, what)
                }
            }
        }
        XCTAssertEqual(combinations, 8, "six in a QuickTime movie and two in an MPEG-4 file")
    }

    func testEncodingsAnMPEG4FileCannotTakeAreSwappedBeforeAnythingIsWritten() async throws {
        let asked = RecordingOptions(container: .mpeg4, pictureCodec: .proRes422, height: 360, soundCodec: .linearPCM)
        let corrected = plan(asked)
        XCTAssertEqual(corrected.pictureCodec, .h264)
        XCTAssertEqual(corrected.soundCodec, .aac)
        let written = try await record(corrected)
        XCTAssertEqual(written.pictureCodec, kCMVideoCodecType_H264)
        XCTAssertEqual(written.soundFormat, kAudioFormatMPEG4AAC)
        XCTAssertEqual(written.pictureSize, CGSize(width: 640, height: 360))
    }

    func testAnMPEG4FileDoesNotTakeProRes() throws {
        // Why the rules keep ProRes to a QuickTime movie: the system refuses it anywhere else.
        var refused = plan(RecordingOptions(container: .quickTime, pictureCodec: .proRes422))
        refused.container = .mpeg4
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: RecordingFormats.fileType(for: refused.container))
        XCTAssertFalse(writer.canApply(outputSettings: RecordingFormats.pictureSettings(for: refused), forMediaType: .video))
        let allowed = plan(RecordingOptions(container: .mpeg4))
        XCTAssertTrue(writer.canApply(outputSettings: RecordingFormats.pictureSettings(for: allowed), forMediaType: .video))
    }

    func testAMovieThatCannotBeWrittenIsNotStarted() {
        let nowhere = URL(fileURLWithPath: "/no/such/folder/\(UUID().uuidString)/movie.mov")
        XCTAssertThrowsError(try ChapteredMovieWriter(
            url: nowhere, plan: plan(RecordingOptions()), soundRate: Self.soundRate
        ))
    }

    func testAChapterTitleIsWrittenWithItsLengthAndItsEncoding() {
        XCTAssertEqual(
            Array(ChapterTrack.textSample("Hi")),
            [0, 2, 0x48, 0x69, 0, 0, 0, 12, 0x65, 0x6E, 0x63, 0x64, 0, 0, 1, 0]
        )
    }
}
