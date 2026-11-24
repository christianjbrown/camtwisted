import CamTwistCore
import CamTwistRendering
import Foundation

/// The cameras and screens a script can name as sources.
@MainActor
protocol ScriptSourceChoices: AnyObject {
    var cameras: [CameraChoice] { get }
    var displays: [DisplayChoice] { get }
}

extension ChoicesModel: ScriptSourceChoices {}

/// Saves the picture on air as a file.
@MainActor
protocol SnapshotSaving: AnyObject {
    func writeSnapshot() -> URL?
}

extension CaptureModel: SnapshotSaving {}

/// The way in for scripts: what a script may see and change of the app,
/// and nothing else.
@MainActor
public final class ScriptDoor: ScriptedScenes, ScriptActing, ScriptSourceFinding, ScriptSnapshotting {
    /// The model owns this door, so it is not held on to from here.
    private unowned let state: ScriptedState
    private let scripting: ScriptSupporting
    private let choices: ScriptSourceChoices
    private let snapshots: SnapshotSaving
    private let steps: StepAdding

    init(
        state: ScriptedState, scripting: ScriptSupporting, choices: ScriptSourceChoices, snapshots: SnapshotSaving,
        steps: StepAdding
    ) {
        self.state = state
        self.scripting = scripting
        self.choices = choices
        self.snapshots = snapshots
        self.steps = steps
    }

    public var scene: SceneConfiguration {
        get { state.scene }
        set { state.scene = newValue }
    }

    public var studio: StudioSettings {
        get { state.studio }
        set { state.studio = newValue }
    }

    public func performOnMain(_ action: TriggerAction) {
        state.performOnMain(action)
    }

    public func addStep(_ content: ChainItem.Content) {
        steps.add(content)
    }

    /// The source a script means by a name such as "Webcam" or "Desktop".
    public func sourceSpec(named name: String) -> SourceSpec? {
        scripting.sourceSpec(named: name, cameras: choices.cameras, displays: choices.displays)
    }

    /// Sets an effect control from text, as scripts supply it. The control
    /// is found by its key or by the name shown beside it.
    @discardableResult
    public func setEffectProperty(_ property: String, to text: String, ofStep id: UUID) -> Bool {
        scripting.setEffectProperty(property, to: text, ofStep: id, in: &state.editedScene)
    }

    /// Saves the program picture and says where it went.
    public func writeSnapshot() -> URL? {
        snapshots.writeSnapshot()
    }
}
