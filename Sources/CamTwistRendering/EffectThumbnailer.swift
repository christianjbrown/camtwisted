import CamTwistCore
import CoreImage
import Foundation

/// Makes a small picture of what an effect does, for the effect picker.
public final class EffectThumbnailer {
    private enum Tuning {
        /// Frames run before the picture is taken, so effects that build up
        /// over time (fire, rain, feedback) have something to show.
        static let warmUpFrames = 24
        /// How far through a transition its picture is taken.
        static let transitionProgress = 0.5
        static let otherSceneFilter = CIFilterName.colorInvert
    }

    private let factory: ImageEffectFactory
    private let transitions: TransitionFactory
    private let size: CGSize
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let sample: CIImage
    /// How many frames a second the clock the effect runs on ticks at.
    private let framesPerSecond: Double

    public init(
        factory: ImageEffectFactory, transitions: TransitionFactory, size: CGSize,
        framesPerSecond: Double = Pacing.usual.thumbnailFramesPerSecond
    ) {
        self.framesPerSecond = framesPerSecond
        self.factory = factory
        self.transitions = transitions
        self.size = size
        sample = Self.sampleScene(size: size)
    }

    /// The sample scene after the effect has run on it, or nil when the
    /// effect cannot be made.
    public func thumbnail(forEffectNamed name: String) -> CGImage? {
        guard let effect = factory.makeEffect(named: name, canvas: size) else { return nil }
        // The sample figure has no face to find, so an effect that follows
        // one is shown where its head is.
        (effect as? FacePosable)?.rest(at: Self.sampleFace(size: size))
        // Nor does it say anything, so captions show sample words.
        (effect as? SamplePreviewing)?.showSample()
        let bounds = CGRect(origin: .zero, size: size)
        var output = sample
        for frame in 0..<Tuning.warmUpFrames {
            output = effect.apply(to: sample, time: Double(frame) / framesPerSecond)
            // Rendering each frame keeps Core Image from stacking the whole
            // history into one enormous picture recipe.
            _ = context.createCGImage(output.cropped(to: bounds), from: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return context.createCGImage(output.cropped(to: bounds), from: bounds)
    }

    /// A transition caught half way from the sample scene to a second,
    /// plainly different one, or nil when there is no such transition.
    public func thumbnail(forTransitionNamed name: String) -> CGImage? {
        guard let transition = transitions.makeTransition(named: name, canvas: size) else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        // The second scene is the first seen in a mirror with its colours turned over.
        let other = sample
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -size.width, y: 0))
            .applyingFilter(Tuning.otherSceneFilter)
        var output = sample
        for frame in 0...Tuning.warmUpFrames {
            let progress = Tuning.transitionProgress * Double(frame) / Double(Tuning.warmUpFrames)
            output = transition.blend(
                from: sample, to: other, progress: progress, time: Double(frame) / framesPerSecond
            )
            _ = context.createCGImage(output.cropped(to: bounds), from: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return context.createCGImage(output.cropped(to: bounds), from: bounds)
    }

    /// A simple scene with sky, ground and a figure: enough colour and edge
    /// for every kind of effect to show itself.
    static func sampleScene(size: CGSize) -> CIImage {
        let bounds = CGRect(origin: .zero, size: size)
        let sky = FilterOutput.image(named: CIFilterName.linearGradient, parameters: [
            CIInputKey.point0: CIVector(x: 0, y: size.height),
            CIInputKey.color0: Scene.skyTop,
            CIInputKey.point1: CIVector(x: 0, y: size.height * Scene.horizon),
            CIInputKey.color1: Scene.skyHorizon,
        ], fallback: CIImage(color: .blue))
        let ground = CIImage(color: Scene.groundColor)
            .cropped(to: CGRect(x: 0, y: 0, width: size.width, height: size.height * Scene.horizon))
        let body = CIImage(color: Scene.bodyColor).cropped(to: CGRect(
            x: size.width * Scene.bodyLeft, y: 0,
            width: size.width * Scene.bodyWidth, height: size.height * Scene.bodyHeight
        ))
        let sun = disc(
            center: CGPoint(x: size.width * Scene.sunX, y: size.height * Scene.sunY),
            radius: size.height * Scene.sunRadius,
            color: Scene.sunColor
        )
        let head = disc(
            center: CGPoint(x: size.width * (Scene.bodyLeft + Scene.bodyWidth / 2), y: size.height * Scene.headHeight),
            radius: size.height * Scene.headRadius,
            color: Scene.headColor
        )
        return head.composited(over: body).composited(over: ground)
            .composited(over: sun).composited(over: sky).cropped(to: bounds)
    }

    /// The face the sample scene's figure would have, were it drawn.
    static func sampleFace(size: CGSize) -> FaceExpression {
        FaceExpression(
            centre: CGPoint(x: size.width * (Scene.bodyLeft + Scene.bodyWidth / 2), y: size.height * Scene.headHeight),
            height: size.height * Scene.headRadius * 2 * Scene.faceShare
        )
    }

    private enum Scene {
        static let skyTop = CIColor(red: 0.25, green: 0.5, blue: 0.9)
        static let skyHorizon = CIColor(red: 1, green: 0.75, blue: 0.5)
        static let groundColor = CIColor(red: 0.2, green: 0.45, blue: 0.25)
        static let bodyColor = CIColor(red: 0.85, green: 0.3, blue: 0.3)
        static let sunColor = CIColor(red: 1, green: 0.95, blue: 0.6)
        static let headColor = CIColor(red: 0.95, green: 0.8, blue: 0.65)
        /// How far in from a disc's edge its soft rim starts, in points.
        static let rimWidth: CGFloat = 1
        static let horizon: CGFloat = 0.35
        // The figure stands left of centre and the sun is on the right, so
        // effects that flip or mirror have something to show.
        static let sunX: CGFloat = 0.82
        static let sunY: CGFloat = 0.78
        static let sunRadius: CGFloat = 0.09
        static let bodyLeft: CGFloat = 0.24
        static let bodyWidth: CGFloat = 0.24
        static let bodyHeight: CGFloat = 0.5
        static let headHeight: CGFloat = 0.64
        static let headRadius: CGFloat = 0.17
        /// A face, brow to chin, is about this much of a head's height.
        static let faceShare: CGFloat = 0.75
    }

    private static func disc(center: CGPoint, radius: CGFloat, color: CIColor) -> CIImage {
        FilterOutput.image(named: CIFilterName.radialGradient, parameters: [
            CIInputKey.center: CIVector(x: center.x, y: center.y),
            CIInputKey.radius0: radius - Scene.rimWidth,
            CIInputKey.radius1: radius,
            CIInputKey.color0: color,
            CIInputKey.color1: CIColor(red: 0, green: 0, blue: 0, alpha: 0),
        ], fallback: CIImage.empty())
    }
}
