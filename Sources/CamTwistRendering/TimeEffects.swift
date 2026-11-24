import CamTwistCore
import CoreImage
import Foundation

/// Keeps a picture so it can be shown later.
protocol FrameKeeping {
    /// A copy of the picture that nothing else can change, the size of the canvas.
    func copy(of image: CIImage) -> CIImage
}

/// Copies a picture out into plain bytes, so it can be kept after the
/// camera has reused the buffer it came in.
struct FrameKeeper: FrameKeeping {
    private let pixels: PixelAccess
    private let canvas: CGSize
    private let size: (width: Int, height: Int)

    /// - Parameter widest: the most points across a kept picture has.
    ///   Pictures wider than that are kept smaller, to save memory.
    init(pixels: PixelAccess, canvas: CGSize, widest: CGFloat) {
        self.pixels = pixels
        self.canvas = canvas
        let scale = min(1, widest / canvas.width)
        size = (Int(canvas.width * scale), Int(canvas.height * scale))
    }

    func copy(of image: CIImage) -> CIImage {
        let kept = pixels.image(
            rgba: pixels.rgba(of: image, width: size.width, height: size.height), width: size.width, height: size.height
        )
        return kept.transformed(by: CGAffineTransform(
            scaleX: canvas.width / CGFloat(size.width), y: canvas.height / CGFloat(size.height)
        ))
    }
}

/// Says when a stop motion film takes its next picture.
protocol StopMotionTiming {
    /// Whether a new picture is due at this moment. Saying yes counts as taking it.
    mutating func isDue(at time: TimeInterval) -> Bool
}

extension StopMotionClock: StopMotionTiming {}

/// Shows the picture as a stop motion film does: a few still pictures a
/// second, each held until the next.
public final class StopMotionEffect: ImageEffect {
    public static let name = "Stop Motion"
    public static let rateKey = "Pictures_A_Second"

    private static let rate = NumberControl(key: rateKey, displayName: "Pictures a second", start: 6, range: 1...15)

    public static let parameters = [rate.parameter]

    private let keeper: FrameKeeping
    private let makeClock: (Double) -> StopMotionTiming
    private var picturesPerSecond: Double
    private var clock: StopMotionTiming
    private var held: CIImage?

    /// - Parameter makeClock: makes the clock for a film of so many pictures a second.
    init(keeper: FrameKeeping, makeClock: @escaping (Double) -> StopMotionTiming) {
        self.keeper = keeper
        self.makeClock = makeClock
        picturesPerSecond = Self.rate.start
        clock = makeClock(Self.rate.start)
    }

    public func setValues(_ values: [String: EffectValue]) {
        let wanted = Self.rate.value(in: values)
        guard wanted != picturesPerSecond else { return }
        picturesPerSecond = wanted
        clock = makeClock(wanted)
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        // The first moment always takes a picture, so there is one to hold.
        guard !clock.isDue(at: time), let held else {
            let taken = keeper.copy(of: image)
            held = taken
            return taken
        }
        return held
    }
}

/// A short tape of pictures played back slower than it was recorded.
protocol FrameTape {
    mutating func clear()
    /// Moves on to a moment and says what to show, asking for a picture
    /// when it is time to keep another.
    mutating func advance(to time: TimeInterval, speed: Double, capture: () -> CIImage) -> SlowMotionTape<CIImage>.Showing
}

extension SlowMotionTape: FrameTape where Frame == CIImage {}

/// Plays the picture back slower than it happens. It falls behind as it
/// goes, and every few seconds cuts forward to now and starts again.
public final class SlowMotionEffect: ImageEffect {
    public static let name = "Slow Motion"
    public static let speedKey = "Speed"

    private static let speed = NumberControl(key: speedKey, displayName: "Speed", start: 0.5, range: 0.1...1)
    private static let blendFilter = CIFilterName.dissolveTransition

    public static let parameters = [speed.parameter]

    private let canvas: CGSize
    private let keeper: FrameKeeping
    private var tape: FrameTape
    private var values: [String: EffectValue] = [:]

    init(canvas: CGSize, keeper: FrameKeeping, tape: FrameTape) {
        self.canvas = canvas
        self.keeper = keeper
        self.tape = tape
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        let speed = Self.speed.value(in: values)
        // At full speed there is nothing to slow: the picture passes
        // straight through, and the tape is let go.
        guard speed < Self.speed.range.upperBound else {
            tape.clear()
            return image
        }
        let keeper = keeper
        let showing = tape.advance(to: time, speed: speed) { keeper.copy(of: image) }
        guard showing.mix > 0 else { return showing.from }
        return showing.from.applyingFilter(Self.blendFilter, parameters: [
            kCIInputTargetImageKey: showing.to, kCIInputTimeKey: showing.mix,
        ]).cropped(to: CGRect(origin: .zero, size: canvas))
    }
}

public extension NativeEffect {
    /// The effects that play with time: stop motion and slow motion.
    static func timeEffects(pixels: PixelAccess, tuning: EffectTuning) -> [NativeEffect] {
        [
            NativeEffect(name: StopMotionEffect.name, kind: .filter, parameters: StopMotionEffect.parameters) { canvas in
                StopMotionEffect(keeper: FrameKeeper(pixels: pixels, canvas: canvas, widest: canvas.width)) {
                    StopMotionClock(picturesPerSecond: $0)
                }
            },
            NativeEffect(name: SlowMotionEffect.name, kind: .filter, parameters: SlowMotionEffect.parameters) { canvas in
                SlowMotionEffect(
                    canvas: canvas,
                    keeper: FrameKeeper(pixels: pixels, canvas: canvas, widest: CGFloat(tuning.slowMotionWidestFrame)),
                    tape: SlowMotionTape<CIImage>(
                        captureInterval: 1 / tuning.slowMotionFramesPerSecond, longestLag: tuning.slowMotionLongestLag
                    )
                )
            },
        ]
    }
}
