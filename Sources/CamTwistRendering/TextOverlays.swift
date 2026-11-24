import CamTwistCore
import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// How far overlays may be placed. The picture runs from -1 to 1; the
/// range goes well past that so things can sit partly off screen.
enum OverlayRange {
    static let position: ClosedRange<Double> = -2...2
}

/// Converts between the units overlays are positioned in and canvas points.
enum OverlayPlacement {
    /// Overlay positions run from -1 to 1 across the picture, and use the
    /// same unit vertically, measured from the middle.
    static func point(x: Double, y: Double, canvas: CGSize) -> CGPoint {
        let halfWidth = canvas.width / 2
        return CGPoint(x: halfWidth + x * halfWidth, y: canvas.height / 2 + y * halfWidth)
    }
}

extension Dictionary where Key == String, Value == EffectValue {
    func number(_ key: String, default fallback: Double) -> Double {
        if case .number(let value) = self[key] { return value }
        return fallback
    }

    /// A switch, off unless it has been switched on.
    func boolean(_ key: String) -> Bool {
        if case .boolean(let value) = self[key] { return value }
        return false
    }

    func string(_ key: String, default fallback: String) -> String {
        if case .string(let value) = self[key] { return value }
        return fallback
    }

    func color(_ key: String, default fallback: CGColor) -> CGColor {
        if case .color(let red, let green, let blue, let alpha) = self[key] {
            return CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        }
        return fallback
    }
}

/// Draws with Core Graphics at the canvas's own resolution, so shapes and
/// text come out sharp however large they are.
enum CanvasDrawing {
    private static let bitsPerComponent = 8

    /// How many pixels are drawn for each point, each way. Text and shapes
    /// are drawn with twice the detail of the layout, so they stay sharp
    /// when the finished picture is drawn at its larger size.
    static let detail: CGFloat = 2

    /// The picture comes back the size asked for, however much detail it holds.
    static func image(size: CGSize, draw: (CGContext) -> Void) -> CIImage? {
        bitmap(size: size, draw: draw).map {
            CIImage(cgImage: $0).transformed(by: CGAffineTransform(scaleX: 1 / detail, y: 1 / detail))
        }
    }

    /// The same drawing as plain pixels, `detail` times the size asked for
    /// each way, for handing to something other than Core Image.
    static func bitmap(size: CGSize, draw: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(size.width * detail),
            height: Int(size.height * detail),
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: SRGBColorSpace.shared,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: detail, y: detail)
        draw(context)
        return context.makeImage()
    }

    /// Draws text centred in a rectangle, wrapping it to fit.
    static func draw(
        _ text: String, in rect: CGRect, fontName: String, fontSize: CGFloat, color: CGColor, context: CGContext
    ) {
        let style = [CTParagraphStyleSetting](arrayLiteral: centredSetting)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(fontName as CFString, fontSize, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String):
                CTParagraphStyleCreate(style, style.count),
        ])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let needed = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil, rect.size, nil
        )
        // The text frame is as tall as the text needs, in the middle of the rectangle.
        let frameRect = CGRect(
            x: rect.minX, y: rect.midY - needed.height / 2, width: rect.width, height: needed.height
        )
        let frame = CTFramesetterCreateFrame(
            setter, CFRange(location: 0, length: 0), CGPath(rect: frameRect, transform: nil), nil
        )
        CTFrameDraw(frame, context)
    }

    private static var centredSetting: CTParagraphStyleSetting {
        withUnsafePointer(to: &centred) {
            CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: $0)
        }
    }

    private static var centred = CTTextAlignment.center
}

/// One line of text drawn to span a width, about a point, at an angle.
/// Used by the overlays that are resized and turned by dragging.
enum TextStamp {
    static let sizeRange: ClosedRange<Double> = 0.05...2
    static let rotationRange: ClosedRange<Double> = -180...180
    /// The size text is measured at, to work out the size that spans a width.
    private static let measuringSize: CGFloat = 100
    private static let halfTurnDegrees = 180.0

