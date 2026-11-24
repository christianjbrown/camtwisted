import CamTwistCore
import CoreImage
import Foundation

/// Filters that move or flicker with the time: a shaking picture, a trail
/// of ghosts, and film that is worn and jumpy.
enum MotionEffect {
    enum Name {
        static let earthquake = "Earthquake"
        static let dodgeBullets = "Dodge bullets"
        static let oldMovie = "Old movie"
    }

    enum Key {
        static let speed = "Speed"
        static let grainFrequency = "Grain_Frequency"
        static let grain = "Grain"
        static let verticalLines = "Vertical_Lines"
        static let minEV = "Min_EV_Distortion"
        static let maxEV = "Max_EV_Distortion"
        static let sepia = "Sepia_Intensity"
    }

    private enum Range {
        static let quakeSpeed: ClosedRange<Double> = 0.15...0.5
        static let grainFrequency: ClosedRange<Double> = 0...0.5
        static let grain: ClosedRange<Double> = 0...100
        static let lines: ClosedRange<Double> = 0...50
        static let ev: ClosedRange<Double> = -3...3
        static let unit: ClosedRange<Double> = 0...1
    }

    private enum Start {
        static let quakeSpeed = 0.25
        static let grainFrequency = 0.08
        static let grain = 25.0
        static let lines = 5.0
        static let minEV = 0.0
        static let maxEV = 1.0
        static let sepia = 1.0
    }

    private enum Controls {
        static let quakeSpeed = NumberControl(
            key: Key.speed, displayName: "Speed", start: Start.quakeSpeed, range: Range.quakeSpeed
        )
        static let grainFrequency = NumberControl(
            key: Key.grainFrequency, displayName: "Grain Frequency", start: Start.grainFrequency,
            range: Range.grainFrequency
        )
        static let grain = NumberControl(key: Key.grain, displayName: "Grain", start: Start.grain, range: Range.grain)
        static let lines = NumberControl(
            key: Key.verticalLines, displayName: "Vertical Lines", start: Start.lines, range: Range.lines
        )
        static let minEV = NumberControl(
            key: Key.minEV, displayName: "Min EV Distortion", start: Start.minEV, range: Range.ev
        )
        static let maxEV = NumberControl(
            key: Key.maxEV, displayName: "Max EV Distortion", start: Start.maxEV, range: Range.ev
        )
        static let sepia = NumberControl(
            key: Key.sepia, displayName: "Sepia Intensity", start: Start.sepia, range: Range.unit
        )
    }

    private enum Tuning {
        /// How far the quake moves the picture, as a share of its width.
        static let quakeShare = 0.012
        /// The waves the quake is made of, each as how fast it runs compared
        /// with the first, where it starts, and how hard it is. Some move
        /// the picture sideways and some up and down.
        typealias Wave = (rate: Double, start: Double, strength: Double)
        static let quakeAcross: [Wave] = [(1, 0, 1), (2.3, 1, 0.5)]
        static let quakeUp: [Wave] = [(1.7, 2, 0.8), (3.1, 0.5, 0.4)]
        /// How many ghosts trail the picture, how far each is magnified and
        /// turned more than the last, and how much of each shows through.
        static let ghosts = 6
        static let ghostMagnify = 0.012
        static let ghostTurnDegrees = 0.6
        static let ghostOpacity = 0.35
        static let ghostSweepRate = 0.8
        /// The picture over its ghosts is a little see-through, so they show.
        static let ghostFront = 0.55
        /// Film frames a second, and how long a scratch stays where it is.
        static let filmRate = 12.0
        static let scratchFrames = 4
        /// How far each stop of flicker darkens the film.
        static let flickerShare = 0.25
        /// Grain size in points for each step of the grain frequency, and
        /// the opacity of the grain at its fullest.
        static let grainCellPerStep = 12.0
        static let grainOpacity = 0.1
        static let grainWander = 1000.0
        static let scratchWidthShare = 0.002
        static let scratchOpacity = 0.7
        static let vignetteIntensity = 1.2
        static let vignetteRadius = 1.5
        static let seedStride: UInt32 = 2_654_435_761
    }

