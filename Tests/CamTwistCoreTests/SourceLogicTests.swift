import XCTest
@testable import CamTwistCore

final class PlaylistSequencerTests: XCTestCase {
    private func next(_ current: Int, _ count: Int, _ mode: MoviePlayMode) -> Int? {
        PlaylistSequencer.next(after: current, count: count, mode: mode) { _ in 2 }
    }

    func testEmptyPlaylistNeverPlays() {
        for mode in MoviePlayMode.allCases {
            XCTAssertNil(next(0, 0, mode))
        }
    }

    func testEachMode() {
        XCTAssertNil(next(0, 3, .playOneAndStop))
        XCTAssertEqual(next(1, 3, .playOneAndRepeat), 1)
        XCTAssertEqual(next(0, 3, .playAllAndStop), 1)
        XCTAssertNil(next(2, 3, .playAllAndStop))
        XCTAssertEqual(next(1, 3, .playAllAndRepeat), 2)
        XCTAssertEqual(next(2, 3, .playAllAndRepeat), 0)
        XCTAssertEqual(next(0, 3, .shuffle), 2)
    }
}

final class SlideShowClockTests: XCTestCase {
    func testIndexAdvancesWithTheDelayAndWraps() {
        XCTAssertNil(SlideShowClock.index(at: 3, delay: 5, count: 0, loops: true))
        XCTAssertEqual(SlideShowClock.index(at: 0, delay: 5, count: 3, loops: true), 0)
        XCTAssertEqual(SlideShowClock.index(at: 4.9, delay: 5, count: 3, loops: true), 0)
        XCTAssertEqual(SlideShowClock.index(at: 5, delay: 5, count: 3, loops: true), 1)
        XCTAssertEqual(SlideShowClock.index(at: 16, delay: 5, count: 3, loops: true), 0)
        XCTAssertEqual(SlideShowClock.index(at: 9, delay: 0, count: 3, loops: true), 0)
        XCTAssertEqual(SlideShowClock.index(at: 5, delay: 5, count: 3, loops: false), 1)
        XCTAssertEqual(SlideShowClock.index(at: 16, delay: 5, count: 3, loops: false), 2, "it stays on the last image")
    }
}

final class CaptureRegionTests: XCTestCase {
    private let frame = CGSize(width: 1000, height: 500)

    func testFixedRegionScalesToTheFrameAndStaysInside() {
        XCTAssertEqual(CaptureRegion.rect(for: .full, in: frame), CGRect(x: 0, y: 0, width: 1000, height: 500))
        XCTAssertEqual(
            CaptureRegion.rect(for: UnitRect(x: 0.5, y: 0.5, width: 0.25, height: 0.5), in: frame),
            CGRect(x: 500, y: 250, width: 250, height: 250)
        )
        XCTAssertEqual(
            CaptureRegion.rect(for: UnitRect(x: 0.9, y: 0, width: 0.5, height: 1), in: frame),
            CGRect(x: 900, y: 0, width: 100, height: 500)
        )
    }

    func testFollowingThePointerCentresOnItAndStopsAtTheEdges() {
        XCTAssertEqual(
            CaptureRegion.rect(following: CGPoint(x: 0.5, y: 0.5), fraction: 0.5, in: frame),
            CGRect(x: 250, y: 125, width: 500, height: 250)
        )
        XCTAssertEqual(
            CaptureRegion.rect(following: CGPoint(x: 0, y: 1), fraction: 0.5, in: frame),
            CGRect(x: 0, y: 250, width: 500, height: 250)
        )
        XCTAssertEqual(
            CaptureRegion.rect(following: CGPoint(x: 1, y: 0), fraction: 0.5, in: frame),
            CGRect(x: 500, y: 0, width: 500, height: 250)
        )
    }
}

final class WindowMatcherTests: XCTestCase {
    private func matches(_ title: String, _ app: String, _ settings: WindowSettings) -> Bool {
        WindowMatcher.matches(title: title, application: app, settings: settings)
    }

    func testPlainTextIsACaseInsensitiveContains() {
        XCTAssertTrue(matches("My Notes", "Notes", WindowSettings(titlePattern: "notes")))
        XCTAssertFalse(matches("Inbox", "Mail", WindowSettings(titlePattern: "notes")))
        XCTAssertTrue(matches("Anything", "App", WindowSettings(titlePattern: "")))
    }

    func testRegularExpressions() {
        let settings = WindowSettings(titlePattern: "^Chapter \\d+$", isRegularExpression: true)
        XCTAssertTrue(matches("chapter 12", "Editor", settings))
        XCTAssertFalse(matches("Chapter twelve", "Editor", settings))
        XCTAssertFalse(matches("x", "Editor", WindowSettings(titlePattern: "(", isRegularExpression: true)))
    }

    func testApplicationNarrowsTheMatch() {
        let settings = WindowSettings(titlePattern: "", applicationName: "Notes")
        XCTAssertTrue(matches("x", "Notes", settings))
        XCTAssertFalse(matches("x", "Mail", settings))
        XCTAssertTrue(matches("x", "Mail", WindowSettings(titlePattern: "", applicationName: "")))
    }
}

final class MediaFileTypesTests: XCTestCase {
    func testMoviesAndImagesAreToldApartByExtension() {
        XCTAssertTrue(MediaFileTypes.isMovie("/clips/Intro.MOV"))
        XCTAssertFalse(MediaFileTypes.isMovie("/clips/intro.png"))
        XCTAssertTrue(MediaFileTypes.isImage("/pics/a.JPEG"))
        XCTAssertFalse(MediaFileTypes.isImage("/pics/a.mov"))
        XCTAssertFalse(MediaFileTypes.isImage("/pics/folder"))
    }
}
