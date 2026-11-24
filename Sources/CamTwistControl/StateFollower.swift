import CamTwistCore
import Foundation

/// Told when the settings change.
@MainActor
protocol PreferenceFollowing: AnyObject {
    func follow(_ preferences: AppPreferences)
}

extension OutputsModel: PreferenceFollowing {}

/// Told when the scenes change.
@MainActor
protocol StudioFollowing: AnyObject {
    func follow(_ studio: StudioSettings)
}

extension SceneGallery: StudioFollowing {
    /// Takes the scenes there now are.
    func follow(_ studio: StudioSettings) {
        scenes = studio.buttons
    }
}

/// Marks a scene coming on air in whatever it is sending or keeping.
@MainActor
protocol SceneMarking: AnyObject {
    func markScene(named name: String)
}

extension OutputsModel: SceneMarking {}

/// Puts the settings into effect with the sound the scenes call for.
@MainActor
protocol LiveSettingsApplying {
    /// Puts the preferences into effect. The streams carry sound only
    /// when one of the scenes has something to be heard.
    func apply(_ preferences: AppPreferences, scenes: [SceneConfiguration])
    /// Tells the mix which sources in the scene on air are heard, and how loud.
    func hear(_ scene: SceneConfiguration)
}

/// Puts the settings into effect and sets the mix, reading each scene's
/// sound to know what there is to hear, and whether a recording is under way.
@MainActor
struct LiveSettings: LiveSettingsApplying {
    let applier: PreferenceApplying
    let sound: SoundCapturing
    let sceneSound: SceneSoundReading
    let recording: RecordingReporting

    func apply(_ preferences: AppPreferences, scenes: [SceneConfiguration]) {
        applier.apply(preferences, isHeard: sceneSound.isHeard(in: scenes), isRecording: recording.isRecording)
    }

    func hear(_ scene: SceneConfiguration) {
        sound.setSourceLevels(sceneSound.levels(in: scene))
    }
}

/// Everything that is told when the model's state changes.
struct StateListeners {
    let preferences: [PreferenceFollowing]
    let studio: [StudioFollowing]
    let markers: [SceneMarking]
}

/// What has to follow when the scene on air, the scenes or the settings
/// change: the one place that knows who is told what.
@MainActor
final class StateFollower {
    /// The model owns this helper, so it is not held on to from here.
    private unowned let state: FollowedState
    private let sceneSync: SceneSyncing
    private let saved: GlobalsKeeping
    private let live: LiveSettingsApplying
    private let listeners: StateListeners

    init(
        state: FollowedState, sceneSync: SceneSyncing, saved: GlobalsKeeping, live: LiveSettingsApplying,
        listeners: StateListeners
    ) {
        self.state = state
        self.sceneSync = sceneSync
        self.saved = saved
        self.live = live
        self.listeners = listeners
    }

    func sceneChanged(from old: SceneConfiguration, to new: SceneConfiguration) {
        guard new != old else { return }
        sceneSync.sceneChanged(from: old, to: new)
        // What is on air belongs to the scene on air.
        state.studio.adoptProgram(new)
        hearScene()
    }

    func studioChanged(from old: StudioSettings, to new: StudioSettings) {
        // Whether there is any sound to carry depends on what the scenes hold.
        if new.buttons.map(\.scene) != old.buttons.map(\.scene) {
            applySettings()
        }
        // A different scene on air is marked in whatever marks them.
        if new.onAirID != old.onAirID, let scene = new.sceneOnAir {
            listeners.markers.forEach { $0.markScene(named: scene.name) }
        }
        listeners.studio.forEach { $0.follow(new) }
    }

    func preferencesChanged() {
        let preferences = state.preferences
        saved.save(globals: GlobalPreferences(preferences))
        applySettings()
        hearScene()
        listeners.preferences.forEach { $0.follow(preferences) }
    }

    /// Puts the settings into effect as they now stand.
    func applySettings() {
        live.apply(state.preferences, scenes: state.studio.buttons.map(\.scene))
    }

    /// Tells the mix which sources on air are heard, and how loud. With
    /// nothing wanting the mix, none are.
    func hearScene() {
        live.hear(state.scene)
    }
}
