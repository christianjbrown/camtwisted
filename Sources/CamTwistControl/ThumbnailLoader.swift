import CoreGraphics
import Foundation

/// Makes pictures for effects that have none yet, one at a time and off
/// the main thread, handing each over as it finishes.
@MainActor
final class ThumbnailLoader {
    private let thumbnailer: EffectThumbnailing
    private let queue: WorkQueueing
    private let onReady: @MainActor (String, CGImage) -> Void
    private var requested: Set<String> = []

    init(
        thumbnailer: EffectThumbnailing,
        queue: WorkQueueing,
        onReady: @escaping @MainActor (String, CGImage) -> Void
    ) {
        self.thumbnailer = thumbnailer
        self.queue = queue
        self.onReady = onReady
    }

    /// Starts on the named effects and transitions that have not been
    /// asked for before. A transition is pictured half way through.
    func requestMissing(among effects: [String], transitions: [String]) {
        let thumbnailer = self.thumbnailer
        request(effects) { thumbnailer.thumbnail(forEffectNamed: $0) }
        request(transitions) { thumbnailer.thumbnail(forTransitionNamed: $0) }
    }

    private func request(_ names: [String], picture: @escaping (String) -> CGImage?) {
        let missing = names.filter { !requested.contains($0) }
        requested.formUnion(missing)
        let queue = self.queue
        let onReady = self.onReady
        for name in missing {
            queue.background {
                guard let image = picture(name) else { return }
                queue.main { onReady(name, image) }
            }
        }
    }
}
