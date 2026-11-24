import CamTwistCore
import CoreImage
import Foundation

/// An effect that is a plain function of the picture, its control values
/// and the time.
public final class TransformEffect: ImageEffect {
    public typealias Transform = (CIImage, [String: EffectValue], TimeInterval, CGSize) -> CIImage

    private let canvas: CGSize
    private let transform: Transform
    private var values: [String: EffectValue] = [:]

    public init(canvas: CGSize, transform: @escaping Transform) {
        self.canvas = canvas
        self.transform = transform
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        transform(image, values, time, canvas).cropped(to: CGRect(origin: .zero, size: canvas))
    }
}

/// A television with poor reception: the picture rolls, lines tear
/// sideways, it wobbles, and scan lines and a dark bar run over it.
public enum DodgySignal {
    public static let name = "Dodgy Signal"
    public static let verticalSyncKey = "Vertical_Sync"
    public static let lineSyncKey = "Line_Sync"
    public static let distortionKey = "Distortion"
    public static let scanLinesKey = "Scan_Lines"
    public static let barsKey = "Bars"

    private enum Tuning {
        /// Picture heights the roll covers each second at full vertical sync.
        static let rollSpeed = 0.5
        /// Sideways tearing at full line sync, as a share of the width.
        static let tearShare = 0.06
        /// Slow wobble at full distortion, as a share of the width.
        static let wobbleShare = 0.15
        /// Rows of picture each band of the slow wobble covers.
        static let wobbleBand: CGFloat = 40
        /// How often a new set of torn lines appears, per second.
        static let tearRate = 30.0
        /// Width of the noise the tearing is cut from.
        static let noiseSpan = 500
        static let scanLineHeight: CGFloat = 2
        /// Darkness of the scan lines and the bar at full strength.
        static let scanLineDarkness = 0.5
        static let barDarkness = 0.45
        /// The bar's height as a share of the picture, and its speed in
        /// picture heights a second.
        static let barHeight: CGFloat = 0.18
        static let barSpeed = 0.2
        /// Where green is held so nothing shifts up or down.
        static let verticalMiddle = 0.5
    }

    /// One of the picture's faults and how strong it is to begin with.
    private struct Fault {
        let key: String
        let title: String
        let defaultStrength: Double
    }

    private static let verticalSync = Fault(key: verticalSyncKey, title: "Vertical Sync", defaultStrength: 0.125)
    private static let lineSync = Fault(key: lineSyncKey, title: "Line Sync", defaultStrength: 0.2)
    private static let distortion = Fault(key: distortionKey, title: "Distortion", defaultStrength: 0.125)
    private static let scanLineFault = Fault(key: scanLinesKey, title: "Scan Lines", defaultStrength: 0.7)
    private static let bars = Fault(key: barsKey, title: "Bars", defaultStrength: 0.45)

    private static let strengthRange: ClosedRange<Double> = 0...1

    public static let parameters: [EffectParameter] = [verticalSync, lineSync, distortion, scanLineFault, bars]
        .map { fault in
            EffectParameter(
                key: fault.key, displayName: fault.title, kind: .number,
                defaultValue: .number(fault.defaultStrength), range: strengthRange
            )
        }

    public static func apply(
        to image: CIImage, values: [String: EffectValue], time: TimeInterval, canvas: CGSize
    ) -> CIImage {
        func strength(_ fault: Fault) -> Double {
            if case .number(let value) = values[fault.key] { return value }
            return fault.defaultStrength
        }
        let bounds = CGRect(origin: .zero, size: canvas)
        var picture = rolled(image.cropped(to: bounds), by: strength(verticalSync), time: time, canvas: canvas)
        picture = displaced(
            picture, by: rowNoise(time: time, band: 1, canvas: canvas),
            amount: strength(lineSync) * Tuning.tearShare * canvas.width
        )
        picture = displaced(
            picture, by: rowNoise(time: time, band: Tuning.wobbleBand, canvas: canvas),
            amount: strength(distortion) * Tuning.wobbleShare * canvas.width
        )
        picture = scanLines(strength(scanLineFault)).composited(over: picture)
        return bar(strength(bars), time: time, canvas: canvas).composited(over: picture).cropped(to: bounds)
    }

    /// The picture slipped upwards, wrapping round like a rolling TV.
    private static func rolled(_ image: CIImage, by amount: Double, time: TimeInterval, canvas: CGSize) -> CIImage {
        guard amount > 0 else { return image.clampedToExtent() }
        let offset = (time * amount * Tuning.rollSpeed).truncatingRemainder(dividingBy: 1) * canvas.height
        return image
            .applyingFilter(CIFilterName.affineTile, parameters: [kCIInputTransformKey: CGAffineTransform.identity])
            .transformed(by: CGAffineTransform(translationX: 0, y: offset))
    }

