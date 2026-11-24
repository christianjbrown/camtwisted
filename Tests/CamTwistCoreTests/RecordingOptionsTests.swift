import XCTest
@testable import CamTwistCore

final class RecordingOptionsTests: XCTestCase {
    private static let wide = 16.0 / 9.0
    private static let bitsPerPixel = 6

    private func plan(_ options: RecordingOptions) -> RecordingPlan {
        RecordingRules.plan(
            for: options, canvasAspect: Self.wide, automaticBitsPerPixelPerSecond: Self.bitsPerPixel
        )
    }

    func testANewRecordingIsAnMP4InFullHD() {
        let fresh = RecordingOptions()
        XCTAssertEqual(fresh.container, .mpeg4)
        XCTAssertEqual(fresh.pictureCodec, .h264)
        XCTAssertEqual(fresh.height, 1080)
        XCTAssertNil(fresh.pictureKilobits, "the picture's bit rate is left to the app")
        XCTAssertEqual(fresh.soundCodec, .aac)
        XCTAssertEqual(fresh.soundKilobits, 192)
        XCTAssertEqual(RecordingRules.usable(fresh), fresh)
    }

    func testEachKindOfFileIsKnownByItsExtension() {
        XCTAssertEqual(RecordingContainer.quickTime.fileExtension, "mov")
        XCTAssertEqual(RecordingContainer.mpeg4.fileExtension, "mp4")
        XCTAssertEqual(RecordingContainer.allCases.map(\.title), ["QuickTime (.mov)", "MPEG-4 (.mp4)"])
    }

    func testEncodingsAreCalledWhatTheyAre() {
        XCTAssertEqual(RecordingPictureCodec.allCases.map(\.name), ["H.264", "HEVC", "Apple ProRes 422"])
        XCTAssertEqual(RecordingPictureCodec.allCases.map(\.title), [
            "H.264, which plays on everything", "HEVC, smaller, for newer players",
            "Apple ProRes 422, large, for editing",
        ])
        XCTAssertEqual(RecordingSoundCodec.allCases.map(\.title), ["AAC", "Uncompressed (Linear PCM)"])
    }

    func testAQuickTimeMovieTakesEveryEncodingAndAnMPEG4FileOnlyTheCompressedOnes() {
        XCTAssertEqual(RecordingRules.pictureCodecs(in: .quickTime), [.h264, .hevc, .proRes422])
        XCTAssertEqual(RecordingRules.pictureCodecs(in: .mpeg4), [.h264, .hevc])
        XCTAssertEqual(RecordingRules.soundCodecs(in: .quickTime), [.aac, .linearPCM])
        XCTAssertEqual(RecordingRules.soundCodecs(in: .mpeg4), [.aac])
    }

    func testProResAndUncompressedSoundHaveNoBitRateToSet() {
        XCTAssertTrue(RecordingRules.hasBitRate(RecordingPictureCodec.h264))
        XCTAssertTrue(RecordingRules.hasBitRate(RecordingPictureCodec.hevc))
        XCTAssertFalse(RecordingRules.hasBitRate(RecordingPictureCodec.proRes422))
        XCTAssertTrue(RecordingRules.hasBitRate(RecordingSoundCodec.aac))
        XCTAssertFalse(RecordingRules.hasBitRate(RecordingSoundCodec.linearPCM))
    }

    func testChoosingMPEG4FallsBackToEncodingsItTakes() {
        var options = RecordingOptions(container: .quickTime, pictureCodec: .proRes422, soundCodec: .linearPCM)
        XCTAssertEqual(RecordingRules.usable(options), options, "both are fine in a QuickTime movie")
        options.container = .mpeg4
        let fitting = RecordingRules.usable(options)
        XCTAssertEqual(fitting.container, .mpeg4)
        XCTAssertEqual(fitting.pictureCodec, .h264)
        XCTAssertEqual(fitting.soundCodec, .aac)

        let kept = RecordingOptions(container: .mpeg4, pictureCodec: .hevc)
        XCTAssertEqual(RecordingRules.usable(kept), kept, "an encoding the file takes is left alone")
    }

