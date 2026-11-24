import CamTwistCore
import CamTwistRendering
import CoreGraphics
import Foundation

// What the model asks of the helpers that do its jobs. Each is a narrow
// protocol, so the model depends on what it needs done and not on who
// does it, and a test can stand anything in for any of them.

/// Keeps the settings that stay with this Mac.
protocol GlobalsKeeping {
    func load() -> GlobalPreferences
    func save(globals: GlobalPreferences)
}

extension SavedState: GlobalsKeeping {}

/// Says which apps are watching the virtual camera.
protocol CameraWatcherNaming {
    /// The apps behind some processes, named as one phrase. Empty with none.
    func sentence(for watchers: [Int32]) -> String
}

extension CameraUse: CameraWatcherNaming {}

/// Lists the controls an effect has.
protocol EffectParameterListing {
    func parameters(forEffectNamed name: String) -> [EffectParameter]
}

extension EffectParameters: EffectParameterListing {}

/// Gathers everything there is to pick from.
protocol ChoiceListing {
    func current() -> Choices
}

extension ChoiceCatalog: ChoiceListing {}

/// Sorts the effects into the lists the picker shows.
protocol EffectMenuListing {
    func transitionNames(from effects: [EffectListing]) -> [String]
    func effects(of kind: EffectKind, in effects: [EffectListing]) -> [EffectListing]
}

extension EffectMenu: EffectMenuListing {}

/// Covers a screen with the picture, and uncovers it.
@MainActor
protocol FullScreenCovering {
    func cover(_ displayID: UInt32?) -> UInt32?
    func stillConnected(_ displayID: UInt32?, among displays: [DisplayChoice]) -> UInt32?
}

extension FullScreenController: FullScreenCovering {}

/// Puts the preferences into effect.
@MainActor
protocol PreferenceApplying {
    func apply(_ preferences: AppPreferences, isHeard: Bool, isRecording: Bool)
}

extension PreferenceApplier: PreferenceApplying {}

/// Chooses how much detail the picture is drawn with.
protocol DrawingSizeChoosing {
    func size(for demands: [PictureDemand]) -> DrawingSize
}

// The rule is what chooses the drawing size.
extension DrawingSizeRule: DrawingSizeChoosing {}

/// Says whether a recording is under way.
@MainActor
protocol RecordingReporting: AnyObject {
    var isRecording: Bool { get }
}

extension CaptureModel: RecordingReporting {}

/// Installs and removes the virtual microphone, and says where it stands.
protocol MicrophoneSettingUp {
    var state: MicrophoneInstallState { get }
    func install(_ finished: @escaping () -> Void)
    func remove(_ finished: @escaping () -> Void)
}

extension MicrophoneSetup: MicrophoneSettingUp {}

/// Takes snapshots of the picture on air.
protocol SnapshotTaking {
    func directory(for preferences: AppPreferences) -> URL
    func write(to directory: URL) -> URL?
    func take(to directory: URL)
}

extension SnapshotTaker: SnapshotTaking {}

/// Works out what dragging on the picture does.
protocol PictureDragHandling {
    func target(in scene: SceneConfiguration, selected: UUID?) -> DragTarget?
    func hint(in scene: SceneConfiguration, selected: UUID?) -> String?
    func outline(
        in scene: SceneConfiguration, selected: UUID?, pictureSize: (UUID) -> CGSize?,
        overlayBounds: (String, [String: EffectValue]) -> CGRect?
    ) -> SelectionOutline?
    func drag(
        from start: CGPoint, to end: CGPoint, mode: DragMode, in scene: inout SceneConfiguration, selected: UUID?
    )
    func drag(by delta: CGPoint, in scene: inout SceneConfiguration, selected: UUID?)
    func addStroke(_ points: [CGPoint], to id: UUID, in scene: inout SceneConfiguration)
    func activeTelestrator(in scene: SceneConfiguration) -> UUID?
}

extension PictureDragging: PictureDragHandling {}

/// Turns what a script says into sources and settings.
protocol ScriptSupporting {
    func sourceSpec(named given: String, cameras: [CameraChoice], displays: [DisplayChoice]) -> SourceSpec?
    func setEffectProperty(
        _ property: String, to text: String, ofStep id: UUID, in scene: inout SceneConfiguration
    ) -> Bool
}

extension ScriptingSupport: ScriptSupporting {}

/// Makes the steps and scenes new things start as.
protocol StepBuilding {
    func item(for content: ChainItem.Content) -> ChainItem
    func startingScene(cameras: [CameraChoice]) -> SceneConfiguration
    func bestCamera(among cameras: [CameraChoice]) -> SourceSpec?
    func content(forFile path: String) -> ChainItem.Content?
    func reset(_ item: ChainItem) -> ChainItem
    func canReset(_ content: ChainItem.Content) -> Bool
    func branchTarget(_ target: UUID?, in scene: SceneConfiguration) -> UUID?
}