    /// The two controls every stamped overlay has: how wide, and turned how far.
    static func controls(sizeKey: String, defaultSize: Double, rotationKey: String) -> [EffectParameter] {
        [
            EffectParameter(
                key: sizeKey, displayName: "Size", kind: .number, defaultValue: .number(defaultSize), range: sizeRange
            ),
            EffectParameter(
                key: rotationKey, displayName: "Rotation", kind: .number, defaultValue: .number(0), range: rotationRange
            ),
        ]
    }

    /// Text that changes as it is shown is measured with every digit as a
    /// nought, so it does not swell and shrink as its digits change.
    static func steadied(_ text: String) -> String {
        String(text.map { $0.isNumber ? "0" : $0 })
    }

    /// How far a shadow falls, as a share of the text's capital height.
    private static let shadowShare: CGFloat = 0.08
    /// How far a background reaches past the text, as a share of its capital height.
    private static let backgroundShare: CGFloat = 0.35

    private static func line(_ text: String, fontName: String, size: CGFloat, color: CGColor) -> (line: CTLine, font: CTFont) {
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
        return (CTLineCreateWithAttributedString(attributed), font)
    }

    /// The font size at which the text spans a width, or nil when the text
    /// has nothing in it to span.
    static func fontSize(for text: String, spanning width: CGFloat, fontName: String) -> CGFloat? {
        let measured = CGFloat(CTLineGetTypographicBounds(
            line(steadied(text), fontName: fontName, size: measuringSize, color: CGColor(gray: 0, alpha: 1)).line, nil, nil, nil
        ))
        guard measured > 0 else { return nil }
        return measuringSize * width / measured
    }

    /// - Parameters:
    ///   - width: how far the text spans, in canvas points.
    ///   - degrees: clockwise.
    ///   - shadow: the colour of a shadow under the text, if it has one.
    ///   - background: the colour of a box behind the text, if it has one.
    ///   - squeeze: how much of its width the text keeps, from 1 down to 0
    ///     for text seen edge on.
    static func draw(
        _ text: String, spanning width: CGFloat, at centre: CGPoint, rotation degrees: Double,
        fontName: String, color: CGColor, shadow: CGColor? = nil, background: CGColor? = nil,
        squeeze: CGFloat = 1, context: CGContext
    ) {
        guard let size = fontSize(for: text, spanning: width, fontName: fontName) else { return }
        drawLine(
            text, fontSize: size, at: centre, rotation: degrees, fontName: fontName, color: color,
            shadow: shadow, background: background, squeeze: squeeze, context: context
        )
    }

    /// One line of text at a given font size, centred on a point.
    static func drawLine(
        _ text: String, fontSize: CGFloat, at centre: CGPoint, rotation degrees: Double,
        fontName: String, color: CGColor, shadow: CGColor? = nil, background: CGColor? = nil,
        squeeze: CGFloat = 1, context: CGContext
    ) {
        let sized = line(text, fontName: fontName, size: fontSize, color: color)
        let drawnWidth = CGFloat(CTLineGetTypographicBounds(sized.line, nil, nil, nil))
        let capHeight = CTFontGetCapHeight(sized.font)
        context.saveGState()
        // Rotation is clockwise; Core Graphics turns anticlockwise.
        context.translateBy(x: centre.x, y: centre.y)
        context.rotate(by: -CGFloat(degrees * .pi / halfTurnDegrees))
        context.scaleBy(x: squeeze, y: 1)
        let baseline = -capHeight / 2
        if let background {
            let pad = capHeight * backgroundShare
            context.setFillColor(background)
            context.fill(CGRect(
                x: -drawnWidth / 2 - pad, y: baseline - CTFontGetDescent(sized.font) - pad,
                width: drawnWidth + pad * 2,
                height: CTFontGetAscent(sized.font) + CTFontGetDescent(sized.font) + pad * 2
            ))
        }
        if let shadow {
            let shadowed = line(text, fontName: fontName, size: fontSize, color: shadow)
            let offset = capHeight * shadowShare
            context.textPosition = CGPoint(x: -drawnWidth / 2 + offset, y: baseline - offset)
            CTLineDraw(shadowed.line, context)
        }
        context.textPosition = CGPoint(x: -drawnWidth / 2, y: baseline)
        CTLineDraw(sized.line, context)
        context.restoreGState()
    }
}

