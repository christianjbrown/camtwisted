import CamTwistCore
import Foundation

/// What has to follow when the scene on air changes: the render loop draws
/// the new one and any script that has just been switched on runs.
@MainActor
final class SceneSync {
    private let renderer: ProgramRendering
    private let scripts: ScriptRunning

    init(renderer: ProgramRendering, scripts: ScriptRunning) {
        self.renderer = renderer
        self.scripts = scripts
    }

    func sceneChanged(from old: SceneConfiguration, to new: SceneConfiguration) {
        renderer.setProgram(new)
        for source in new.scriptsToRun(after: old) where !source.isEmpty {
            scripts.run(source)
        }
    }
}