    private static func faded(_ image: CIImage, to opacity: Double) -> CIImage {
        image.applyingFilter(CIFilterName.colorMatrix, parameters: [
            CIInputKey.redVector: CIVector(x: 1, y: 0, z: 0, w: 0),
            CIInputKey.greenVector: CIVector(x: 0, y: 1, z: 0, w: 0),
            CIInputKey.blueVector: CIVector(x: 0, y: 0, z: 1, w: 0),
            CIInputKey.alphaVector: CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)),
        ])
    }

    private static func unit(_ random: inout XorShiftRandom) -> Double {
        Double(random.next()) / Double(UInt32.max)
    }

    private static func effect(
        _ name: String, _ controls: [EffectParameter], _ recipe: @escaping RecipeEffect.Recipe
    ) -> NativeEffect {
        NativeEffect(name: name, kind: .filter, parameters: controls) { RecipeEffect(canvas: $0, recipe: recipe) }
    }

    /// The picture magnified and turned about its middle.
    private static func moved(_ image: CIImage, magnify: Double, degrees: Double, canvas: CGSize) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: canvas.width / 2, y: canvas.height / 2)
            .rotated(by: degrees * .pi / 180).scaledBy(x: 1 + magnify, y: 1 + magnify)
            .translatedBy(x: -canvas.width / 2, y: -canvas.height / 2))
    }

    static let all: [NativeEffect] = [
        effect(Name.earthquake, [Controls.quakeSpeed.parameter]) { image, values, canvas, time in
            // The shaking runs once in each period, from a few waves of
            // different lengths, so it never looks regular.
            let phase = time / max(Controls.quakeSpeed.value(in: values), Range.quakeSpeed.lowerBound) * 2 * .pi
            let reach = canvas.width * Tuning.quakeShare
            func swing(_ waves: [Tuning.Wave]) -> CGFloat {
                CGFloat(waves.reduce(0) { $0 + $1.strength * sin(phase * $1.rate + $1.start) }) * reach
            }
            let shake = CGPoint(x: swing(Tuning.quakeAcross), y: swing(Tuning.quakeUp))
            return image.clampedToExtent().transformed(by: CGAffineTransform(translationX: shake.x, y: shake.y))
        },
        effect(Name.dodgeBullets, []) { image, _, canvas, time in
            // The moment held while the viewpoint sweeps past it, as a ghost
            // for every step of the sweep.
            let sweep = sin(time * Tuning.ghostSweepRate)
            let base = image.clampedToExtent()
            var stack = base
            for step in (1...Tuning.ghosts).reversed() {
                let ghost = moved(
                    base, magnify: Tuning.ghostMagnify * Double(step),
                    degrees: Tuning.ghostTurnDegrees * Double(step) * sweep, canvas: canvas
                )
                stack = faded(ghost, to: Tuning.ghostOpacity).composited(over: stack)
            }
            return faded(base, to: Tuning.ghostFront).composited(over: stack)
        },
        effect(Name.oldMovie, [
            Controls.grainFrequency.parameter, Controls.grain.parameter, Controls.lines.parameter,
            Controls.minEV.parameter, Controls.maxEV.parameter, Controls.sepia.parameter,
        ]) { image, values, canvas, time in
            let frame = Int(time * Tuning.filmRate)
            var random = XorShiftRandom(seed: UInt32(truncatingIfNeeded: frame + 1) &* Tuning.seedStride)
            let minimum = Controls.minEV.value(in: values), maximum = Controls.maxEV.value(in: values)
            let stops = -(minimum + (maximum - minimum) * unit(&random)) * Tuning.flickerShare
            let bounds = CGRect(origin: .zero, size: canvas)
            let toned = image.clampedToExtent()
                .applyingFilter(CIFilterName.sepia, parameters: [kCIInputIntensityKey: Controls.sepia.value(in: values)])
                .applyingFilter(CIFilterName.exposureAdjust, parameters: [kCIInputEVKey: stops])
                .applyingFilter(CIFilterName.vignette, parameters: [
                    kCIInputIntensityKey: Tuning.vignetteIntensity, kCIInputRadiusKey: Tuning.vignetteRadius,
                ])
                .cropped(to: bounds)
            let wander = CGPoint(x: unit(&random) * Tuning.grainWander, y: unit(&random) * Tuning.grainWander)
            let cell = 1 + CGFloat(Controls.grainFrequency.value(in: values) * Tuning.grainCellPerStep)
            let grain = faded(
                NoiseField.image(canvas: canvas, cell: cell, offset: wander),
                to: Controls.grain.value(in: values) / Range.grain.upperBound * Tuning.grainOpacity
            ).composited(over: toned)
            // Scratches stay put for a few frames, then jump.
            var scratchRandom = XorShiftRandom(
                seed: UInt32(truncatingIfNeeded: frame / Tuning.scratchFrames + 1) &* Tuning.seedStride
            )
            let scratch = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: Tuning.scratchOpacity))
            return (0..<Int(Controls.lines.value(in: values))).reduce(grain) { picture, _ in
                let x = canvas.width * CGFloat(unit(&scratchRandom))
                return scratch.cropped(to: CGRect(
                    x: x, y: 0, width: max(canvas.width * Tuning.scratchWidthShare, 1), height: canvas.height
                )).composited(over: picture)
            }
        },
    ]
}

public extension NativeEffect {
    /// A shaking picture, a trail of ghosts and worn film.
    static var motionFilters: [NativeEffect] { MotionEffect.all }
}