    /// Noise that is the same all the way along each row, in bands a given
    /// number of rows tall, and different every moment.
    private static func rowNoise(time: TimeInterval, band: CGFloat, canvas: CGSize) -> CIImage {
        let column = CGFloat(Int(time * Tuning.tearRate) % Tuning.noiseSpan)
        let noise = FilterOutput.image(named: CIFilterName.randomGenerator, parameters: [:], fallback: CIImage.empty())
        let strip = noise
            .cropped(to: CGRect(x: column, y: 0, width: 1, height: canvas.height / band + 1))
            .transformed(by: CGAffineTransform(translationX: -column, y: 0))
        // One strip a pixel wide, stretched across the whole picture.
        let stretched = (band > 1 ? strip : strip.samplingNearest())
            .transformed(by: CGAffineTransform(scaleX: canvas.width, y: band))
        // Only the red channel moves things; green is held at the middle so
        // nothing shifts up or down.
        return stretched.applyingFilter(CIFilterName.colorMatrix, parameters: [
            CIInputKey.greenVector: CIVector(x: 0, y: 0, z: 0, w: 0),
            CIInputKey.biasVector: CIVector(x: 0, y: Tuning.verticalMiddle, z: 0, w: 0),
        ])
    }

    private static func displaced(_ image: CIImage, by map: CIImage, amount: Double) -> CIImage {
        guard amount > 0 else { return image }
        return image.applyingFilter(CIFilterName.displacementDistortion, parameters: [
            CIInputKey.displacementImage: map,
            kCIInputScaleKey: amount,
        ])
    }

    private static func scanLines(_ amount: Double) -> CIImage {
        guard amount > 0, let stripes = CIFilter(name: CIFilterName.stripesGenerator, parameters: [
            CIInputKey.color0: CIColor(red: 0, green: 0, blue: 0, alpha: amount * Tuning.scanLineDarkness),
            CIInputKey.color1: CIColor(red: 0, green: 0, blue: 0, alpha: 0),
            CIInputKey.width: Tuning.scanLineHeight,
            CIInputKey.sharpness: 1,
        ])?.outputImage else { return CIImage.empty() }
        // The generator's stripes stand upright; a quarter turn lays them flat.
        return stripes.transformed(by: CGAffineTransform(rotationAngle: .pi / 2))
    }

    /// A dark band drifting up the picture.
    private static func bar(_ amount: Double, time: TimeInterval, canvas: CGSize) -> CIImage {
        guard amount > 0 else { return CIImage.empty() }
        let height = canvas.height * Tuning.barHeight
        let travel = canvas.height + height
        let y = (time * Tuning.barSpeed).truncatingRemainder(dividingBy: 1) * travel - height
        return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: amount * Tuning.barDarkness))
            .cropped(to: CGRect(x: 0, y: y, width: canvas.width, height: height))
    }
}

public extension NativeEffect {
    /// A television with poor reception.
    static var badTV: NativeEffect {
        NativeEffect(name: DodgySignal.name, kind: .filter, parameters: DodgySignal.parameters) { canvas in
            TransformEffect(canvas: canvas) { image, values, time, canvas in
                DodgySignal.apply(to: image, values: values, time: time, canvas: canvas)
            }
        }
    }

    /// The picture as a comic book drawing.
    static var comicBook: NativeEffect {
        NativeEffect(name: Restyle.comicBookName, kind: .filter, parameters: [Restyle.strength]) { canvas in
            TransformEffect(canvas: canvas) { image, values, _, _ in
                Restyle.mixed(image, with: image.clampedToExtent().applyingFilter(CIFilterName.comicEffect), values: values)
            }
        }
    }

    /// The picture as a charcoal sketch on paper.
    static var charcoalSketch: NativeEffect {
        NativeEffect(name: Restyle.charcoalSketchName, kind: .filter, parameters: Sketch.parameters) { canvas in
            TransformEffect(canvas: canvas) { image, values, _, canvas in
                let lines = image.clampedToExtent().applyingFilter(CIFilterName.lineOverlay, parameters: [
                    CIInputKey.edgeIntensity: values.number(Sketch.linesKey, default: Sketch.defaultLines),
                    CIInputKey.threshold: values.number(Sketch.thresholdKey, default: Sketch.defaultThreshold),
                    CIInputKey.contrast: values.number(Sketch.contrastKey, default: Sketch.defaultContrast),
                ])
                let sketch = lines.composited(over: CIImage(color: .white))
                    .cropped(to: CGRect(origin: .zero, size: canvas))
                return Restyle.mixed(image, with: sketch, values: values)
            }
        }
    }
}

/// Bars down the left and right of the picture, the upright cousin of the
/// letterbox.
public enum PillarBox {
    public static let name = "PillarBox"
    public static let percentKey = "Percent"
    public static let colorKey = "Color"

    private static let defaultPercent = 20.0
    private static let wholePercent = 100.0

    public static let parameters = [
        EffectParameter(
            key: percentKey, displayName: "Percent", kind: .number, defaultValue: .number(defaultPercent),
            range: 0...wholePercent
        ),
        EffectParameter(
            key: colorKey, displayName: "Color", kind: .color, defaultValue: .color(red: 0, green: 0, blue: 0, alpha: 1)
        ),
    ]