    func testSizesAndRatesNotOnOfferAreSwappedForTheUsualOnes() {
        let odd = RecordingOptions(height: 1000, pictureKilobits: 1234, soundKilobits: 100)
        let fitting = RecordingRules.usable(odd)
        XCTAssertEqual(fitting.height, 1080)
        XCTAssertNil(fitting.pictureKilobits)
        XCTAssertEqual(fitting.soundKilobits, 192)

        let fine = RecordingOptions(height: 2160, pictureKilobits: 50000, soundKilobits: 320)
        XCTAssertEqual(RecordingRules.usable(fine), fine)
        XCTAssertTrue(RecordingRules.pictureKilobitChoices.contains(50000))
        XCTAssertTrue(RecordingRules.soundKilobitChoices.contains(RecordingOptions.usualSoundKilobits))
    }

    func testAPlanHasThePictureSizeAndTheBitRatesWorkedOut() {
        let automatic = plan(RecordingOptions(height: 720))
        XCTAssertEqual(automatic.width, 1280)
        XCTAssertEqual(automatic.height, 720)
        XCTAssertEqual(automatic.pictureBitsPerSecond, 1280 * 720 * Self.bitsPerPixel, "so many bits for each pixel")
        XCTAssertEqual(automatic.soundBitsPerSecond, 192_000)

        let chosen = plan(RecordingOptions(container: .mpeg4, pictureCodec: .hevc, pictureKilobits: 8000, soundKilobits: 128))
        XCTAssertEqual(chosen.container, .mpeg4)
        XCTAssertEqual(chosen.pictureCodec, .hevc)
        XCTAssertEqual(chosen.pictureBitsPerSecond, 8_000_000)
        XCTAssertEqual(chosen.soundBitsPerSecond, 128_000)
    }

    func testAPlanLeavesOutTheBitRatesOfEncodingsThatHaveNone() {
        let editing = plan(RecordingOptions(
            container: .quickTime, pictureCodec: .proRes422, pictureKilobits: 8000, soundCodec: .linearPCM
        ))
        XCTAssertEqual(editing.pictureCodec, .proRes422)
        XCTAssertNil(editing.pictureBitsPerSecond)
        XCTAssertEqual(editing.soundCodec, .linearPCM)
        XCTAssertNil(editing.soundBitsPerSecond)
    }

    func testAPlanIsMadeFromOptionsThatFit() {
        let corrected = plan(RecordingOptions(container: .mpeg4, pictureCodec: .proRes422, soundCodec: .linearPCM))
        XCTAssertEqual(corrected, RecordingPlan(
            container: .mpeg4, pictureCodec: .h264, width: 1920, height: 1080,
            pictureBitsPerSecond: 1920 * 1080 * Self.bitsPerPixel, soundCodec: .aac, soundBitsPerSecond: 192_000
        ))
    }

    func testThePictureBitRateIsCalledAutomaticUntilOneIsChosen() {
        XCTAssertEqual(RecordingWording.pictureBitRateTitle(nil), "Automatic")
        XCTAssertEqual(RecordingWording.pictureBitRateTitle(8000), "8000")
    }

    func testTheOptionsAreSummedUpInAFewWords() {
        XCTAssertEqual(RecordingWording.summary(of: RecordingOptions()), "MPEG-4 (.mp4), H.264, 1080p (Full HD)")
        XCTAssertEqual(
            RecordingWording.summary(of: RecordingOptions(container: .mpeg4, pictureCodec: .proRes422, height: 2160)),
            "MPEG-4 (.mp4), H.264, 4K", "as they will be recorded"
        )
    }

    func testOptionsSurviveBeingSaved() throws {
        let options = RecordingOptions(
            container: .mpeg4, pictureCodec: .hevc, height: 720, pictureKilobits: 6000, soundKilobits: 256
        )
        let saved = try JSONEncoder().encode(options)
        XCTAssertEqual(try JSONDecoder().decode(RecordingOptions.self, from: saved), options)
    }
}
