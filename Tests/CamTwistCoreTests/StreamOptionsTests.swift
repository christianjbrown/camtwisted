import XCTest
@testable import CamTwistCore

final class StreamOptionsTests: XCTestCase {
    func testStreamsStartWithOptionsThatSuitWhereTheyGo() {
        XCTAssertEqual(StreamOptions.web.keyFrameSeconds, 1)
        XCTAssertEqual(StreamOptions.server.keyFrameSeconds, 2)
        XCTAssertEqual(StreamOptions.server.videoKilobits, 4500)
        XCTAssertEqual(StreamOptions().height, 720)
        XCTAssertEqual(DrawingSize.fullHD.scale, 1)
        XCTAssertEqual(DrawingSize.ultraHD.width, 3840)
        XCTAssertEqual(DrawingSize.ultraHD.height, 2160)
        XCTAssertEqual(DrawingSize.fullHD.height, 1080)
        XCTAssertEqual(DrawingSize.allCases, [.fullHD, .ultraHD])
    }

    func testAStreamIsH264UnlessSomethingElseIsChosen() throws {
        XCTAssertEqual(StreamOptions().codec, .h264)
        var options = StreamOptions(codec: .hevc)
        XCTAssertEqual(options.usable.codec, .hevc, "the choice survives being tidied")
        options.codec = .h264
        XCTAssertEqual(options.videoCodec, .h264)
        // Options saved before there was a choice still load, as H.264.
        let old = Data(
            #"{"height":720,"videoKilobits":4000,"keyFrameSeconds":1,"soundKilobits":128,"soundChannels":2,"sampleRate":48000}"#.utf8
        )
        XCTAssertEqual(try JSONDecoder().decode(StreamOptions.self, from: old).codec, .h264)
        XCTAssertEqual(StreamCodec.allCases, [.h264, .hevc])
    }

    func testThePictureSizeFollowsTheCanvasShapeAndIsEven() {
        let wide = 16.0 / 9
        XCTAssertTrue(StreamOptions().pictureSize(canvasAspect: wide) == (1280, 720))
        XCTAssertTrue(StreamOptions(height: 360).pictureSize(canvasAspect: wide) == (640, 360))
        XCTAssertTrue(StreamOptions(height: 480).pictureSize(canvasAspect: wide) == (854, 480), "853 made even")
        XCTAssertTrue(StreamOptions(height: 999).pictureSize(canvasAspect: wide) == (1280, 720), "not a height on offer")
    }

    func testOptionsOutOfRangeAreBroughtBackIn() {
        let wild = StreamOptions(
            height: 4320, videoKilobits: 1, keyFrameSeconds: 99, soundKilobits: 7, soundChannels: 6, sampleRate: 8000
        )
        XCTAssertEqual(wild.usable, StreamOptions(
            height: 720, videoKilobits: 4000, keyFrameSeconds: 6, soundKilobits: 128, soundChannels: 2, sampleRate: 48000
        ))
        let fine = StreamOptions(
            height: 540, videoKilobits: 2500, keyFrameSeconds: 1, soundKilobits: 96, soundChannels: 1, sampleRate: 44100
        )
        XCTAssertEqual(fine.usable, fine)
        XCTAssertFalse(fine.marksScenes)
        var marking = fine
        marking.marksScenes = true
        XCTAssertTrue(marking.usable.marksScenes)
        let old = try? JSONDecoder().decode(StreamOptions.self, from: Data(
            #"{"height":720,"videoKilobits":4000,"keyFrameSeconds":1,"soundKilobits":128,"soundChannels":2,"sampleRate":48000}"#.utf8
        ))
        XCTAssertEqual(old?.marksScenes, false, "options saved before markers existed still load")
        XCTAssertEqual(fine.videoBitsPerSecond, 2_500_000)
        XCTAssertEqual(fine.sound, SoundFormat(sampleRate: 44100, channels: 1, bitsPerSecond: 96000))
    }
}

final class CameraWatchersTests: XCTestCase {
    func testTheProcessesWatchingTravelAsTextAndComeBack() {
        XCTAssertEqual(CameraWatchers.text(for: [30, 4, 200]), "4,30,200")
        XCTAssertEqual(CameraWatchers.text(for: []), "")
        XCTAssertEqual(CameraWatchers.processes(in: "4,30,200"), [4, 30, 200])
        XCTAssertEqual(CameraWatchers.processes(in: ""), [])
        XCTAssertEqual(CameraWatchers.processes(in: "4,x,,9"), [4, 9], "what is not a number is left out")
        XCTAssertEqual(CameraWatchers.extensionProperty, "4cc_wtch_glob_0000")
        // The four characters, packed most significant first.
        XCTAssertEqual(CameraWatchers.selector, 0x7774_6368)
    }
}

final class RecordingNameTests: XCTestCase {
    func testARecordingIsNamedAfterWhenItBegan() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        // The fifteenth of June 2030, at five past nine and seven seconds.
        let date = Date(timeIntervalSince1970: 1_907_744_707)
        XCTAssertEqual(
            RecordingName.fileName(startingAt: date, as: .quickTime, in: zone), "CamTwisted 2030-06-15 at 09.05.07.mov"
        )
        XCTAssertEqual(
            RecordingName.fileName(startingAt: date, as: .mpeg4, in: zone), "CamTwisted 2030-06-15 at 09.05.07.mp4",
            "the extension follows the kind of file"
        )
        XCTAssertTrue(RecordingName.fileName(startingAt: date, as: .quickTime).hasSuffix(".mov"))
    }
}