    public static func apply(to image: CIImage, values: [String: EffectValue], canvas: CGSize) -> CIImage {
        let color = values.color(colorKey, default: CGColor(gray: 0, alpha: 1))
        return ScreenBars.apply(to: image, share: share(in: values), color: color, axis: .sides, canvas: canvas)
    }

    /// How much of the picture the bars cover, from none to all.
    static func share(in values: [String: EffectValue]) -> Double {
        min(max(values.number(percentKey, default: defaultPercent), 0), wholePercent) / wholePercent
    }
}

/// Which edges of the picture a pair of bars covers.
enum BarAxis {
    case sides
    case topAndBottom
}

/// A pair of bars across the picture, one on each side of it.
enum ScreenBars {
    /// The bars share the picture's length between them, one each side.
    private static let bars = 2.0

    /// - Parameter share: how much of the picture the two bars cover
    ///   between them, from none to all.
    static func apply(to image: CIImage, share: Double, color: CGColor, axis: BarAxis, canvas: CGSize) -> CIImage {
        let length = axis == .sides ? canvas.width : canvas.height
        let thickness = length * share / bars
        guard thickness > 0 else { return image }
        let paint = CIImage(color: CIColor(cgColor: color))
        let first: CGRect
        let second: CGRect
        switch axis {
        case .sides:
            first = CGRect(x: 0, y: 0, width: thickness, height: canvas.height)
            second = CGRect(x: canvas.width - thickness, y: 0, width: thickness, height: canvas.height)
        case .topAndBottom:
            first = CGRect(x: 0, y: 0, width: canvas.width, height: thickness)
            second = CGRect(x: 0, y: canvas.height - thickness, width: canvas.width, height: thickness)
        }
        return paint.cropped(to: first).composited(over: paint.cropped(to: second).composited(over: image))
    }
}

/// Bars across the top and bottom of the picture, as on a wide film.
public enum LetterBox {
    public static let name = "LetterBox"

    /// Like the pillar box, so the two are used the same way.
    public static let parameters = PillarBox.parameters

    public static func apply(to image: CIImage, values: [String: EffectValue], canvas: CGSize) -> CIImage {
        let color = values.color(PillarBox.colorKey, default: CGColor(gray: 0, alpha: 1))
        return ScreenBars.apply(
            to: image, share: PillarBox.share(in: values), color: color, axis: .topAndBottom, canvas: canvas
        )
    }
}

public extension NativeEffect {
    /// Bars across the top and bottom of the picture.
    static var letterBox: NativeEffect {
        NativeEffect(name: LetterBox.name, kind: .overlay, parameters: LetterBox.parameters) { canvas in
            TransformEffect(canvas: canvas) { image, values, _, canvas in
                LetterBox.apply(to: image, values: values, canvas: canvas)
            }
        }
    }

    /// Bars down the sides of the picture.
    static var pillarBox: NativeEffect {
        NativeEffect(name: PillarBox.name, kind: .overlay, parameters: PillarBox.parameters) { canvas in
            TransformEffect(canvas: canvas) { image, values, _, canvas in
                PillarBox.apply(to: image, values: values, canvas: canvas)
            }
        }
    }
}

/// How strongly a restyling effect takes over the picture.
enum Restyle {
    static let strengthKey = "Strength"
    static let comicBookName = "ComicBook"
    static let charcoalSketchName = "Charcoal sketch"
    private static let fullStrength = 1.0
    private static let strengthRange: ClosedRange<Double> = 0...1

    static let strength = EffectParameter(
        key: strengthKey, displayName: "Strength", kind: .number, defaultValue: .number(fullStrength), range: strengthRange
    )

    /// The picture faded towards its restyled version by the strength.
    static func mixed(_ image: CIImage, with restyled: CIImage, values: [String: EffectValue]) -> CIImage {
        let amount = values.number(strengthKey, default: fullStrength)
        guard amount < fullStrength else { return restyled }
        return image.applyingFilter(CIFilterName.dissolveTransition, parameters: [
            kCIInputTargetImageKey: restyled,
            kCIInputTimeKey: max(amount, 0),
        ])
    }
}

/// The controls of the pencil sketch effect.
enum Sketch {
    static let linesKey = "Lines"
    static let thresholdKey = "Threshold"
    static let contrastKey = "Contrast"
    static let defaultLines = 1.0
    static let defaultThreshold = 0.1
    static let defaultContrast = 50.0
    private static let linesRange: ClosedRange<Double> = 0.1...5
    private static let thresholdRange: ClosedRange<Double> = 0.01...0.6
    private static let contrastRange: ClosedRange<Double> = 1...200

    static let parameters = [
        EffectParameter(
            key: linesKey, displayName: "Line strength", kind: .number, defaultValue: .number(defaultLines),
            range: linesRange
        ),
        EffectParameter(
            key: thresholdKey, displayName: "Detail", kind: .number, defaultValue: .number(defaultThreshold),
            range: thresholdRange
        ),
        EffectParameter(
            key: contrastKey, displayName: "Contrast", kind: .number, defaultValue: .number(defaultContrast),
            range: contrastRange
        ),
        Restyle.strength,
    ]
}
