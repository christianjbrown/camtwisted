import CamTwistCore
import Foundation

/// Carries out one group of actions. A handler that does not know an action
/// says so, and the router tries the next.
@MainActor
protocol ActionHandling {
    /// Returns whether the action belonged to this handler.
    func handle(_ action: TriggerAction) -> Bool
}

/// Carries out an action by finding the handler for it.
@MainActor
final class ActionRouter {
    private let handlers: [ActionHandling]

    init(handlers: [ActionHandling]) {
        self.handlers = handlers
    }

    func perform(_ action: TriggerAction) {
        _ = handlers.contains { $0.handle(action) }
    }
}

/// Clearing the scene on air.
@MainActor
final class SceneActionHandler: ActionHandling {
    /// The model owns this helper, so it is not held on to from here.
    private unowned let state: SceneState

    init(state: SceneState) {
        self.state = state
    }

    func handle(_ action: TriggerAction) -> Bool {
        guard case .clearScene = action else { return false }
        state.scene = SceneConfiguration()
        return true
    }
}

/// The preview and program buses of the Studio tab.
@MainActor
final class StudioActionHandler: ActionHandling {
    /// The model owns this helper, so it is not held on to from here.
    private unowned let state: StudioState
    private let transitions: TransitionRunner

    init(state: StudioState, transitions: TransitionRunner) {
        self.state = state
        self.transitions = transitions
    }

    func handle(_ action: TriggerAction) -> Bool {
        switch action {
        case .studioPreview(let name):
            if let button = state.studio.button(named: name) { state.studioPreview = button.scene }
        case .studioPunch(let name):
            if let button = state.studio.button(named: name) {
                state.studio.onAirID = button.id
                state.scene = button.scene
            }
        case .studioCut:
            cut()
        case .studioTransition:
            goLiveWithPreview()
        case .studioClear:
            state.studioPreview = nil
        default:
            return false
        }
        return true
    }

    private func cut() {
        let bus = StudioBus(program: state.scene, preview: state.studioPreview)
            .cutting(swapMode: state.studio.swapMode)
        state.studio.markOnAir(showing: bus.program)
        state.scene = bus.program
        state.studioPreview = bus.preview
    }

    /// Puts the preview on air with the transition chosen in the studio,
    /// or else the way its scene asks: at once, or through its transition.
    /// A preview that is no saved scene fades in with the studio's own.
    private func goLiveWithPreview() {
        guard let target = state.studioPreview, !state.isTransitioning else { return }
        let change = state.studio.studioSwitch(to: state.studio.button(showing: target))
        if change.cutsInstantly {
            cut()
        } else {
            transitions.begin(to: target, named: change.name, duration: change.duration)
        }
    }
}

/// Running a piece of AppleScript.
@MainActor
final class ScriptActionHandler: ActionHandling {
    private let scripts: ScriptRunning

    init(scripts: ScriptRunning) {
        self.scripts = scripts
    }

    func handle(_ action: TriggerAction) -> Bool {
        guard case .runAppleScript(let source) = action else { return false }
        scripts.run(source)
        return true
    }
}
