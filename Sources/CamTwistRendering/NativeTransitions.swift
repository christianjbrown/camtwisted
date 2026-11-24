import CamTwistCore
import CoreImage
import Foundation

/// A transition that is a function of the two pictures and how far along it is.
final class RecipeTransition: TransitionEffect {
    typealias Recipe = (_ from: CIImage, _ to: CIImage, _ progress: Double, _ canvas: CGSize) -> CIImage

    private let canvas: CGSize
    private let recipe: Recipe

    init(canvas: CGSize, recipe: @escaping Recipe) {
        self.canvas = canvas
        self.recipe = recipe
    }

    func blend(from: CIImage, to: CIImage, progress: Double, time: TimeInterval) -> CIImage {
        let bounds = CGRect(origin: .zero, size: canvas)
        // Filters leave a trace of themselves at either end, such as the
        // corner of a curl, so the ends are the pictures themselves.
        if progress <= 0 { return from.cropped(to: bounds) }
        if progress >= 1 { return to.cropped(to: bounds) }
        return recipe(from, to, progress, canvas).cropped(to: bounds)
    }
}

/// The transitions the app comes with, made from Core Image's own filters.
enum NativeTransitions {
    enum Name {
        static let dip = "Dip"
        static let flash = "Flash"
        static let mod = "Mod"
        static let pageCurl = "PageCurl"
        static let swipe = "Swipe"
        static let copyMachine = "CopyMachine"
        static let ripple = "Ripple"
    }

    /// Sizes given as shares of the picture's width.
    private enum Share {
        static let swipeEdge = 0.15
        static let copyBar = 0.08
        static let curlRadius = 0.12
        static let modRadius = 0.12
        static let modCompression = 0.25
        static let rippleWidth = 0.1
        static let rippleScale = 0.04
    }

    private enum Tuning {
        /// The half way point, where the dip is blackest.
        static let dipMiddle = 0.5
        /// The curl lifts from the bottom left corner towards the top right.
        static let curlAngle = Double.pi / 4
        static let swipeAngle = 0.0
        static let copyAngle = 0.0
        static let copyOpacity = 1.3
        static let copyColor = CIColor(red: 0.65, green: 0.99, blue: 0.84)
        static let flashColor = CIColor(red: 1, green: 0.85, blue: 0.65)
        static let swipeColor = CIColor(red: 1, green: 1, blue: 1)
        static let white = CIColor(red: 1, green: 1, blue: 1)
        static let black = CIColor(red: 0, green: 0, blue: 0)
        /// A circle smaller than this is not worth drawing.
        static let smallestRadius = 1.0
    }

    /// White inside a circle, fading to black over `edge` points at its rim.
    private static func disc(centre: CIVector, radius: Double, edge: Double, bounds: CGRect) -> CIImage {
        let outer = max(radius, Tuning.smallestRadius)
        return FilterOutput.image(named: CIFilterName.radialGradient, parameters: [
            kCIInputCenterKey: centre,
            CIInputKey.radius0: max(outer - edge, 0),
            CIInputKey.radius1: outer,
            CIInputKey.color0: Tuning.white,
            CIInputKey.color1: Tuning.black,
        ], fallback: CIImage(color: Tuning.black)).cropped(to: bounds)
    }

    /// The new picture spreads from the middle as a ring, which bends the
    /// pictures it passes over like a ripple on water.
    private static func ripple(_ from: CIImage, _ to: CIImage, _ progress: Double, _ canvas: CGSize) -> CIImage {
        let bounds = CGRect(origin: .zero, size: canvas)
        let centre = middle(of: canvas)
        let edge = Share.rippleWidth * canvas.width
        let reach = Double(hypot(canvas.width, canvas.height) / 2) + 2 * edge
        let radius = progress * reach
        let revealed = to.applyingFilter(CIFilterName.blendWithMask, parameters: [
            kCIInputBackgroundImageKey: from,
            kCIInputMaskImageKey: disc(centre: centre, radius: radius, edge: edge, bounds: bounds),
        ])
        // The band between a slightly larger and a slightly smaller disc is
        // the ring itself.
        let ring = disc(centre: centre, radius: radius + edge, edge: edge, bounds: bounds)
            .applyingFilter(CIFilterName.differenceBlend, parameters: [
                kCIInputBackgroundImageKey: disc(centre: centre, radius: radius - edge, edge: edge, bounds: bounds),
            ])
        return revealed.clampedToExtent().applyingFilter(CIFilterName.displacementDistortion, parameters: [
            CIInputKey.displacementImage: ring,
            kCIInputScaleKey: Share.rippleScale * canvas.width,
        ])
    }