/// A clock that shows the time however it is asked to, in any date format.
public final class ClockEffect: ImageEffect {
    public static let name = "Clock"
    public static let formatKey = "Format"
    public static let sizeKey = EffectParameterKey.size
    public static let rotationKey = EffectParameterKey.rotation
    public static let colorKey = "Color"
    public static let xKey = EffectParameterKey.xPosition
    public static let yKey = EffectParameterKey.yPosition

    private static let defaultFormat = "HH:mm:ss"
    /// How much of the picture's width the time spans.
    private static let defaultSize = 0.35
    private static let fontName = "Helvetica-Bold"

    public static let parameters = [
        EffectParameter(key: formatKey, displayName: "Format", kind: .string, defaultValue: .string(defaultFormat)),
        EffectParameter(
            key: colorKey, displayName: "Color", kind: .color, defaultValue: .color(red: 1, green: 1, blue: 1, alpha: 1)
        ),
        EffectParameter(key: xKey, displayName: "X Position", kind: .number, defaultValue: .number(0), range: OverlayRange.position),
        EffectParameter(key: yKey, displayName: "Y Position", kind: .number, defaultValue: .number(0), range: OverlayRange.position),
    ] + TextStamp.controls(sizeKey: sizeKey, defaultSize: defaultSize, rotationKey: rotationKey)

    private let canvas: CGSize
    private let now: () -> Date
    private let formatter = DateFormatter()
    private var values: [String: EffectValue] = [:]
    private var drawn: (text: String, values: [String: EffectValue], image: CIImage)?

    public init(canvas: CGSize, now: @escaping () -> Date) {
        self.canvas = canvas
        self.now = now
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        formatter.dateFormat = values.string(Self.formatKey, default: Self.defaultFormat)
        let text = formatter.string(from: now())
        // The picture of the text is only redrawn when the text or its look changes.
        if drawn?.text != text || drawn?.values != values {
            let values = values
            let canvas = canvas
            let picture = CanvasDrawing.image(size: canvas) { context in
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
            drawn = picture.map { (text, values, $0) }
        }
        return drawn.map { $0.image.composited(over: image) } ?? image
    }
}

/// The shapes a bubble comes in.
enum BubbleKind: String, CaseIterable {
    case thought = "Thought"
    case speech = "Speech"
    case shout = "Shout"

    /// The kind a name means, or a thought bubble for anything else.
    init(named name: String) {
        self = Self.allCases.first { $0.rawValue == name } ?? .thought
    }
}

/// A cartoon thought bubble with a message in it, drawn as shapes at the
/// canvas's own resolution so it is sharp at any size.
public final class ThoughtBubbleEffect: ImageEffect {
    public static let name = "Thought bubble"
    public static let messageKey = "Message"
    public static let kindKey = "Kind"
    public static let fontKey = "Font"
    public static let fontSizeKey = "Font_Size"
    public static let sizeKey = "Bubble_Size"
    public static let xKey = EffectParameterKey.xPosition
    public static let yKey = EffectParameterKey.yPosition

