import CamTwistCore
import CoreImage
import Foundation

/// Fire that rises from the edges in the picture, the way xflame burns.
public final class FlameEffect: ImageEffect {
    public static let name = "Flame"
    public static let flaresKey = "Flares"

    /// The fire is simulated on a grid this many times smaller than the
    /// picture, which is also what gives it its soft look.
    private static let gridDivisor: CGFloat = 4

    private let canvas: CGSize
    private let pixels: PixelAccess
    private let gridWidth: Int
    private let gridHeight: Int
    private var simulation: FlameSimulation
    private var random: XorShiftRandom
    private var flares = false

    public init(canvas: CGSize, pixels: PixelAccess, seed: UInt32) {
        self.canvas = canvas
        self.pixels = pixels
        gridWidth = max(Int(canvas.width / Self.gridDivisor), 1)
        gridHeight = max(Int(canvas.height / Self.gridDivisor), 1)
        simulation = FlameSimulation(width: gridWidth, height: gridHeight)
        random = XorShiftRandom(seed: seed)
    }

    public static let parameters = [
        EffectParameter(key: flaresKey, displayName: "Flares", kind: .boolean, defaultValue: .boolean(false)),
    ]

    public func setValues(_ values: [String: EffectValue]) {
        let wanted = values[Self.flaresKey] == .boolean(true)
        guard wanted != flares else { return }
        flares = wanted
        // The spread settings live in the simulation, so a change starts a fresh fire.
        simulation = FlameSimulation(
            width: gridWidth, height: gridHeight, settings: FlameSettings(flares: wanted)
        )
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        let small = pixels.rgba(of: image, width: gridWidth, height: gridHeight)
        let brightness = ImageAnalysis.luminance(rgba: small, width: gridWidth, height: gridHeight)
        simulation.step(fuel: ImageAnalysis.edges(of: brightness), random: &random)
        let fire = pixels.image(rgba: FlamePalette.picture(of: simulation), width: gridWidth, height: gridHeight)
        return fire.stretched(to: canvas, smooth: true).composited(over: image)
    }
}