    private static func middle(of canvas: CGSize) -> CIVector {
        CIVector(x: canvas.width / 2, y: canvas.height / 2)
    }

    private static func extent(of canvas: CGSize) -> CIVector {
        CIVector(cgRect: CGRect(origin: .zero, size: canvas))
    }

    private static func filtered(
        _ name: String, _ from: CIImage, _ to: CIImage, _ progress: Double, _ parameters: [String: Any]
    ) -> CIImage {
        var all = parameters
        all[kCIInputTargetImageKey] = to
        all[kCIInputTimeKey] = progress
        return from.applyingFilter(name, parameters: all)
    }

    private static func dip(_ from: CIImage, _ to: CIImage, _ progress: Double, _: CGSize) -> CIImage {
        let black = CIImage(color: .black).cropped(to: from.extent)
        if progress < Tuning.dipMiddle {
            return filtered(CIFilterName.dissolveTransition, from, black, progress / Tuning.dipMiddle, [:])
        }
        return filtered(
            CIFilterName.dissolveTransition, black, to, (progress - Tuning.dipMiddle) / Tuning.dipMiddle, [:]
        )
    }

    private static func recipe(_ name: String, _ make: @escaping RecipeTransition.Recipe) -> NativeTransition {
        NativeTransition(name: name) { RecipeTransition(canvas: $0, recipe: make) }
    }

    static let all: [NativeTransition] = [
        recipe(Name.dip, dip),
        recipe(Name.flash) { from, to, progress, canvas in
            filtered(CIFilterName.flashTransition, from, to, progress, [
                kCIInputCenterKey: middle(of: canvas),
                kCIInputExtentKey: extent(of: canvas),
                kCIInputColorKey: Tuning.flashColor,
            ])
        },
        recipe(Name.mod) { from, to, progress, canvas in
            filtered(CIFilterName.modTransition, from, to, progress, [
                kCIInputCenterKey: middle(of: canvas),
                kCIInputRadiusKey: Share.modRadius * canvas.width,
                CIInputKey.compression: Share.modCompression * canvas.width,
            ])
        },
        recipe(Name.pageCurl) { from, to, progress, canvas in
            filtered(CIFilterName.pageCurlTransition, from, to, progress, [
                kCIInputExtentKey: extent(of: canvas),
                kCIInputAngleKey: Tuning.curlAngle,
                kCIInputRadiusKey: Share.curlRadius * canvas.width,
            ])
        },
        recipe(Name.swipe) { from, to, progress, canvas in
            filtered(CIFilterName.swipeTransition, from, to, progress, [
                kCIInputExtentKey: extent(of: canvas),
                kCIInputColorKey: Tuning.swipeColor,
                kCIInputAngleKey: Tuning.swipeAngle,
                kCIInputWidthKey: Share.swipeEdge * canvas.width,
                CIInputKey.opacity: 0,
            ])
        },
        recipe(Name.copyMachine) { from, to, progress, canvas in
            filtered(CIFilterName.copyMachineTransition, from, to, progress, [
                kCIInputExtentKey: extent(of: canvas),
                kCIInputColorKey: Tuning.copyColor,
                kCIInputAngleKey: Tuning.copyAngle,
                kCIInputWidthKey: Share.copyBar * canvas.width,
                CIInputKey.opacity: Tuning.copyOpacity,
            ])
        },
        recipe(Name.ripple, ripple),
    ]
}

/// A transition built into the app.
struct NativeTransition {
    let name: String
    let make: (CGSize) -> TransitionEffect
}

/// The built-in transitions, presented like any other effect library so
/// they are listed with the rest.
public final class NativeTransitionLibrary: EffectLibrary, ImageEffectFactory, TransitionFactory {
    public let directory: URL
    private let transitions: [NativeTransition]

    public init(directory: URL) {
        self.directory = directory
        transitions = [NativeTransition(name: DissolveTransition.name) { _ in DissolveTransition() }]
            + NativeTransitions.all
    }

    public func availableEffects() -> [EffectListing] {
        transitions.map { EffectListing(name: $0.name, kind: .transition) }
    }

    /// Transitions have no controls: how far along they are is all they take.
    public func parameters(forEffectNamed name: String) -> [EffectParameter] { [] }

    /// Transitions are not effects, so there is never one to make.
    public func makeEffect(named name: String, canvas: CGSize) -> ImageEffect? { nil }

    public func makeTransition(named name: String, canvas: CGSize) -> TransitionEffect? {
        transitions.first { $0.name == name }?.make(canvas)
    }
}
