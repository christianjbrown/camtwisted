import CamTwistCore
import XCTest
@testable import CamTwistControl

@MainActor
final class CaptureModelTests: XCTestCase {
    private static let chosenFolder = "/snapshots"
    private static let recordingsFolder = "/recordings"
    private static let sceneName = "Wide"

    private let recorder = FakeRecorder()
    private let renderer = FakeRenderer()
    private let writer = FakeSnapshotWriter()
    private let files = FakeFiles()

    private func makeCapture() -> CaptureModel {
        CaptureModel(
            preferences: AppPreferences(), recorder: recorder,
            snapshotTaker: SnapshotTaker(frames: renderer, writer: writer, folders: FakeFolders(), files: files),
            files: files
        )
    }

    private func studio(onAir name: String) -> StudioSettings {
        let scene = StudioButton(name: name, scene: SceneConfiguration())
        var studio = StudioSettings()
        studio.buttons = [scene]
        studio.onAirID = scene.id
        return studio
    }

    func testRecordingIsNamedAfterTheSceneOnAirAndGoesToTheFolderLastChosen() {
        let capture = makeCapture()
        XCTAssertEqual(capture.recordingStatus, .off)
        recorder.status = .recording("Show.mov")
        capture.isRecording = true
        XCTAssertEqual(recorder.applied.last?.isOn, true)
        XCTAssertEqual(recorder.applied.last?.folder, FakeFolders().desktopDirectory)
        XCTAssertEqual(recorder.applied.last?.sceneName, "", "no scene on air has been said yet")
        XCTAssertEqual(capture.recordingStatus, .recording("Show.mov"))

        var preferences = AppPreferences()
        preferences.snapshotsFolder = Self.chosenFolder
        capture.follow(preferences)
        capture.follow(studio(onAir: Self.sceneName))
        recorder.status = .off
        capture.isRecording = false
        XCTAssertEqual(recorder.applied.last?.isOn, false)
        XCTAssertEqual(recorder.applied.last?.folder, URL(fileURLWithPath: Self.chosenFolder))
        XCTAssertEqual(recorder.applied.last?.sceneName, Self.sceneName)
        XCTAssertEqual(capture.recordingStatus, .off)

        capture.follow(StudioSettings())
        capture.isRecording = true
        XCTAssertEqual(recorder.applied.last?.sceneName, "", "with no scene on air it has no name")
    }

    func testRecordingsGoToTheirOwnFolderOnceOneIsChosen() {
        let capture = makeCapture()
        XCTAssertEqual(capture.recordingsDirectory, FakeFolders().desktopDirectory, "wherever snapshots go")
        var preferences = AppPreferences()
        preferences.snapshotsFolder = Self.chosenFolder
        preferences.recordingsFolder = ""
        capture.follow(preferences)
        XCTAssertEqual(capture.recordingsDirectory, URL(fileURLWithPath: Self.chosenFolder))

        preferences.recordingsFolder = Self.recordingsFolder
        capture.follow(preferences)
        XCTAssertEqual(capture.recordingsDirectory, URL(fileURLWithPath: Self.recordingsFolder))
        XCTAssertEqual(capture.snapshotsDirectory, URL(fileURLWithPath: Self.chosenFolder), "snapshots stay put")
        capture.isRecording = true
        XCTAssertEqual(recorder.applied.last?.folder, URL(fileURLWithPath: Self.recordingsFolder))

        capture.openRecordingsFolder()
        XCTAssertEqual(files.opened, [URL(fileURLWithPath: Self.recordingsFolder)])
    }

    func testARecordingIsMadeTheWayTheOptionsSayWhenItStarts() {
        let capture = makeCapture()
        var changes = 0
        capture.onRecordingChanged = { changes += 1 }
        var preferences = AppPreferences()
        preferences.recording = RecordingOptions(container: .mpeg4, pictureCodec: .hevc, height: 720)
        capture.follow(preferences)
        capture.isRecording = true
        XCTAssertEqual(recorder.applied.last?.options, preferences.recording)
        XCTAssertEqual(changes, 1, "starting a recording is said, so the outputs are put into effect again")
        capture.isRecording = false
        XCTAssertEqual(changes, 2)
    }

    func testASceneComingOnAirIsMarkedInTheRecording() {
        let capture = makeCapture()
        capture.markScene(named: Self.sceneName)
        XCTAssertEqual(recorder.marked, [Self.sceneName])
    }

    func testRefreshShowsHowTheRecordingIsGettingOn() {
        let capture = makeCapture()
        capture.refresh()
        XCTAssertEqual(capture.recordingStatus, .off)
        recorder.status = .failed("The disk is full.")
        capture.refresh()
        XCTAssertEqual(capture.recordingStatus, .failed("The disk is full."))
    }

    func testSnapshotsGoToTheFolderChosenAndAreShown() {
        let capture = makeCapture()
        XCTAssertEqual(capture.snapshotsDirectory, FakeFolders().desktopDirectory)
        XCTAssertNil(capture.writeSnapshot(), "there is no picture yet")
        renderer.latestProgramFrame = makePixelBuffer()
        writer.result = URL(fileURLWithPath: "/desktop/a.png")
        capture.takeSnapshot()
        XCTAssertEqual(files.revealed, [URL(fileURLWithPath: "/desktop/a.png")])

        var preferences = AppPreferences()
        preferences.snapshotsFolder = Self.chosenFolder
        capture.follow(preferences)
        XCTAssertEqual(capture.writeSnapshot(), writer.result)
        XCTAssertEqual(writer.written.last, URL(fileURLWithPath: Self.chosenFolder))
    }
}
