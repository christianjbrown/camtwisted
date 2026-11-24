import CamTwistCore
import CoreGraphics
import CoreImage
import Foundation

/// Overlays drawn over the picture that move with the time: snow falling
/// and searchlights sweeping.
enum SkyEffect {
    enum Name {
        static let snowfall = "Snowfall"
        static let searchlights = "Searchlights"
    }

    enum Key {
        static let speed = "Speed"
        static let flakes = "Num_Flakes"
        static let batSignal = "Batman"
    }

    private enum Range {
        static let speed: ClosedRange<Double> = 1...50
        static let flakes: ClosedRange<Double> = 1...100
    }

    private enum Start {
        static let speed = 20.0
        static let flakes = 50.0
    }

    private static let speed = NumberControl(key: Key.speed, displayName: "Speed", start: Start.speed, range: Range.speed)
    private static let flakes = NumberControl(
        key: Key.flakes, displayName: "Num Flakes", start: Start.flakes, range: Range.flakes
    )
    private static let batSignal = SwitchControl(key: Key.batSignal, displayName: "Bat signal")

    private enum Snow {
        /// Picture heights a flake falls each second for each step of speed.
        static let heightsPerStep = 0.01
        /// The pace of the farthest flake, as a share of the full pace; nearer flakes add to it.
        static let basePace = 0.5
        static let smallestFlake = 0.004
        static let largestFlake = 0.018
        static let sway = 0.02
        static let swayRate = 0.8
        static let spinRate = 0.5
        static let arms = 6
        static let armWidthShare: CGFloat = 0.14
        static let opacity: CGFloat = 0.85
        /// The arms of a flake each have a short twig, this far along the
        /// arm and this long as a share of the arm.
        static let twigAt: CGFloat = 0.6
        static let twigLength: CGFloat = 0.3
        static let twigAngle: CGFloat = .pi / 4
        static let seedStride: UInt32 = 2_246_822_519
    }

    /// What is different about one flake from the next, worked out from its
    /// number alone so it is the same on every frame.
    private struct Flake {
        let across: CGFloat
        let start: Double
        let pace: Double
        let size: CGFloat
        let phase: Double

        init(index: Int) {
            var random = XorShiftRandom(seed: UInt32(truncatingIfNeeded: index + 1) &* Snow.seedStride)
            func unit() -> Double { Double(random.next()) / Double(UInt32.max) }
            across = CGFloat(unit())
            start = unit()
            // Nearer flakes are bigger and fall faster.
            let nearness = unit()
            pace = Snow.basePace + nearness
            size = CGFloat(Snow.smallestFlake + (Snow.largestFlake - Snow.smallestFlake) * nearness)
            phase = unit() * 2 * .pi
        }
    }

