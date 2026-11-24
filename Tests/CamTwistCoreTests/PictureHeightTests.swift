import XCTest
@testable import CamTwistCore

final class PictureHeightTests: XCTestCase {
    func testEveryOutputChoosesFromTheSameHeights() {
        XCTAssertEqual(PictureHeight.all, [360, 480, 540, 720, 1080, 1440, 2160])
        XCTAssertEqual(PictureHeight.fullHD, DrawingSize.fullHD.height)
        XCTAssertEqual(PictureHeight.ultraHD, DrawingSize.ultraHD.height)
        XCTAssertTrue(PictureHeight.all.contains(StreamOptions().height))
        XCTAssertTrue(PictureHeight.all.contains(RecordingOptions().height))
    }

    func testAHeightIsCalledByItsLinesOrByItsName() {
        XCTAssertEqual(
            PictureHeight.all.map(PictureHeight.label),
            ["360p", "480p", "540p", "720p", "1080p (Full HD)", "1440p", "4K"]
        )
    }

    func testAPictureKeepsTheCanvasShapeWithAnEvenWidth() {
        let wide = PictureHeight.size(height: 720, canvasAspect: 16.0 / 9.0)
        XCTAssertEqual(wide.width, 1280)
        XCTAssertEqual(wide.height, 720)
        XCTAssertEqual(PictureHeight.size(height: 360, canvasAspect: 4.0 / 3.0).width, 480)
        XCTAssertEqual(PictureHeight.size(height: 481, canvasAspect: 16.0 / 9.0).width, 856, "855 is made even")
    }
}

final class DrawingSizeRuleTests: XCTestCase {
    func testThePictureIsDrawnInFullHDWhileNothingAsksForMore() {
        XCTAssertEqual(DrawingSizeRule().size(for: []), .fullHD)
        XCTAssertEqual(
            DrawingSizeRule().size(for: [
                PictureDemand(isOn: true, height: 720), PictureDemand(isOn: true, height: 1080),
            ]),
            .fullHD
        )
    }

    func testThePictureIsDrawnIn4KWhileAnOutputThatIsOnAsksForMoreThanFullHD() {
        XCTAssertEqual(
            DrawingSizeRule().size(for: [
                PictureDemand(isOn: true, height: 720), PictureDemand(isOn: true, height: 1440),
            ]),
            .ultraHD
        )
        XCTAssertEqual(DrawingSizeRule().size(for: [PictureDemand(isOn: true, height: 2160)]), .ultraHD)
    }

    func testAnOutputThatIsOffAsksForNothing() {
        XCTAssertEqual(
            DrawingSizeRule().size(for: [
                PictureDemand(isOn: false, height: 2160), PictureDemand(isOn: true, height: 360),
            ]),
            .fullHD
        )
    }

    func testTheLargestSizeIsUsedWhenNoneIsTallEnough() {
        XCTAssertEqual(DrawingSizeRule().size(for: [PictureDemand(isOn: true, height: 4320)]), .ultraHD)
    }

    func testTheSizesAreTriedSmallestFirstWhateverOrderTheyAreGivenIn() {
        let rule = DrawingSizeRule(sizes: [.ultraHD, .fullHD])
        XCTAssertEqual(rule.size(for: [PictureDemand(isOn: true, height: 720)]), .fullHD)
    }

    func testARuleWithNoSizesDrawsInFullHD() {
        XCTAssertEqual(DrawingSizeRule(sizes: []).size(for: [PictureDemand(isOn: true, height: 720)]), .fullHD)
    }

    func testTheNamedHeightsAreTheDrawingSizes() {
        XCTAssertEqual(PictureHeight.fullHD, DrawingSize.fullHD.height)
        XCTAssertEqual(PictureHeight.ultraHD, DrawingSize.ultraHD.height)
        XCTAssertTrue(PictureHeight.all.contains(PictureHeight.hd))
    }
}

final class PictureCodecWordingTests: XCTestCase {
    func testAStreamAndARecordingNameAnEncodingAlike() {
        XCTAssertEqual(StreamCodec.h264.title, RecordingPictureCodec.h264.title)
        XCTAssertEqual(StreamCodec.hevc.title, RecordingPictureCodec.hevc.title)
        XCTAssertEqual(StreamCodec.h264.title, "H.264, which plays on everything")
        XCTAssertEqual(PictureCodecWording.proRes422.name, RecordingPictureCodec.proRes422.name)
    }
}
