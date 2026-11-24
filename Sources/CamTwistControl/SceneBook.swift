import CamTwistCore
import Foundation

/// The list of scenes: which is on air, which is being changed, and how
/// one takes over from another.
@MainActor
final class SceneBook {
    /// The model owns this helper, so it is not held on to from here.
    private unowned let state: StudioState
    private let transitions: TransitionRunner
    /// The scene a transition under way is heading for.
    private var arriving: UUID?

    init(state: StudioState, transitions: TransitionRunner) {
        self.state = state
        self.transitions = transitions
    }

    // MARK: Going on air

    /// Puts a scene on air, at once or through its own transition.
    func goLive(with id: UUID) {
        guard let scene = state.studio.buttons.first(where: { $0.id == id }),
              !state.isTransitioning, id != state.studio.onAirID
        else { return }
        if state.editedSceneID == id {
            edit(nil)
        }
        if scene.cutsInstantly {
            state.studio.onAirID = id
            state.scene = scene.scene
        } else {
            arriving = id
            transitions.begin(to: scene.scene, named: scene.switchName, duration: scene.switchTime)
        }
    }

    /// A transition has reached its target, which is now on air.
    func landed(on target: SceneConfiguration) {
        if let id = arriving, state.studio.buttons.contains(where: { $0.id == id }) {
            state.studio.onAirID = id
        } else {
            state.studio.markOnAir(showing: target)
        }
        arriving = nil
        transitions.finish(on: target)
    }

    // MARK: Changing a scene

    /// Whether the scene being changed is the one on air.
    var isEditingOnAir: Bool { offAirIndex == nil }

    /// The scene being changed: the one on air, or another, which is shown
    /// in the preview as it is changed.
    var edited: SceneConfiguration {
        get { offAirIndex.map { state.studio.buttons[$0].scene } ?? state.scene }
        set {
            // A locked scene stays as it is, whatever asks to change it.
            guard !isEditedLocked else { return }
            guard let index = offAirIndex else {
                state.scene = newValue
                return
            }
            state.studio.buttons[index].scene = newValue
            state.studioPreview = newValue
        }
    }

    /// Chooses the scene to change. The one on air, or none, means the one on air.
    func edit(_ id: UUID?) {
        let scene = state.studio.buttons.first { $0.id == id && id != state.studio.onAirID }
        state.editedSceneID = scene?.id
        state.studioPreview = scene?.scene
    }

    @discardableResult
    func add(_ scene: SceneConfiguration) -> UUID {
        let id = state.studio.addScene(scene)
        edit(id)
        return id
    }

    func duplicate(id: UUID) {
        if let copy = state.studio.duplicateScene(id: id) {
            edit(copy)
        }
    }

    func remove(id: UUID) {
        // Neither the scene on air nor a locked one goes.
        guard id != state.studio.onAirID,
              state.studio.buttons.first(where: { $0.id == id })?.isLocked != true
        else { return }
        if state.editedSceneID == id {
            edit(nil)
        }
        state.studio.removeScene(id: id)
    }

    /// Whether the scene being changed is locked against changes.
    var isEditedLocked: Bool {
        let edited = offAirIndex.map { state.studio.buttons[$0] } ?? state.studio.sceneOnAir
        return edited?.isLocked == true
    }

    private var offAirIndex: Int? {
        guard let id = state.editedSceneID, id != state.studio.onAirID else { return nil }
        return state.studio.buttons.firstIndex { $0.id == id }
    }
}
