import CamTwistCore
import CoreGraphics
import Foundation

/// Takes small pictures of scenes, whether or not they are on air.
public protocol SceneThumbnailCapturing: AnyObject {
    /// Asks for a picture of a scene. False when one is being taken
    /// already; otherwise the picture, or nil, comes back on any queue.
    func captureThumbnail(of scene: SceneConfiguration, completion: @escaping (CGImage?) -> Void) -> Bool
}

/// Decides which scene's picture to take next, so that every scene has one
/// and each is taken again in its turn.
struct SceneThumbnailTurns {
    /// What each scene looked like when its picture was last taken, and
    /// how long ago that was, counted in pictures.
    private var taken: [UUID: (scene: SceneConfiguration, turn: Int)] = [:]
    private var turn = 0

    /// The scene whose picture is most out of date: one with none or one
    /// that has changed comes first, then whichever was taken longest ago.
    func next(among scenes: [StudioButton]) -> StudioButton? {
        if let fresh = scenes.first(where: { taken[$0.id]?.scene != $0.scene }) {
            return fresh
        }
        // Every scene has had its picture taken by now: the oldest goes again.
        return scenes.compactMap { scene in taken[scene.id].map { (scene, $0.turn) } }
            .min { $0.1 < $1.1 }?.0
    }

    /// Whether some scene still has no picture of how it looks now.
    func isBehind(with scenes: [StudioButton]) -> Bool {
        scenes.contains { taken[$0.id]?.scene != $0.scene }
    }

    mutating func took(_ scene: StudioButton) {
        turn += 1
        taken[scene.id] = (scene.scene, turn)
    }

    /// Forgets scenes that are no longer there.
    mutating func keep(only ids: Set<UUID>) {
        taken = taken.filter { ids.contains($0.key) }
    }
}
