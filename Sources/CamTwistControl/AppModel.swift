import CamTwistCore
import CamTwistRendering
import Foundation
import Observation

/// The window's state: what is on air, what is saved, and what there is to
/// pick from. Every way of driving the app ends up in `perform`. The jobs
/// themselves live in small types of their own; the model holds the
/// published state the views watch and hands each job to the one that does it.
@MainActor
@Observable
public final class AppModel {
    // MARK: Saved state

    public var scene: SceneConfiguration {
        didSet { stateHelpers.follower.sceneChanged(from: oldValue, to: scene) }
    }
    public var studio: StudioSettings {
        didSet {
            stateHelpers.follower.studioChanged(from: oldValue, to: studio)
            // Saved as each change is made, so a crash or a power cut loses nothing.
            stateHelpers.setups.autosave()
        }
    }
    public var preferences: AppPreferences {
        didSet {
            stateHelpers.follower.preferencesChanged()
            stateHelpers.setups.autosave()
        }
    }

    // MARK: Live state

    public var studioPreview: SceneConfiguration? {
        didSet { renderer.setPreview(studioPreview) }
    }
    public internal(set) var isTransitioning = false
    /// The scene whose steps are showing when it is not the one on air.
    public var editedSceneID: UUID?
    /// The step whose settings are in focus. Dragging on the picture moves it.
    public var selectedStepID: UUID?
    /// The source whose branch picker additions go into, or nil for the
    /// main chain.
    public var branchTarget: UUID?
    /// The steps whose settings are showing.
    public var expandedSteps: Set<UUID> = []
    /// The setup file being worked on, when there is one.
    public internal(set) var documentURL: URL?
    /// Why the last setup file could not be opened or saved. Clears on the next success.
    public internal(set) var setupProblem: String?
    /// Whether the app is on a fresh start, with no setup file opened. The
    /// scene picker is open then, ready for the first thing to be added.
    public internal(set) var startsAfresh = true

    // MARK: The parts with jobs of their own

    /// What there is to pick from: cameras, screens, pictures, effects.
    public let choices: ChoicesModel
    /// Where the picture is going, and how that is getting on.
    public let outputs: OutputsModel
    /// The small pictures of the scenes, for the studio window.
    public let gallery: SceneGallery
    /// Recording the picture on air and saving snapshots of it.
    public let capture: CaptureModel
    /// The display the picture covers, when it covers one.
    public let fullScreen: FullScreenModel
    /// The passwords of computers shown over VNC.
    public let remoteScreens: RemoteScreenPasswords
    /// The MIDI keys: the last note played and the scene learning one.
    public var midi: MIDIModel { stateHelpers.midi }
    /// The keyboard shortcuts: listening for them and the scene learning one.
    public var shortcuts: ShortcutModel { stateHelpers.shortcuts }
    /// Where a key pressed in the window goes: to a scene waiting for its
    /// shortcut first, then to the picture.
    public var keys: KeyPressHandling {
        KeyPressChain(handlers: [stateHelpers.shortcuts, stateHelpers.picture])
    }
    /// Dragging and drawing on the picture.
    public var picture: PictureModel { stateHelpers.picture }
    /// The drag under way on the picture, from the press to the mouse coming up.
    public var pictureDrag: PictureDragSession { stateHelpers.pictureDrag }
    /// Adding steps to the scene being changed, and resetting them.
    public var steps: StepsModel { stateHelpers.steps }
    /// Starting, opening and saving setup files.
    public var setups: SetupDocuments { stateHelpers.setups }
    /// The app as scripts may see it.
    public var scripts: ScriptSlices {
        let door = stateHelpers.scripts
        return ScriptSlices(scenes: door, actions: door, sources: door, snapshots: door)
    }

    private let renderer: ProgramRendering
    private let refreshTriggers: RefreshTriggering
    private nonisolated let queue: WorkQueueing
    private var isStarted = false

    private let helperMaker: StateHelperMaking
    /// The helpers that work on this model's own state, made the first
    /// time one is wanted, since they need the model to exist.
    @ObservationIgnored private lazy var stateHelpers = helperMaker.makeHelpers(for: self)

