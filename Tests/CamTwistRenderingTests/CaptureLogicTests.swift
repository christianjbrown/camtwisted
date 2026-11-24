import CamTwistCore
import CoreGraphics
import CoreImage
import XCTest
@testable import CamTwistRendering

final class CaptureLogicTests: XCTestCase {
    private let frame = CIImage(color: .red).cropped(to: CGRect(x: 10, y: 20, width: 200, height: 100))

    func testAFixedRegionCropsTheFrameAndFullShowsAllOfIt() {
        let settings = DisplaySettings(displayID: 1)
        XCTAssertEqual(DisplayCapture.framed(frame, settings: settings, pointer: { .zero }).extent, frame.extent)
        var half = settings
        half.region = UnitRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let cropped = DisplayCapture.framed(frame, settings: half, pointer: { .zero }).extent
        XCTAssertEqual(cropped.width, 100)
        XCTAssertEqual(cropped.minX, 10)
    }

    func testFollowingTheMouseAsksWhereThePointerIs() {
        let settings = DisplaySettings(displayID: 1, followsMouse: true, followFraction: 0.5)
        var asked = 0
        let shown = DisplayCapture.framed(frame, settings: settings, pointer: {
            asked += 1
            return CGPoint(x: 0.5, y: 0.5)
        })
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(shown.extent.width, 100)
        XCTAssertEqual(shown.extent.midX, frame.extent.midX)
    }

    func testARegionWithNoAreaShowsTheWholeFrame() {
        let settings = DisplaySettings(displayID: 1, region: UnitRect(x: 0.5, y: 0.5, width: 0, height: 0))
        XCTAssertEqual(DisplayCapture.framed(frame, settings: settings, pointer: { .zero }).extent, frame.extent)
    }

    func testThePointerIsMeasuredAsSharesOfTheScreenOrTheMiddleWhenThereIsNone() {
        let screen = CGRect(x: 100, y: 50, width: 200, height: 100)
        XCTAssertEqual(DisplayCapture.unitPosition(of: CGPoint(x: 200, y: 100), on: screen), CGPoint(x: 0.5, y: 0.5))
        let middle = CGPoint(x: DisplayCapture.centre, y: DisplayCapture.centre)
        XCTAssertEqual(DisplayCapture.unitPosition(of: .zero, on: nil), middle)
        XCTAssertEqual(DisplayCapture.unitPosition(of: .zero, on: CGRect(x: 0, y: 0, width: 0, height: 10)), middle)
        XCTAssertEqual(DisplayCapture.unitPosition(of: .zero, on: CGRect(x: 0, y: 0, width: 10, height: 0)), middle)
    }

    func testOnlyANewDisplayOrCursorSettingNeedsANewStream() {
        let old = DisplaySettings(displayID: 1)
        var moved = old
        moved.region = UnitRect(x: 0, y: 0, width: 0.5, height: 0.5)
        var other = old
        other.displayID = 2
        var cursor = old
        cursor.showsCursor = false
        XCTAssertTrue(DisplayCapture.keepsStream(from: old, to: moved))
        XCTAssertFalse(DisplayCapture.keepsStream(from: old, to: other))
        XCTAssertFalse(DisplayCapture.keepsStream(from: old, to: cursor))
    }

    func testACameraIsListedByItsBiggestFormatAndOurOwnIsLeftOut() {
        XCTAssertEqual(CameraListing.mostPixels(of: [(640, 480), (1920, 1080), (1280, 720)]), 1920 * 1080)
        XCTAssertEqual(CameraListing.mostPixels(of: []), 0)
        XCTAssertFalse(CameraListing.isOffered(uniqueID: CameraContract.deviceID.uuidString))
        XCTAssertTrue(CameraListing.isOffered(uniqueID: "another-camera"))
    }

    func testAnAttemptIsLetThroughOnlyOnceTheIntervalHasPassed() {
        var throttle = AttemptThrottle(interval: 2)
        XCTAssertTrue(throttle.permits(at: 1000))
        XCTAssertFalse(throttle.permits(at: 1001))
        XCTAssertFalse(throttle.permits(at: 1002))
        XCTAssertTrue(throttle.permits(at: 1002.5))
        XCTAssertFalse(throttle.permits(at: 1003))
        throttle.reset()
        XCTAssertTrue(throttle.permits(at: 1003))
    }

    func testTheSteadyClockCountsUp() {
        XCTAssertGreaterThan(SteadyClock.uptime(), 0)
    }

    func testPointsBecomeWholePixels() {
        XCTAssertEqual(DisplayCapture.pixels(100.4, scale: 2), 200)
    }

    func testAWindowMatchesOnlyOnceOneHasBeenChosenAndItHasATitle() {
        XCTAssertFalse(WindowSelection.isMatch(title: "Notes", application: "Notes", settings: WindowSettings(titlePattern: "")))
        let byTitle = WindowSettings(titlePattern: "note")
        XCTAssertTrue(WindowSelection.isMatch(title: "Notes", application: nil, settings: byTitle))
        XCTAssertFalse(WindowSelection.isMatch(title: nil, application: "Notes", settings: byTitle))
        XCTAssertFalse(WindowSelection.isMatch(title: "", application: "Notes", settings: byTitle))
        let byApplication = WindowSettings(titlePattern: "", applicationName: "Notes")
        XCTAssertTrue(WindowSelection.isMatch(title: "Anything", application: "Notes", settings: byApplication))
        XCTAssertFalse(WindowSelection.isMatch(title: "Anything", application: nil, settings: byApplication))
    }

    func testTheWindowListKeepsTitledOrdinaryWindowsOfOtherProcessesOnce() {
        func window(layer: Int = 0, pid: Int32 = 7, title: String? = "Doc", owner: String? = "Editor") -> [String: Any] {
            var info: [String: Any] = [kCGWindowLayer as String: layer, kCGWindowOwnerPID as String: pid]
            info[kCGWindowName as String] = title
            info[kCGWindowOwnerName as String] = owner
            return info
        }
        let list = [
            window(), window(), window(layer: 25), window(pid: 99), window(title: nil), window(title: ""),
            window(owner: nil), window(title: "Other"),
        ]
        let choices = WindowSelection.choices(from: list, excludingProcess: 99)
        XCTAssertEqual(choices.map(\.title), ["Doc", "Other"])
        XCTAssertEqual(choices.map(\.application), ["Editor", "Editor"])
    }
}