    private enum Shape {
        /// The cloud's height as a share of its width.
        static let aspect: CGFloat = 0.62
        /// Puffs round the cloud's edge: angle in turns, and size as a
        /// share of the cloud's width.
        static let puffs: [(turn: CGFloat, size: CGFloat)] = [
            (0.00, 0.30), (0.10, 0.27), (0.20, 0.30), (0.30, 0.26), (0.40, 0.29),
            (0.50, 0.30), (0.60, 0.27), (0.70, 0.30), (0.80, 0.26), (0.90, 0.29),
        ]
        /// The trail of small bubbles leading down to the thinker: offset
        /// from the cloud's bottom left and size, as shares of its width.
        static let trail: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
            (0.16, -0.06, 0.11), (0.06, -0.17, 0.075), (-0.01, -0.25, 0.045),
        ]
        static let outline: CGFloat = 0.012
        /// How far in from the cloud's edge its solid middle starts.
        static let cloudCore: CGFloat = 0.12
        /// The speech bubble's tail: where it leaves the oval and its tip,
        /// from the bubble's bottom left, as shares of its width.
        static let speechTail: [(x: CGFloat, y: CGFloat)] = [(0.22, 0.12), (0.10, -0.16), (0.40, 0.05)]
        /// The shout's spikes: how many, and how far out their tips and
        /// the dips between them reach.
        static let shoutSpikes = 14
        static let shoutTip: CGFloat = 1.18
        static let shoutDip: CGFloat = 0.88
        /// The message's box inside the cloud, as shares of the cloud.
        static let textWidth: CGFloat = 0.74
        static let textHeight: CGFloat = 0.66
    }

    private static let defaultMessage = "Hmm..."
    private static let defaultFontSize = 0.07
    private static let defaultSize = 0.42
    private static let fontName = "Helvetica"
    /// Where the bubble starts, up and to the right of the middle.
    private static let defaultX = 0.4
    private static let defaultY = 0.25
    private static let fontSizeRange: ClosedRange<Double> = 0.02...0.3
    private static let bubbleSizeRange: ClosedRange<Double> = 0.15...1
    private static let outlineGrey = 0.15
    private static let textGrey = 0.1

    public static let parameters = [
        EffectParameter(key: messageKey, displayName: "Message", kind: .string, defaultValue: .string(defaultMessage)),
        EffectParameter(
            key: kindKey, displayName: "Shape", kind: .string, defaultValue: .string(BubbleKind.thought.rawValue),
            choices: BubbleKind.allCases.map(\.rawValue)
        ),
        EffectParameter(key: fontKey, displayName: "Font", kind: .string, defaultValue: .string(fontName), isFont: true),
        EffectParameter(
            key: fontSizeKey, displayName: "Font Size", kind: .number, defaultValue: .number(defaultFontSize),
            range: fontSizeRange
        ),
        EffectParameter(
            key: sizeKey, displayName: "Bubble Size", kind: .number, defaultValue: .number(defaultSize),
            range: bubbleSizeRange
        ),
        EffectParameter(key: xKey, displayName: "X Position", kind: .number, defaultValue: .number(defaultX), range: OverlayRange.position),
        EffectParameter(key: yKey, displayName: "Y Position", kind: .number, defaultValue: .number(defaultY), range: OverlayRange.position),
    ]

    private let canvas: CGSize
    private var values: [String: EffectValue] = [:]
    private var drawn: (values: [String: EffectValue], image: CIImage)?

    public init(canvas: CGSize) {
        self.canvas = canvas
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        if drawn?.values != values {
            drawn = CanvasDrawing.image(size: canvas, draw: draw).map { (values, $0) }
        }
        return drawn.map { $0.image.composited(over: image) } ?? image
    }

    /// A cloud of puffs with a trail of small bubbles down to the thinker.
    private static func thoughtPieces(cloud: CGRect) -> [CGPath] {
        let width = cloud.width
        var circles = Shape.puffs.map { puff -> CGRect in
            let angle = puff.turn * 2 * .pi
            let size = puff.size * width
            let x = cloud.midX + cos(angle) * (width - size) / 2
            let y = cloud.midY + sin(angle) * (cloud.height - size) / 2
            return CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
        }
        // The middle of the cloud, so the puffs have no gap between them.
        circles.append(cloud.insetBy(dx: width * Shape.cloudCore, dy: cloud.height * Shape.cloudCore))
        circles += Shape.trail.map { bubble in
            let size = bubble.size * width
            return CGRect(
                x: cloud.minX + bubble.x * width - size / 2, y: cloud.minY + bubble.y * width - size / 2,
                width: size, height: size
            )
        }
        return circles.map { CGPath(ellipseIn: $0, transform: nil) }
    }

