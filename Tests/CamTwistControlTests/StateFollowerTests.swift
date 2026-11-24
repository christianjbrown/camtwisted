import CamTwistCore
import XCTest
@testable import CamTwistControl

@MainActor
private final class FakeSceneSync: SceneSyncing {
    var changes: [(old: SceneConfiguration, new: SceneConfiguration)] = []
    func sceneChanged(from old: SceneConfiguration, to new: SceneConfiguration) { changes.append((old, new)) }
}

private final class FakeGlobals: GlobalsKeeping {
    var saved: [GlobalPreferences] = []
    func load() -> GlobalPreferences { GlobalPreferences(AppPreferences()) }
    func save(globals: GlobalPreferences) { saved.append(globals) }
}

@MainActor
private final class FakeLiveSettings: LiveSettingsApplying {
    var applied: [(preferences: AppPreferences, scenes: [SceneConfiguration])] = []
    var heard: [SceneConfiguration] = []
    func apply(_ preferences: AppPreferences, scenes: [SceneConfiguration]) { applied.append((preferences, scenes)) }
    func hear(_ scene: SceneConfiguration) { heard.append(scene) }
}

@MainActor
private final class FakeListener: PreferenceFollowing, StudioFollowing, SceneMarking {
    var preferences: [AppPreferences] = []
    var studios: [StudioSettings] = []
    var marked: [String] = []
    func follow(_ preferences: AppPreferences) { self.preferences.append(preferences) }
    func follow(_ studio: StudioSettings) { studios.append(studio) }
    func markScene(named name: String) { marked.append(name) }
}

@MainActor
private final class FakePreferenceApplier: PreferenceApplying {
    var applied: [(preferences: AppPreferences, isHeard: Bool, isRecording: Bool)] = []
    func apply(_ preferences: AppPreferences, isHeard: Bool, isRecording: Bool) {
        applied.append((preferences, isHeard, isRecording))
    }
}

@MainActor
private final class FakeRecording: RecordingReporting {
    var isRecording = false
}

@MainActor
final class StateFollowerTests: XCTestCase {
    private static let chosenFolder = "/snapshots"

    private let state = FakeState()
    private let sceneSync = FakeSceneSync()
    private let globals = FakeGlobals()
    private let live = FakeLiveSettings()
    private let listener = FakeListener()

    private func makeFollower() -> StateFollower {
        StateFollower(
            state: state, sceneSync: sceneSync, saved: globals, live: live,
            listeners: StateListeners(preferences: [listener], studio: [listener], markers: [listener])
        )
    }

    func testANewSceneOnAirIsDrawnAdoptedByItsSceneAndHeard() {
        let follower = makeFollower()
        let old = state.scene
        let new = SceneConfiguration(items: [sourceItem(.testCard)])
        follower.sceneChanged(from: old, to: old)
        XCTAssertTrue(sceneSync.changes.isEmpty, "the same scene again changes nothing")
        XCTAssertTrue(live.heard.isEmpty)

        state.scene = new
        follower.sceneChanged(from: old, to: new)
        XCTAssertEqual(sceneSync.changes.map(\.new), [new])
        XCTAssertEqual(sceneSync.changes.map(\.old), [old])
        XCTAssertEqual(state.studio.sceneOnAir?.scene, new, "what is on air belongs to the scene on air")
        XCTAssertEqual(live.heard, [new])
    }

    func testChangedScenesPutTheSettingsIntoEffectAgainAndAreSaidToThoseWhoFollow() {
        let follower = makeFollower()
        let old = state.studio
        follower.studioChanged(from: old, to: old)
        XCTAssertTrue(live.applied.isEmpty, "the scenes hold what they held")
        XCTAssertTrue(listener.marked.isEmpty)
        XCTAssertEqual(listener.studios, [old])

        let scene = StudioButton(name: "Wide", scene: SceneConfiguration(items: [sourceItem(.colorBars)]))
        state.studio.buttons = [scene]
        follower.studioChanged(from: old, to: state.studio)
        XCTAssertEqual(live.applied.last?.scenes, [scene.scene])
        XCTAssertTrue(listener.marked.isEmpty, "the scene on air is the one it was")
        XCTAssertEqual(listener.studios.last, state.studio)
    }

    func testASceneComingOnAirIsMarked() {
        let follower = makeFollower()
        let scene = StudioButton(name: "Wide", scene: SceneConfiguration())
        var old = StudioSettings()
        old.buttons = [scene]
        var new = old
        new.onAirID = scene.id
        follower.studioChanged(from: old, to: new)
        XCTAssertEqual(listener.marked, ["Wide"])

        // With no scene on air there is nothing to mark.
        follower.studioChanged(from: new, to: old)
        XCTAssertEqual(listener.marked, ["Wide"])
    }

    func testChangedSettingsAreSavedPutIntoEffectAndSaidToThoseWhoFollow() {
        let follower = makeFollower()
        state.preferences.snapshotsFolder = Self.chosenFolder
        follower.preferencesChanged()
        XCTAssertEqual(globals.saved.last?.snapshotsFolder, Self.chosenFolder)
        XCTAssertEqual(live.applied.last?.preferences, state.preferences)
        XCTAssertEqual(live.applied.last?.scenes, state.studio.buttons.map(\.scene))
        XCTAssertEqual(live.heard, [state.scene])
        XCTAssertEqual(listener.preferences, [state.preferences])
    }

    func testLiveSettingsCarrySoundOnlyWhenASceneHasSomethingToHear() {
        let applier = FakePreferenceApplier()
        let sound = FakeSound()
        let recording = FakeRecording()
        let settings = LiveSettings(
            applier: applier, sound: sound, sceneSound: SceneSoundReader(), recording: recording
        )
        let camera = ChainItem(content: .source(.camera(deviceID: "cam")), volume: 0.5)
        let loud = SceneConfiguration(items: [camera])
        settings.apply(AppPreferences(), scenes: [SceneConfiguration()])
        XCTAssertEqual(applier.applied.last?.isHeard, false)
        settings.apply(AppPreferences(), scenes: [SceneConfiguration(), loud])
        XCTAssertEqual(applier.applied.last?.isHeard, true)
        XCTAssertEqual(applier.applied.last?.isRecording, false)
        recording.isRecording = true
        settings.apply(AppPreferences(), scenes: [])
        XCTAssertEqual(applier.applied.last?.isRecording, true, "a recording under way is said along with the settings")
        settings.hear(loud)
        XCTAssertEqual(sound.levels.last, [camera.id: 0.5])
    }

    func testTheGalleryTakesTheScenesItIsTold() {
        let gallery = SceneGallery(
            capturer: FakeSceneThumbnails(), queue: ImmediateQueue(), turns: SceneThumbnailTurns()
        )
        var studio = StudioSettings()
        studio.buttons = [StudioButton(name: "Wide", scene: SceneConfiguration())]
        gallery.follow(studio)
        XCTAssertEqual(gallery.scenes, studio.buttons)
    }
}