    private static func draw(radius: CGFloat, at centre: CGPoint, spin: Double, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: centre.x, y: centre.y)
        context.rotate(by: CGFloat(spin))
        context.setStrokeColor(CGColor(gray: 1, alpha: Snow.opacity))
        context.setLineWidth(max(radius * Snow.armWidthShare, 1))
        context.setLineCap(.round)
        for arm in 0..<Snow.arms {
            context.saveGState()
            context.rotate(by: CGFloat(arm) * 2 * .pi / CGFloat(Snow.arms))
            let twig = radius * Snow.twigAt
            let side = radius * Snow.twigLength
            context.move(to: .zero)
            context.addLine(to: CGPoint(x: radius, y: 0))
            for direction: CGFloat in [-1, 1] {
                context.move(to: CGPoint(x: twig, y: 0))
                context.addLine(to: CGPoint(
                    x: twig + side * cos(Snow.twigAngle), y: direction * side * sin(Snow.twigAngle)
                ))
            }
            context.strokePath()
            context.restoreGState()
        }
        context.restoreGState()
    }

    static let snowfall = NativeEffect(
        name: Name.snowfall, kind: .overlay, parameters: [speed.parameter, flakes.parameter]
    ) { canvas in
        DrawnOverlay(canvas: canvas, animated: true) { values, time, canvas, context in
            let count = Int(flakes.value(in: values).rounded())
            let heights = time * speed.value(in: values) * Snow.heightsPerStep
            for index in 0..<count {
                let flake = Flake(index: index)
                let reach = flake.size * canvas.width
                // A flake falls from just above the picture to just below it.
                let fallen = (flake.start + heights * flake.pace).truncatingRemainder(dividingBy: 1)
                let y = (1 - CGFloat(fallen)) * (canvas.height + reach * 2) - reach
                let x = (flake.across + CGFloat(Snow.sway * sin(time * Snow.swayRate * flake.pace + flake.phase)))
                    * canvas.width
                draw(
                    radius: reach, at: CGPoint(x: x, y: y), spin: time * Snow.spinRate * flake.pace + flake.phase,
                    in: context
                )
            }
        }
    }

    // MARK: Searchlights

    private enum Beams {
        /// How wide the lamp is at the ground, and the pool of light where
        /// the beam ends, as shares of the picture's width.
        static let lampHalfWidth: CGFloat = 0.03
        static let poolRadius: CGFloat = 0.12
        static let batPoolRadius: CGFloat = 0.2
        static let beamStrongest: CGFloat = 0.6
        /// A beam is a few beams laid over each other, each narrower than
        /// the last, so its edges are soft.
        static let beamLayers = 6
        static let beamFaintest: CGFloat = 0.12
        static let poolStrongest: CGFloat = 0.7
        /// Where each lamp stands, as a share of the width along the bottom,
        /// and where its beam wanders to: the middle, how far it roams, how
        /// fast, and where in its sweep each lamp begins.
        static let lamps: [CGFloat] = [0.08, 0.92]
        static let aimHeight: CGFloat = 0.6
        static let roamAcross: CGFloat = 0.25
        static let roamUp: CGFloat = 0.15
        static let roamRate = 0.7
        static let roamRateUp = 0.9
        static let lampOffset = 2.1
        /// Where the beams meet when they make the bat signal, as a share of the height.
        static let batHeight: CGFloat = 0.62
        static let batSpan: CGFloat = 0.55
        static let batOpacity: CGFloat = 0.85
        /// The bat's outline, in units where its wings reach one either side.
        static let bat: [CGPoint] = [
            (-1, 0.15), (-0.75, 0.35), (-0.5, 0.25), (-0.3, 0.35), (-0.15, 0.2), (-0.1, 0.45), (0, 0.3),
            (0.1, 0.45), (0.15, 0.2), (0.3, 0.35), (0.5, 0.25), (0.75, 0.35), (1, 0.15), (0.8, -0.1),
            (0.55, -0.05), (0.3, -0.3), (0.12, -0.12), (0, -0.25), (-0.12, -0.12), (-0.3, -0.3),
            (-0.55, -0.05), (-0.8, -0.1),
        ].map { CGPoint(x: $0.0, y: $0.1) }
    }

    /// Runs a drawing step with a gradient through the colours.
    private static func withGradient(_ colours: [CGColor], _ draw: (CGGradient) -> Void) {
        if let made = CGGradient(colorsSpace: SRGBColorSpace.shared, colors: colours as CFArray, locations: nil) {
            draw(made)
        }
    }

    /// One beam from a lamp on the ground to where it lights the sky.
    private static func beam(from lamp: CGPoint, to target: CGPoint, canvas: CGSize, in context: CGContext) {
        let reach = hypot(target.x - lamp.x, target.y - lamp.y)
        let sideways = CGPoint(x: -(target.y - lamp.y) / reach, y: (target.x - lamp.x) / reach)
        for layer in 1...Beams.beamLayers {
            let narrowing = CGFloat(layer) / CGFloat(Beams.beamLayers)
            let lampSide = Beams.lampHalfWidth * canvas.width * narrowing
            let poolSide = Beams.poolRadius * canvas.width * narrowing
            let share = 1 / CGFloat(Beams.beamLayers)
            context.saveGState()
            context.addLines(between: [
                CGPoint(x: lamp.x + sideways.x * lampSide, y: lamp.y + sideways.y * lampSide),
                CGPoint(x: target.x + sideways.x * poolSide, y: target.y + sideways.y * poolSide),
                CGPoint(x: target.x - sideways.x * poolSide, y: target.y - sideways.y * poolSide),
                CGPoint(x: lamp.x - sideways.x * lampSide, y: lamp.y - sideways.y * lampSide),
            ])
            context.clip()
            withGradient([
                CGColor(gray: 1, alpha: Beams.beamStrongest * share), CGColor(gray: 1, alpha: Beams.beamFaintest * share),
            ]) {
                context.drawLinearGradient($0, start: lamp, end: target, options: [])
            }
            context.restoreGState()
        }
    }

    private static func pool(at target: CGPoint, radius: CGFloat, in context: CGContext) {
        withGradient([CGColor(gray: 1, alpha: Beams.poolStrongest), CGColor(gray: 1, alpha: 0)]) {
            context.drawRadialGradient(
                $0, startCenter: target, startRadius: 0, endCenter: target, endRadius: radius, options: []
            )
        }
    }

    static let searchlights = NativeEffect(
        name: Name.searchlights, kind: .overlay, parameters: [batSignal.parameter]
    ) { canvas in
        DrawnOverlay(canvas: canvas, animated: true) { values, time, canvas, context in
            let signal = batSignal.isOn(in: values)
            let poolRadius = (signal ? Beams.batPoolRadius : Beams.poolRadius) * canvas.width
            for (index, lampAt) in Beams.lamps.enumerated() {
                let lamp = CGPoint(x: lampAt * canvas.width, y: 0)
                let wander = time + Double(index) * Beams.lampOffset
                // The lamps roam the sky, or both aim at the same place in the clouds.
                let target = signal
                    ? CGPoint(x: canvas.width / 2, y: Beams.batHeight * canvas.height)
                    : CGPoint(
                        x: canvas.width / 2 + Beams.roamAcross * canvas.width * CGFloat(sin(wander * Beams.roamRate)),
                        y: (Beams.aimHeight + Beams.roamUp * CGFloat(sin(wander * Beams.roamRateUp))) * canvas.height
                    )
                beam(from: lamp, to: target, canvas: canvas, in: context)
                pool(at: target, radius: poolRadius, in: context)
            }
            if signal {
                let centre = CGPoint(x: canvas.width / 2, y: Beams.batHeight * canvas.height)
                let span = Beams.batSpan * poolRadius
                context.setFillColor(CGColor(gray: 0, alpha: Beams.batOpacity))
                context.addLines(between: Beams.bat.map {
                    CGPoint(x: centre.x + $0.x * span, y: centre.y + $0.y * span)
                })
                context.fillPath()
            }
        }
    }
}

public extension NativeEffect {
    /// Falling snow, and searchlights.
    static var skyEffects: [NativeEffect] { [SkyEffect.snowfall, SkyEffect.searchlights] }
}
