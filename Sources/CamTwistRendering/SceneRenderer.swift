import CamTwistCore
import CoreImage
import Foundation

/// Makes the effect objects a scene runs.
public protocol ImageEffectFactory {
    func makeEffect(named name: String, canvas: CGSize) -> ImageEffect?
}

/// Turns a scene into a picture. Keeps the scene's effect objects alive
/// between frames, since effects carry state such as running animations.
public final class SceneRenderer {
    private let sources: SourceFrameSupplying
    private let effectFactory: ImageEffectFactory
    private let compositor: Compositor
    private let cutter: SourceCutting
    private var effects: [UUID: ImageEffect] = [:]
    /// When each animated source was first drawn, so its animations run
    /// from the moment it appears rather than from when the app started.
    private var animationStarts: [UUID: TimeInterval] = [:]

    public convenience init(
        sources: SourceFrameSupplying, effectFactory: ImageEffectFactory, canvas: CGSize, supplies: RenderingSupplies
    ) {
        self.init(
            sources: sources, effectFactory: effectFactory, canvas: canvas,
            cutter: SourceCutter(masker: supplies.makeMasker())
        )
    }

    init(sources: SourceFrameSupplying, effectFactory: ImageEffectFactory, canvas: CGSize, cutter: SourceCutting) {
        self.sources = sources
        self.effectFactory = effectFactory
        self.cutter = cutter
        compositor = Compositor(canvas: canvas)
    }

    public func render(_ scene: SceneConfiguration, time: TimeInterval) -> CIImage {
        let wanted = Set(scene.allItems.map(\.id))
        effects = effects.filter { wanted.contains($0.key) }
        cutter.keepOnly(wanted)
        // A source that is switched off, or gone, starts its animations
        // afresh when it comes back.
        let showing = Set(scene.sourcesInUse.keys)
        animationStarts = animationStarts.filter { showing.contains($0.key) }
        return compositor.compose(layers(for: scene.items, hearing: [:], time: time), time: time)
    }

    /// Resolves a list of steps into what each draws. A source with a
    /// branch is drawn with its branch first, as a picture of its own, and
    /// only then takes its place in this list.
    ///
    /// - Parameter hearing: the sources an effect at the top of the list
    ///   hears, by step, with how loud each is. Every source with sound
    ///   joins them for the effects below it.
    private func layers(for items: [ChainItem], hearing: [UUID: Double], time: TimeInterval) -> [CompositorLayer] {
        var above = hearing
        return items.filter(\.isEnabled).compactMap { item in
            switch item.content {
            case .source:
                defer { above[item.id] = SceneSound.level(of: item) }
                return .picture(
                    picture(of: item, time: time), placement: placement(of: item, time: time), fit: item.fit ?? .fill
                )
            case .effect(let name, let values):
                if effects[item.id] == nil {
                    effects[item.id] = effectFactory.makeEffect(named: name, canvas: compositor.canvas)
                }
                guard let effect = effects[item.id] else { return nil }
                effect.setValues(values)
                (effect as? HearsSourcesAbove)?.hear(HeardSources(levels: above))
                return .effect(effect)
            case .script:
                // Scripts act when switched on; they draw nothing.
                return nil
            }
        }
    }

    /// A source's picture: its own frame, cut out and adjusted, or,
    /// when it has a branch, that picture filling a canvas with the
    /// branch's steps applied on top.
    private func picture(of item: ChainItem, time: TimeInterval) -> CIImage? {
        let frame = sources.latestFrame(for: item.id).map { raw in
            // What is cut out goes first, from the picture as it arrived.
            let cut = item.cutout.map { cutter.cut(raw, by: $0, forSource: item.id) }
            return SourceLook.apply(item.adjustments, to: cut ?? raw)
        }
        guard let branch = item.branch, !branch.isEmpty else { return frame }
        let base = CompositorLayer.picture(frame, placement: nil)
        // Over nothing, not over black: a source with clear parts, such as a
        // telestrator or text, keeps them clear with a branch too.
        // A branch's effects hear the source the branch belongs to.
        let own = SceneSound.level(of: item).map { [item.id: $0] } ?? [:]
        return compositor.composeClear([base] + layers(for: branch, hearing: own, time: time), time: time)
    }

    /// Where a source sits right now, with its animations run on from the
    /// moment it first appeared.
    private func placement(of item: ChainItem, time: TimeInterval) -> PictureInPictureSettings? {
        guard let placement = item.pictureInPicture, let animations = item.animations, !animations.isEmpty else {
            return item.pictureInPicture
        }
        let start = animationStarts[item.id, default: time]
        animationStarts[item.id] = start
        return placement.animated(by: animations, elapsed: time - start)
    }
}