    /// An oval with a tail pointing down to the speaker.
    private static func speechPieces(cloud: CGRect) -> [CGPath] {
        let tail = CGMutablePath()
        tail.addLines(between: Shape.speechTail.map {
            CGPoint(x: cloud.minX + $0.x * cloud.width, y: cloud.minY + $0.y * cloud.width)
        })
        tail.closeSubpath()
        return [CGPath(ellipseIn: cloud, transform: nil), tail]
    }

    /// A burst of spikes, for something said loudly.
    private static func shoutPieces(cloud: CGRect) -> [CGPath] {
        let burst = CGMutablePath()
        let points = (0..<Shape.shoutSpikes * 2).map { index -> CGPoint in
            let angle = CGFloat(index) / CGFloat(Shape.shoutSpikes * 2) * 2 * .pi
            // Every other point is a spike's tip; the ones between sit further in.
            let reach = index.isMultiple(of: 2) ? Shape.shoutTip : Shape.shoutDip
            return CGPoint(
                x: cloud.midX + cos(angle) * cloud.width / 2 * reach,
                y: cloud.midY + sin(angle) * cloud.height / 2 * reach
            )
        }
        burst.addLines(between: points)
        burst.closeSubpath()
        return [burst]
    }

    private func draw(in context: CGContext) {
        let width = CGFloat(values.number(Self.sizeKey, default: Self.defaultSize)) * canvas.width
        let height = width * Shape.aspect
        let centre = OverlayPlacement.point(
            x: values.number(Self.xKey, default: Self.defaultX), y: values.number(Self.yKey, default: Self.defaultY), canvas: canvas
        )
        let cloud = CGRect(x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height)

        let pieces: [CGPath]
        switch BubbleKind(named: values.string(Self.kindKey, default: BubbleKind.thought.rawValue)) {
        case .thought: pieces = Self.thoughtPieces(cloud: cloud)
        case .speech: pieces = Self.speechPieces(cloud: cloud)
        case .shout: pieces = Self.shoutPieces(cloud: cloud)
        }

        // Every piece is outlined, then every piece is filled in white over
        // the inner half of the outlines, which leaves one outline round the lot.
        context.setStrokeColor(CGColor(gray: Self.outlineGrey, alpha: 1))
        context.setLineWidth(Shape.outline * width * 2)
        context.setLineJoin(.round)
        pieces.forEach { context.addPath($0); context.strokePath() }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        pieces.forEach { context.addPath($0); context.fillPath() }

        let textRect = CGRect(
            x: cloud.midX - width * Shape.textWidth / 2, y: cloud.midY - height * Shape.textHeight / 2,
            width: width * Shape.textWidth, height: height * Shape.textHeight
        )
        CanvasDrawing.draw(
            values.string(Self.messageKey, default: Self.defaultMessage),
            in: textRect,
            fontName: values.string(Self.fontKey, default: Self.fontName),
            fontSize: CGFloat(values.number(Self.fontSizeKey, default: Self.defaultFontSize)) * canvas.height,
            color: CGColor(gray: Self.textGrey, alpha: 1),
            context: context
        )
    }
}

public extension NativeEffect {
    /// A clock in any date format, reading the time it is handed.
    static func clock(now: @escaping () -> Date) -> NativeEffect {
        NativeEffect(name: ClockEffect.name, kind: .overlay, parameters: ClockEffect.parameters) {
            ClockEffect(canvas: $0, now: now)
        }
    }

    /// A sharp cartoon thought bubble.
    static var thoughtBubble: NativeEffect {
        NativeEffect(name: ThoughtBubbleEffect.name, kind: .overlay, parameters: ThoughtBubbleEffect.parameters) {
            ThoughtBubbleEffect(canvas: $0)
        }
    }
}