    init(
        parts: AppModelSubModels,
        preferences: AppPreferences,
        renderer: ProgramRendering,
        refreshTriggers: RefreshTriggering,
        queue: WorkQueueing,
        helperMaker: StateHelperMaking
    ) {
        // Every launch is a fresh start: only what stays with this Mac is brought back.
        self.preferences = preferences
        studio = StudioSettings()
        scene = .initial

        choices = parts.choices
        outputs = parts.outputs
        gallery = parts.gallery
        capture = parts.capture
        fullScreen = parts.fullScreen
        remoteScreens = parts.remoteScreens

        self.renderer = renderer
        self.refreshTriggers = refreshTriggers
        self.queue = queue
        self.helperMaker = helperMaker

        studio.adoptProgram(scene)
        // Said outright, so those that follow the scenes know them from the
        // start whether or not setting them above told them.
        gallery.follow(studio)
        capture.follow(studio)
        // Installing or removing the microphone restarts the audio server,
        // so the outputs are put into effect again afterwards.
        outputs.microphone.onChanged = { [weak self] in
            self?.stateHelpers.follower.applySettings()
            self?.refresh()
        }
        // A recording counts among the outputs that say how much detail
        // is drawn, so starting or stopping one puts them into effect again.
        capture.onRecordingChanged = { [weak self] in
            self?.stateHelpers.follower.applySettings()
        }
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        refresh()
        // The first scene is chosen once the cameras are known. A setup file
        // opened before this has already put its own scene on air.
        if startsAfresh {
            startFreshScene()
            // A fresh start has nothing to lose until something is changed.
            stateHelpers.setups.markSaved()
        }
        renderer.setProgram(scene)
        let queue = self.queue
        renderer.onTransitionFinished { [weak self] target in
            queue.main { self?.transitionFinished(on: target) }
        }
        renderer.start()
        stateHelpers.midi.start()
        stateHelpers.shortcuts.start()
        fullScreen.start()
        stateHelpers.follower.applySettings()
        refreshTriggers.start { [weak self] in self?.refresh() }
    }

    public func refresh() {
        choices.refresh()
        fullScreen.refresh(among: choices.displays)
        capture.refresh()
        gallery.takeNext()
        outputs.refresh()
        // Said again each time round, so a source that has only just
        // started running is heard too.
        stateHelpers.follower.hearScene()
    }

    // MARK: Actions

    public func performOnMain(_ action: TriggerAction) {
        stateHelpers.router.perform(action)
    }

    func startFreshScene() {
        scene = stateHelpers.steps.startingScene()
        // The first source is chosen, with its settings folded away.
        selectedStepID = scene.items.first?.id
    }

    private func transitionFinished(on target: SceneConfiguration) {
        stateHelpers.sceneBook.landed(on: target)
    }

    // MARK: Scenes

    /// The scene whose steps are being changed: the one on air, or another,
    /// which shows in the preview as it is changed.
    public var editedScene: SceneConfiguration {
        get { stateHelpers.sceneBook.edited }
        set { stateHelpers.sceneBook.edited = newValue }
    }

    /// Whether the scene being changed is the one on air.
    public var isEditingOnAir: Bool { stateHelpers.sceneBook.isEditingOnAir }

    /// Whether the scene being changed is locked against changes.
    public var isEditedSceneLocked: Bool { stateHelpers.sceneBook.isEditedLocked }

    /// Chooses the scene to change.
    public func editScene(id: UUID?) {
        stateHelpers.sceneBook.edit(id)
        selectedStepID = nil
        branchTarget = nil
    }

    /// Adds a scene with the usual first source in it, ready to be changed.
    public func addScene() {
        stateHelpers.sceneBook.add(stateHelpers.steps.startingScene())
    }

    public func duplicateScene(id: UUID) {
        stateHelpers.sceneBook.duplicate(id: id)
    }

    /// Removes a scene. The one on air cannot be removed.
    public func removeScene(id: UUID) {
        stateHelpers.sceneBook.remove(id: id)
    }

    /// Puts a scene on air, at once or through its own transition.
    public func goLive(withScene id: UUID) {
        stateHelpers.sceneBook.goLive(with: id)
    }

    // MARK: The studio window

    /// The scene lined up in the preview, when what is there is a scene.
    public var previewedSceneID: UUID? {
        studioPreview.flatMap(studio.button(showing:))?.id
    }

    /// Lines a scene up in the preview without putting it on air. The scene
    /// on air has nothing to line up, so asking for it clears the preview.
    public func previewScene(id: UUID) {
        let scene = studio.buttons.first { $0.id == id && id != studio.onAirID }
        studioPreview = scene?.scene
    }

    /// Puts the scene in the preview on air at once, whatever switch it has.
    public func cutToPreview() {
        performOnMain(.studioCut)
    }

    /// Puts the scene in the preview on air with the transition chosen in
    /// the studio, or else the way that scene asks.
    public func goLiveWithPreview() {
        performOnMain(.studioTransition)
    }

    /// Puts a scene on air from the studio the way the studio switches:
    /// lined up, then taken. The scene on air already stays as it is.
    public func goLiveFromStudio(withScene id: UUID) {
        previewScene(id: id)
        goLiveWithPreview()
    }
}

// The slices of the model that its helpers work on.
extension AppModel: HelpedState {}
