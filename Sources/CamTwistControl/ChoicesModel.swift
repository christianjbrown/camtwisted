import CamTwistCore
import CamTwistRendering
import CoreGraphics
import Foundation
import Observation

/// What there is to pick from: the cameras, screens, windows, microphones,
/// pictures and effects the pickers offer, kept up to date.
@MainActor
@Observable
public final class ChoicesModel {
    public private(set) var cameras: [CameraChoice] = []
    public private(set) var displays: [DisplayChoice] = []
    public private(set) var windows: [WindowChoice] = []
    public private(set) var audioOutputs: [AudioDeviceChoice] = []
    /// The microphones a microphone source can listen to.
    public private(set) var microphones: [MicrophoneChoice] = []
    /// Pictures in the app's pictures folder, each offered as a source.
    public private(set) var savedPictures: [SavedPicture] = []
    public private(set) var effects: [EffectListing] = []
    /// Small pictures of what each effect does, by effect name.
    public private(set) var thumbnails: [String: CGImage] = [:]

    private let catalog: ChoiceListing
    private let menu: EffectMenuListing
    private let effectParameters: EffectParameterListing
    private let makeMissingSources: (ConnectedDevices) -> MissingSourceChecking
    private let files: FileRevealing
    private let picturesDirectory: URL
    private let effectsDirectory: URL
    private let makeThumbnailLoader: @MainActor (ChoicesModel) -> ThumbnailRequesting
    /// Has the effects' small pictures made. It hands them back here, so
    /// it is made the first time it is wanted.
    @ObservationIgnored private lazy var thumbnailLoader = makeThumbnailLoader(self)

    init(
        catalog: ChoiceListing,
        menu: EffectMenuListing,
        effectParameters: EffectParameterListing,
        makeMissingSources: @escaping (ConnectedDevices) -> MissingSourceChecking,
        files: FileRevealing,
        picturesDirectory: URL,
        effectsDirectory: URL,
        makeThumbnailLoader: @escaping @MainActor (ChoicesModel) -> ThumbnailRequesting
    ) {
        self.catalog = catalog
        self.menu = menu
        self.effectParameters = effectParameters
        self.makeMissingSources = makeMissingSources
        self.files = files
        self.picturesDirectory = picturesDirectory
        self.effectsDirectory = effectsDirectory
        self.makeThumbnailLoader = makeThumbnailLoader
    }

    /// Looks again at what there is, and asks for the small picture of any
    /// effect that has none yet.
    func refresh() {
        let choices = catalog.current()
        assign(\.cameras, choices.cameras)
        assign(\.displays, choices.displays)
        assign(\.windows, choices.windows)
        assign(\.audioOutputs, choices.audioOutputs)
        assign(\.microphones, choices.microphones)
        assign(\.savedPictures, choices.savedPictures)
        assign(\.effects, choices.effects)
        // Transitions are pictured mid-change, so they are asked for apart.
        let transitions = transitionNames
        thumbnailLoader.requestMissing(
            among: effects.map(\.name).filter { !transitions.contains($0) }, transitions: transitions
        )
    }

    /// Keeps the small picture just made for an effect.
    func thumbnailReady(_ image: CGImage, forEffectNamed name: String) {
        thumbnails[name] = image
    }

    /// The ways of switching looks: at once, a plain fade, then the
    /// transition effects in the effects folder.
    public var transitionNames: [String] { menu.transitionNames(from: effects) }

    public func effects(of kind: EffectKind) -> [EffectListing] {
        menu.effects(of: kind, in: effects)
    }

    public func parameters(forEffectNamed name: String) -> [EffectParameter] {
        effectParameters.parameters(forEffectNamed: name)
    }

    /// What is wrong with a step's source: its camera, screen or
    /// microphone is not connected, or its file has gone. Nil when it is
    /// all there.
    public func missingSourceProblem(with item: ChainItem) -> String? {
        missingSources.problem(with: item)
    }

    /// Whether anything in a scene is missing, so it can be seen before
    /// the scene goes on air.
    public func isAnythingMissing(in scene: SceneConfiguration) -> Bool {
        missingSources.isAnythingMissing(in: scene)
    }

    /// Opens the folder whose pictures appear in the picker as sources.
    public func openPicturesFolder() {
        files.openFolder(picturesDirectory)
    }

    public func openEffectsFolder() {
        files.openFolder(effectsDirectory)
    }

    private var missingSources: MissingSourceChecking {
        makeMissingSources(ConnectedDevices(
            cameras: Set(cameras.map(\.id)), screens: Set(displays.map(\.id)),
            microphones: Set(microphones.map(\.id))
        ))
    }

    /// Changes a value only when it differs, so idle refreshes redraw nothing.
    private func assign<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<ChoicesModel, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }
}
