import CamTwistCore
import CoreImage
import Foundation

/// The picture of somebody on a bad connection: it keeps freezing for a
/// moment at random, and can go blocky while it is stuck.
public final class BadConnectionEffect: ImageEffect {
    public static let name = "Bad Connection"
    public static let frequencyKey = "Freezes"
    public static let longestKey = "Longest_Freeze"
    public static let blockinessKey = "Blockiness"

    private static let defaultFrequency = 12.0
    private static let frequencyRange: ClosedRange<Double> = 0...60
    private static let defaultLongest = 2.0
    private static let longestRange: ClosedRange<Double> = 0.2...10
    private static let defaultBlockiness = 0.0
    private static let blockinessRange: ClosedRange<Double> = 0...1
    /// The largest blocks, as a share of the picture's width.
    private static let largestBlock = 0.05
    private static let pixellateFilter = CIFilterName.pixellate
    private static let seed: UInt32 = 0x0BAD_C0DE

    public static let parameters = [
        EffectParameter(
            key: frequencyKey, displayName: "Freezes a minute", kind: .number,
            defaultValue: .number(defaultFrequency), range: frequencyRange
        ),
        EffectParameter(
            key: longestKey, displayName: "Longest freeze in seconds", kind: .number,
            defaultValue: .number(defaultLongest), range: longestRange
        ),
        EffectParameter(
            key: blockinessKey, displayName: "Blocky while frozen", kind: .number,
            defaultValue: .number(defaultBlockiness), range: blockinessRange
        ),
    ]

    private let canvas: CGSize
    private var stutter: ConnectionStutter<XorShiftRandom>
    private var values: [String: EffectValue] = [:]
    /// The last picture that got through.
    private var held: CIImage?

    public init(canvas: CGSize) {
        self.canvas = canvas
        stutter = ConnectionStutter(random: XorShiftRandom(seed: Self.seed))
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        let isFrozen = stutter.isFrozen(
            at: time,
            freezesPerMinute: values.number(Self.frequencyKey, default: Self.defaultFrequency),
            longestFreeze: values.number(Self.longestKey, default: Self.defaultLongest)
        )
        guard isFrozen, let stuck = held else {
            held = image
            return image
        }
        let blockiness = values.number(Self.blockinessKey, default: Self.defaultBlockiness)
        guard blockiness > 0 else { return stuck }
        return stuck.clampedToExtent().applyingFilter(Self.pixellateFilter, parameters: [
            kCIInputScaleKey: max(blockiness * Self.largestBlock * canvas.width, 1),
            kCIInputCenterKey: CIVector(x: 0, y: 0),
        ]).cropped(to: CGRect(origin: .zero, size: canvas))
    }
}

public extension NativeEffect {
    /// A picture that keeps freezing, as on a bad connection.
    static var badConnection: NativeEffect {
        NativeEffect(name: BadConnectionEffect.name, kind: .filter, parameters: BadConnectionEffect.parameters) {
            BadConnectionEffect(canvas: $0)
        }
    }
}
