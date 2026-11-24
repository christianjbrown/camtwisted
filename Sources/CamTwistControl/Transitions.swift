import CamTwistCore
import Foundation

/// Starts the fade to a new picture and lands the buses when it ends.
@MainActor
final class TransitionRunner {
    /// The model owns this helper, so it is not held on to from here.
    private unowned let state: StudioState
    private let renderer: ProgramRendering

    init(state: StudioState, renderer: ProgramRendering) {
        self.state = state
        self.renderer = renderer
    }

    /// Starts a transition towards a scene.
    func begin(to target: SceneConfiguration, named name: String, duration: Double) {
        state.isTransitioning = true
        renderer.startTransition(to: target, named: name, duration: duration)
    }

    /// The render loop reached the target: it is on air now.
    func finish(on target: SceneConfiguration) {
        let bus = StudioBus(program: state.scene, preview: state.studioPreview)
            .landing(on: target, swapMode: state.studio.swapMode)
        state.scene = bus.program
        state.studioPreview = bus.preview
        state.isTransitioning = false
    }
}
