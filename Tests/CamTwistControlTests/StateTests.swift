import CamTwistCore
import XCTest
@testable import CamTwistControl

final class AppPreferencesTests: XCTestCase {
    func testPreferencesSavedWithFewerKeysStillLoad() throws {
        let old = Data(#"{"mirrorsPreview":true,"keepsWindowOnTop":false}"#.utf8)
        let loaded = try JSONDecoder().decode(AppPreferences.self, from: old)
        XCTAssertTrue(loaded.mirrorsPreview)
        XCTAssertFalse(loaded.keepsWindowOnTop)
        XCTAssertEqual(loaded.recording, RecordingOptions(), "a recording is made the usual way")
        XCTAssertNil(loaded.recordingsFolder)
    }

    func testPreferencesSavedWhenThePictureSizeWasChosenByHandStillLoad() throws {
        // The key is no longer kept: the size now follows what the outputs ask for.
        let old = Data(#"{"mirrorsPreview":false,"keepsWindowOnTop":true,"drawingSize":"ultraHD"}"#.utf8)
        let loaded = try JSONDecoder().decode(AppPreferences.self, from: old)
        XCTAssertTrue(loaded.keepsWindowOnTop)
        let saved = String(decoding: try JSONEncoder().encode(loaded), as: UTF8.self)
        XCTAssertFalse(saved.contains("drawingSize"), "and it is gone the next time they are saved")
    }

    func testRecordingOptionsAreMadeToFitWhateverIsPutThere() {
        var preferences = AppPreferences()
        preferences.recording = RecordingOptions(container: .mpeg4, pictureCodec: .proRes422, soundCodec: .linearPCM)
        XCTAssertEqual(preferences.recording, RecordingOptions(container: .mpeg4))
        XCTAssertEqual(preferences.recordingSettings, RecordingOptions(container: .mpeg4))

        // Options that reached a file some other way are made to fit when read.
        preferences.recordingSettings = RecordingOptions(container: .mpeg4, soundCodec: .linearPCM)
        XCTAssertEqual(preferences.recording.soundCodec, .aac)
    }
}

final class SavedStateTests: XCTestCase {
    func testAnEmptyStoreGivesTheDefaults() {
        XCTAssertEqual(SavedState(keyValueStore: FakeKeyValueStore()).load(), GlobalPreferences(AppPreferences()))
    }

    func testTheGlobalPreferencesComeBackOnTheNextLaunch() {
        let store = FakeKeyValueStore()
        var preferences = AppPreferences()
        preferences.snapshotsFolder = "/snapshots"
        preferences.rtmp.streamKey = "secret"
        SavedState(keyValueStore: store).save(globals: GlobalPreferences(preferences))

        let loaded = SavedState(keyValueStore: store).load()
        XCTAssertEqual(loaded.snapshotsFolder, "/snapshots")
        XCTAssertEqual(loaded.rtmpStreamKey, "secret")
    }

    func testGlobalsSavedBeforeRecordingsHadAFolderStillLoad() {
        let store = FakeKeyValueStore()
        store.values["globalPreferences"] = Data(#"{"snapshotsFolder":"/snapshots","rtmpStreamKey":"secret"}"#.utf8)
        let loaded = SavedState(keyValueStore: store).load()
        XCTAssertEqual(loaded.snapshotsFolder, "/snapshots")
        XCTAssertEqual(loaded.rtmpStreamKey, "secret")
        XCTAssertNil(loaded.recordingsFolder)
    }
}

final class GlobalPreferencesTests: XCTestCase {
    func testTheGlobalOnesLayerOverAnotherSetOfPreferences() {
        var mine = AppPreferences()
        mine.snapshotsFolder = "/snapshots"
        mine.recordingsFolder = "/recordings"
        mine.rtmp.streamKey = "secret"
        var theirs = AppPreferences()
        theirs.mirrorsPreview = true
        theirs.rtmp.address = "rtmp://example.com/live"

        let result = GlobalPreferences(mine).applied(to: theirs)
        XCTAssertEqual(result.snapshotsFolder, "/snapshots")
        XCTAssertEqual(result.recordingsFolder, "/recordings")
        XCTAssertEqual(result.rtmp.streamKey, "secret")
        XCTAssertTrue(result.mirrorsPreview, "the rest is theirs")
        XCTAssertEqual(result.rtmp.address, "rtmp://example.com/live")
    }

    func testRemovingThemLeavesTheRest() {
        var preferences = AppPreferences()
        preferences.snapshotsFolder = "/snapshots"
        preferences.recordingsFolder = "/recordings"
        preferences.recording.container = .mpeg4
        preferences.rtmp.streamKey = "secret"
        preferences.rtmp.address = "rtmp://example.com/live"
        preferences.keepsWindowOnTop = true

        let result = GlobalPreferences.removed(from: preferences)
        XCTAssertNil(result.snapshotsFolder)
        XCTAssertNil(result.recordingsFolder)
        XCTAssertEqual(result.recording.container, .mpeg4, "how a recording is made goes with the setup")
        XCTAssertEqual(result.rtmp.streamKey, "")
        XCTAssertEqual(result.rtmp.address, "rtmp://example.com/live")
        XCTAssertTrue(result.keepsWindowOnTop)
    }
}

@MainActor
final class SceneSyncTests: XCTestCase {
    func testAChangedSceneIsDrawn() {
        let renderer = FakeRenderer()
        let sync = SceneSync(renderer: renderer, scripts: FakeScripts())
        let scene = SceneConfiguration(items: [sourceItem(.testCard)])
        sync.sceneChanged(from: .initial, to: scene)
        XCTAssertEqual(renderer.programs, [scene])
    }

    func testScriptsSwitchedOnByTheChangeRunButEmptyOnesDoNot() {
        let scripts = FakeScripts()
        let sync = SceneSync(renderer: FakeRenderer(), scripts: scripts)
        let scene = SceneConfiguration(items: [
            ChainItem(content: .script(source: "beep")),
            ChainItem(content: .script(source: "")),
        ])
        sync.sceneChanged(from: SceneConfiguration(), to: scene)
        XCTAssertEqual(scripts.sources, ["beep"])
    }
}

@MainActor
final class TransitionRunnerTests: XCTestCase {
    func testBeginningAFadeUsesTheChosenTransition() {
        let state = FakeState()
        let renderer = FakeRenderer()
        let target = SceneConfiguration(items: [sourceItem(.colorBars)])
        TransitionRunner(state: state, renderer: renderer).begin(to: target, named: "Wipe", duration: 2.5)
        XCTAssertTrue(state.isTransitioning)
        XCTAssertEqual(renderer.transitions.first?.scene, target)
        XCTAssertEqual(renderer.transitions.first?.name, "Wipe")
        XCTAssertEqual(renderer.transitions.first?.duration, 2.5)
    }

    func testLandingOnTheTargetPutsItOnAirAndEndsTheFade() {
        let state = FakeState()
        state.isTransitioning = true
        let preview = SceneConfiguration(items: [sourceItem(.testCard)])
        state.studioPreview = preview
        let target = SceneConfiguration(items: [sourceItem(.colorBars)])
        TransitionRunner(state: state, renderer: FakeRenderer()).finish(on: target)
        XCTAssertEqual(state.scene, target)
        XCTAssertEqual(state.studioPreview, preview)
        XCTAssertFalse(state.isTransitioning)
    }

    func testLandingInSwapModeSendsTheOldProgramToPreview() {
        let state = FakeState()
        state.studio.swapMode = true
        let old = SceneConfiguration(items: [sourceItem(.testCard)])
        state.scene = old
        TransitionRunner(state: state, renderer: FakeRenderer()).finish(on: SceneConfiguration())
        XCTAssertEqual(state.studioPreview, old)
    }
}

final class MIDILearnerTests: XCTestCase {
    func testTheNoteGoesToTheLookWaitingForIt() {
        var studio = StudioSettings(buttons: [StudioButton(name: "Wide", scene: SceneConfiguration())])
        MIDILearner().assign(note: 61, to: studio.buttons[0].id, studio: &studio)
        XCTAssertEqual(studio.buttons[0].midiNote, 61)
    }

    func testAnUnknownWaiterChangesNothing() {
        var studio = StudioSettings(buttons: [StudioButton(name: "Wide", scene: SceneConfiguration())])
        MIDILearner().assign(note: 62, to: UUID(), studio: &studio)
        XCTAssertNil(studio.buttons[0].midiNote)
    }
}
