import CamTwistCore
import CamTwistRendering
import Foundation

/// The cameras and saved pictures that new steps and scenes start from.
@MainActor
protocol StartingChoices: AnyObject {
    var cameras: [CameraChoice] { get }
    var savedPictures: [SavedPicture] { get }
}

extension ChoicesModel: StartingChoices {}

/// Adds a step where additions are going.
@MainActor
protocol StepAdding: AnyObject {
    func add(_ content: ChainItem.Content)
}

/// The steps of the scene being changed: adding them, putting their
/// settings back, and what new ones start as.
@MainActor
public final class StepsModel: StepAdding, FileAdding {
    /// The model owns this, so it is not held on to from here.
    private unowned let state: StepEditingState
    private let builder: StepBuilding
    private let choices: StartingChoices

    init(state: StepEditingState, builder: StepBuilding, choices: StartingChoices) {
        self.state = state
        self.builder = builder
        self.choices = choices
    }

    /// Adds a step where additions are currently going: the main chain, or
    /// the branch of the source chosen with "Add to this source only".
    public func add(_ content: ChainItem.Content) {
        let target = builder.branchTarget(state.branchTarget, in: state.editedScene)
        if target != state.branchTarget {
            state.branchTarget = target
        }
        add(content, before: nil, inBranchOf: target)
    }

    /// Adds a step with its settings open and ready to be dragged about on
    /// the picture.
    public func add(_ content: ChainItem.Content, before target: UUID?, inBranchOf parent: UUID?) {
        let item = builder.item(for: content)
        state.editedScene.insert(item, before: target, inBranchOf: parent)
        state.expandedSteps.insert(item.id)
        state.selectedStepID = item.id
    }

    /// Adds the image and video files among some dropped on the picture.
    public func addFiles(_ paths: [String]) {
        paths.compactMap(builder.content(forFile:)).forEach(add)
    }

    /// Whether a step has settings that a reset would put back.
    public func canReset(_ item: ChainItem) -> Bool {
        builder.canReset(item.content)
    }

    /// Puts a step's settings back to how they start, keeping what it shows.
    public func reset(id: UUID) {
        state.editedScene.update(id: id) { $0 = builder.reset($0) }
    }

    /// What a new camera source starts as: the camera with the most detail,
    /// or nil when there is no camera.
    public var newCameraSource: SourceSpec? { builder.bestCamera(among: choices.cameras) }

    /// What a new image source starts as: no picture chosen yet.
    public var newImageSource: SourceSpec { .image(path: Self.noPictureChosen) }

    /// The path of an image source whose picture has not been chosen.
    private static let noPictureChosen = ""

    /// The scene a fresh start, or a new scene, begins with.
    func startingScene() -> SceneConfiguration {
        builder.startingScene(cameras: choices.cameras)
    }
}
