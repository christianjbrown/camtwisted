import CamTwistCore
import Foundation

// What a script may see and change of the app, a slice at a time, so a
// command depends only on the slice it uses.

/// The scenes as a script may see and change them.
@MainActor
public protocol ScriptedScenes: AnyObject {
    var scene: SceneConfiguration { get set }
    var studio: StudioSettings { get set }
}

/// What a script may have the app do.
@MainActor
public protocol ScriptActing: AnyObject {
    func performOnMain(_ action: TriggerAction)
    func addStep(_ content: ChainItem.Content)
    func setEffectProperty(_ property: String, to text: String, ofStep id: UUID) -> Bool
}

/// Finds the source a script means by a name.
@MainActor
public protocol ScriptSourceFinding: AnyObject {
    func sourceSpec(named name: String) -> SourceSpec?
}

/// Saves the picture on air for a script.
@MainActor
public protocol ScriptSnapshotting: AnyObject {
    func writeSnapshot() -> URL?
}

/// The slices of the app a script may reach, each kept apart, so whatever
/// is handed these takes out only the slice it uses. They are held weakly:
/// the app owns what they point at.
@MainActor
public struct ScriptSlices {
    public private(set) weak var scenes: ScriptedScenes?
    public private(set) weak var actions: ScriptActing?
    public private(set) weak var sources: ScriptSourceFinding?
    public private(set) weak var snapshots: ScriptSnapshotting?

    public init(
        scenes: ScriptedScenes, actions: ScriptActing, sources: ScriptSourceFinding, snapshots: ScriptSnapshotting
    ) {
        self.scenes = scenes
        self.actions = actions
        self.sources = sources
        self.snapshots = snapshots
    }
}
