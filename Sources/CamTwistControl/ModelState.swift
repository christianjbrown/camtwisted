import CamTwistCore
import Foundation

// The slices of the model's published state that the helper types work on.
// The model is the one thing that conforms, so each helper sees only what
// it needs.

@MainActor
protocol SceneState: AnyObject {
    var scene: SceneConfiguration { get set }
}

@MainActor
protocol StudioState: SceneState {
    var studio: StudioSettings { get set }
    var studioPreview: SceneConfiguration? { get set }
    /// The scene being changed when it is not the one on air.
    var editedSceneID: UUID? { get set }
    var isTransitioning: Bool { get set }
}

/// The slice that whatever follows the state's changes reads from.
@MainActor
protocol FollowedState: SceneState {
    var studio: StudioSettings { get set }
    var preferences: AppPreferences { get }
}

/// The slice a MIDI note, a keyboard shortcut or a scene's timer works
/// on: the scenes, their keys, and putting one on air.
@MainActor
protocol KeyPlayedState: AnyObject {
    var studio: StudioSettings { get set }
    func goLive(withScene id: UUID)
}

/// The slice that working on the picture needs: the scene on air, the
/// scene being changed and the step in focus.
@MainActor
protocol PictureState: SceneState {
    var selectedStepID: UUID? { get set }
    var editedScene: SceneConfiguration { get set }
    var isEditedSceneLocked: Bool { get }
}

/// The slice of the model a script may see and change.
@MainActor
protocol ScriptedState: SceneState {
    var studio: StudioSettings { get set }
    var editedScene: SceneConfiguration { get set }
    func performOnMain(_ action: TriggerAction)
}

/// The slice that adding and resetting steps works on: the scene being
/// changed, where additions go, and which steps are open and in focus.
@MainActor
protocol StepEditingState: AnyObject {
    var editedScene: SceneConfiguration { get set }
    var selectedStepID: UUID? { get set }
    var branchTarget: UUID? { get set }
    var expandedSteps: Set<UUID> { get set }
}
