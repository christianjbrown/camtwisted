import CamTwistCore
import CoreGraphics
import CoreImage
import Foundation

/// A timer drawn over the picture that counts down to zero or up from it.
public final class CountdownEffect: ImageEffect {
    public static let name = "Countdown"
    public static let timeKey = "Time"
    public static let countsUpKey = "Count_Up"
    public static let carriesOnKey = "Then_Count_Up"
    public static let pauseKey = "Pause"
    public static let holdKey = "Hold"
    public static let sizeKey = EffectParameterKey.size
    public static let rotationKey = EffectParameterKey.rotation
    public static let colorKey = "Color"
    public static let xKey = EffectParameterKey.xPosition
    public static let yKey = EffectParameterKey.yPosition

    private static let defaultTime = "05:00"
    /// How much of the picture's width the time spans.
    private static let defaultSize = 0.3
    private static let fontName = "Helvetica-Bold"

    public static let parameters = [
        EffectParameter(key: timeKey, displayName: "Time", kind: .string, defaultValue: .string(defaultTime)),
        EffectParameter(key: countsUpKey, displayName: "Count up", kind: .boolean, defaultValue: .boolean(false)),
        EffectParameter(
            key: carriesOnKey, displayName: "Count up after zero", kind: .boolean, defaultValue: .boolean(false)
        ),
        EffectParameter(key: pauseKey, displayName: "Pause", kind: .boolean, defaultValue: .boolean(false)),
        EffectParameter(key: holdKey, displayName: "Hold at the start", kind: .boolean, defaultValue: .boolean(false)),
        EffectParameter(
            key: colorKey, displayName: "Color", kind: .color, defaultValue: .color(red: 1, green: 1, blue: 1, alpha: 1)
        ),
        EffectParameter(key: xKey, displayName: "X Position", kind: .number, defaultValue: .number(0), range: OverlayRange.position),
        EffectParameter(key: yKey, displayName: "Y Position", kind: .number, defaultValue: .number(0), range: OverlayRange.position),
    ] + TextStamp.controls(sizeKey: sizeKey, defaultSize: defaultSize, rotationKey: rotationKey)

    private let canvas: CGSize
    private var values: [String: EffectValue] = [:]
    private var stopwatch = Stopwatch()
    private var settings: CountdownSettings?
    private var drawn: (text: String, values: [String: EffectValue], image: CIImage)?

    public init(canvas: CGSize) {
        self.canvas = canvas
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        let wanted = CountdownSettings(
            length: CountdownClock.seconds(fromText: values.string(Self.timeKey, default: Self.defaultTime)),
            countsUp: values.boolean(Self.countsUpKey),
            carriesOnPastZero: values.boolean(Self.carriesOnKey)
        )
        // A new time or direction starts the count again.
        if wanted != settings {
            settings = wanted
            stopwatch = Stopwatch()
        }
        stopwatch.advance(to: time, isPaused: values.boolean(Self.pauseKey), isHeld: values.boolean(Self.holdKey))
        let text = CountdownClock.text(
            forSeconds: CountdownClock.secondsShown(elapsed: stopwatch.elapsed, settings: wanted)
        )
        // The picture of the text is only redrawn when the text or its look changes.
        if drawn?.text != text || drawn?.values != values {
            drawn = picture(of: text).map { (text, values, $0) }
        }
        return drawn.map { $0.image.composited(over: image) } ?? image
    }

    private func picture(of text: String) -> CIImage? {
        let values = values
        let canvas = canvas
        return CanvasDrawing.image(size: canvas) { context in
            TextStamp.draw(
                text, spanning: CGFloat(values.number(Self.sizeKey, default: Self.defaultSize)) * canvas.width,
                at: OverlayPlacement.point(
                    x: values.number(Self.xKey, default: 0), y: values.number(Self.yKey, default: 0), canvas: canvas
                ),
                rotation: values.number(Self.rotationKey, default: 0),
                fontName: Self.fontName, color: values.color(Self.colorKey, default: CGColor(gray: 1, alpha: 1)),
                context: context
            )
        }
    }
}

public extension NativeEffect {
    /// A timer that counts down or up.
    static var countdown: NativeEffect {
        NativeEffect(name: CountdownEffect.name, kind: .overlay, parameters: CountdownEffect.parameters) {
            CountdownEffect(canvas: $0)
        }
    }
}