extension StepBuilder: StepBuilding {}

/// Says how loud each source in a scene is.
protocol SceneSoundReading {
    /// Whether any of some scenes has a source that would be heard.
    func isHeard(in scenes: [SceneConfiguration]) -> Bool
    /// How loud each source in a scene is, by source.
    func levels(in scene: SceneConfiguration) -> [UUID: Double]
}

/// Reads a scene's sound the way the sound mixer does.
struct SceneSoundReader: SceneSoundReading {
    func isHeard(in scenes: [SceneConfiguration]) -> Bool { SceneSound.isHeard(in: scenes) }

    func levels(in scene: SceneConfiguration) -> [UUID: Double] { SceneSound.levels(in: scene) }
}

/// Says where other devices can watch a web stream.
protocol StreamLinkListing {
    func streamLinks(hosts: [String], port: Int) -> [WebStreamLink]
    func movieLinks(hosts: [String], port: Int) -> [WebStreamLink]
}

/// Lists a web stream's addresses as `WebStreamLinks` makes them.
struct WebStreamLinkLister: StreamLinkListing {
    func streamLinks(hosts: [String], port: Int) -> [WebStreamLink] {
        WebStreamLinks.streamLinks(hosts: hosts, port: port)
    }

    func movieLinks(hosts: [String], port: Int) -> [WebStreamLink] {
        WebStreamLinks.movieLinks(hosts: hosts, port: port)
    }
}

/// Says what is wrong with a source that cannot be found.
protocol MissingSourceChecking {
    func problem(with item: ChainItem) -> String?
    func isAnythingMissing(in scene: SceneConfiguration) -> Bool
}

extension MissingSources: MissingSourceChecking {}

/// What is connected right now, by identifier, for telling what is missing.
struct ConnectedDevices {
    let cameras: Set<String>
    let screens: Set<UInt32>
    let microphones: Set<String>
}

/// Gives a scene the MIDI key it has just been played.
protocol MIDIKeyAssigning {
    func assign(note: Int, to id: UUID, studio: inout StudioSettings)
}

extension MIDILearner: MIDIKeyAssigning {}

/// Keeps what is drawn in step with the scene on air.
@MainActor
protocol SceneSyncing {
    func sceneChanged(from old: SceneConfiguration, to new: SceneConfiguration)
}

extension SceneSync: SceneSyncing {}

/// Looks after the scenes: which is on air, which is being changed.
@MainActor
protocol SceneKeeping: AnyObject {
    var isEditingOnAir: Bool { get }
    var isEditedLocked: Bool { get }
    var edited: SceneConfiguration { get set }
    func goLive(with id: UUID)
    func landed(on target: SceneConfiguration)
    func edit(_ id: UUID?)
    @discardableResult
    func add(_ scene: SceneConfiguration) -> UUID
    func duplicate(id: UUID)
    func remove(id: UUID)
}

extension SceneBook: SceneKeeping {}

/// Has the effect picker's small pictures made.
@MainActor
protocol ThumbnailRequesting {
    func requestMissing(among effects: [String], transitions: [String])
}

extension ThumbnailLoader: ThumbnailRequesting {}

/// Hands an action to whichever part of the app does it.
@MainActor
protocol ActionRouting {
    func perform(_ action: TriggerAction)
}

extension ActionRouter: ActionRouting {}

/// Says when to look again at what there is.
@MainActor
protocol RefreshTriggering {
    func start(_ refresh: @escaping @MainActor () -> Void)
}

extension RefreshTriggers: RefreshTriggering {}

/// Tells everything that follows the model's state when it changes.
@MainActor
protocol StateFollowing {
    func sceneChanged(from old: SceneConfiguration, to new: SceneConfiguration)
    func studioChanged(from old: StudioSettings, to new: StudioSettings)
    func preferencesChanged()
    func applySettings()
    func hearScene()
}

extension StateFollower: StateFollowing {}

/// The helpers that work on the model's own state. They need the model to
/// exist first, so they are made the first time one is wanted.
struct AppModelStateHelpers {
    let follower: StateFollowing
    let sceneBook: SceneKeeping
    let setups: SetupDocuments
    let router: ActionRouting
    let midi: MIDIModel
    let shortcuts: ShortcutModel
    let picture: PictureModel
    let pictureDrag: PictureDragSession
    let steps: StepsModel
    let scripts: ScriptDoor
}

/// The parts of the model that have jobs of their own, ready made.
struct AppModelSubModels {
    let choices: ChoicesModel
    let outputs: OutputsModel
    let gallery: SceneGallery
    let capture: CaptureModel
    let fullScreen: FullScreenModel
    let remoteScreens: RemoteScreenPasswords
}
