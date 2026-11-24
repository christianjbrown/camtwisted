import CamTwistCore
import CamTwistRendering
import Foundation

/// Everything the model's helpers work on. Only the maker of the helpers
/// sees it whole: it hands each helper the one slice that helper needs.
typealias HelpedState = SetupDocumentState & FollowedState & KeyPlayedState & PictureState & ScriptedState
    & StepEditingState

/// Makes the helpers that work on the model's own state, once the model
/// exists for them to work on.
@MainActor
protocol StateHelperMaking {
    func makeHelpers(for state: HelpedState) -> AppModelStateHelpers
}

/// Makes the app's own helpers from the parts the app handed in.
@MainActor
struct StateHelperMaker: StateHelperMaking {
    let parts: AppParts
    let subModels: AppModelSubModels
    let effectParameters: EffectParameters
    let saved: GlobalsKeeping
    let live: LiveSettingsApplying

    func makeHelpers(for state: HelpedState) -> AppModelStateHelpers {
        let transitions = TransitionRunner(state: state, renderer: parts.picture.renderer)
        let picture = PictureModel(
            state: state, dragging: PictureDragging(parameters: effectParameters),
            pictureSizes: parts.picture.pictureSizes, overlayMeasurer: parts.picture.overlayMeasurer
        )
        let steps = StepsModel(
            state: state, builder: StepBuilder(parameters: effectParameters), choices: subModels.choices
        )
        let shortcuts = ShortcutModel(state: state, listener: parts.control.shortcuts, recorder: ShortcutRecorder())
        let handovers = SceneHandoverTimer(state: state, timers: parts.system.timers)
        return AppModelStateHelpers(
            follower: follower(for: state, alsoFollowingScenes: [shortcuts, handovers]),
            sceneBook: SceneBook(state: state, transitions: transitions),
            setups: SetupDocuments(
                state: state, filing: parts.system.filing, windows: parts.system.windows, coder: SetupDocumentCoder()
            ),
            router: ActionRouter(handlers: [
                SceneActionHandler(state: state),
                StudioActionHandler(state: state, transitions: transitions),
                ScriptActionHandler(scripts: parts.control.scripts),
            ]),
            midi: MIDIModel(
                state: state, listener: parts.control.midi, learner: MIDILearner(), queue: parts.system.queue
            ),
            shortcuts: shortcuts,
            picture: picture,
            pictureDrag: PictureDragSession(picture: picture),
            steps: steps,
            scripts: ScriptDoor(
                state: state, scripting: ScriptingSupport(parameters: effectParameters),
                choices: subModels.choices, snapshots: subModels.capture, steps: steps
            )
        )
    }

    /// What follows the state, with the helpers made here that follow the scenes too.
    private func follower(for state: FollowedState, alsoFollowingScenes helpers: [StudioFollowing]) -> StateFollower {
        StateFollower(
            state: state,
            sceneSync: SceneSync(renderer: parts.picture.renderer, scripts: parts.control.scripts),
            saved: saved,
            live: live,
            listeners: StateListeners(
                preferences: [subModels.outputs, subModels.capture],
                studio: [subModels.gallery, subModels.capture] + helpers,
                markers: [subModels.outputs, subModels.capture]
            )
        )
    }
}
