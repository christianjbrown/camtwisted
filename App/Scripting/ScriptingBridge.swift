import CamTwistControl
import CamTwistCore
import Foundation

/// The one doorway from AppleScript into the app. Cocoa scripting creates
/// its command objects itself, so they cannot be handed the model; they
/// reach it here instead.
@MainActor
final class ScriptingBridge {
    static let shared = ScriptingBridge()

    /// The app as scripts may see it, a slice at a time, so each command
    /// reaches only for what it uses.
    var slices: ScriptSlices?

    /// The scenes as scripts may see and change them.
    var scenes: ScriptedScenes? { slices?.scenes }
    /// What scripts may have the app do.
    var actions: ScriptActing? { slices?.actions }
    /// Finds the source a script names.
    var sources: ScriptSourceFinding? { slices?.sources }
    /// Saves the picture on air for a script.
    var snapshots: ScriptSnapshotting? { slices?.snapshots }

    func perform(_ action: TriggerAction) {
        actions?.performOnMain(action)
    }
}
