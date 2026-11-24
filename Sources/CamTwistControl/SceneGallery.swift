import CamTwistCore
import CoreGraphics
import Foundation
import Observation

/// The small pictures of the scenes that the studio window shows, taken in
/// turn so the one most out of date is always next.
@MainActor
@Observable
public final class SceneGallery {
    /// A small picture of each scene, by scene, for those that have had one taken.
    public private(set) var sceneThumbnails: [UUID: CGImage] = [:]
    /// Whether the pictures are wanted, which they are while the studio
    /// window is showing. Taking one briefly starts a scene's sources, so
    /// they are only taken while somebody is looking.
    public var showsSceneThumbnails = false {
        didSet {
            if showsSceneThumbnails { takeNext() }
        }
    }

    /// The scenes there are, as the model last said.
    @ObservationIgnored var scenes: [StudioButton] = []

    private let capturer: SceneThumbnailCapturing
    private nonisolated let queue: WorkQueueing
    private var turns: SceneThumbnailTurns

    /// - Parameter turns: keeps count of whose picture was taken when.
    init(capturer: SceneThumbnailCapturing, queue: WorkQueueing, turns: SceneThumbnailTurns) {
        self.capturer = capturer
        self.queue = queue
        self.turns = turns
    }

    /// Takes the picture of whichever scene is most out of date, then
    /// carries straight on while any scene still has none.
    func takeNext() {
        let ids = Set(scenes.map(\.id))
        turns.keep(only: ids)
        // Only when one has really gone, so an idle refresh redraws nothing.
        if sceneThumbnails.keys.contains(where: { !ids.contains($0) }) {
            sceneThumbnails = sceneThumbnails.filter { ids.contains($0.key) }
        }
        guard showsSceneThumbnails, let scene = turns.next(among: scenes) else { return }
        let queue = self.queue
        _ = capturer.captureThumbnail(of: scene.scene) { [weak self] image in
            queue.main { self?.took(image, of: scene) }
        }
    }

    private func took(_ image: CGImage?, of scene: StudioButton) {
        turns.took(scene)
        if let image {
            sceneThumbnails[scene.id] = image
        }
        if turns.isBehind(with: scenes) {
            takeNext()
        }
    }
}
