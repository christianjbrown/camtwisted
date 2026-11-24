import CamTwistCore
import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// A news channel's headline across the bottom of the picture: a coloured
/// tag such as "Breaking news", the headline on a bar beneath it, and a
/// smaller line under that.
public final class HeadlineEffect: ImageEffect {
    public static let name = "News Headline"
    public static let tagKey = "Tag"
    public static let headlineKey = "Headline"
    public static let detailKey = "Detail"
    public static let tagColorKey = "Tag_Color"
    public static let barColorKey = "Bar_Color"
    public static let textColorKey = EffectParameterKey.textColor
    public static let xKey = EffectParameterKey.xPosition
    public static let yKey = EffectParameterKey.yPosition
    public static let sizeKey = EffectParameterKey.size
    public static let rotationKey = EffectParameterKey.rotation
    public static let scrollSpeedKey = "Scroll_Speed"

    private enum Design {
        /// Heights of the three strips, as shares of the banner's width.
        static let tagHeight: CGFloat = 0.045
        static let barHeight: CGFloat = 0.075
        static let detailHeight: CGFloat = 0.04
        /// Text height as a share of its strip, and the space before it
        /// as a share of the banner's width.
        static let textShare: CGFloat = 0.62
        static let inset: CGFloat = 0.018
        static let headlineFont = "Helvetica-Bold"
        static let detailFont = "Helvetica"
        /// How much black is washed over the bar's colour for the second line's strip.
        static let detailShade: CGFloat = 0.18
        /// The space between the end of scrolling text and its start
        /// coming round again, as a share of the banner's width.
        static let scrollGap: CGFloat = 0.12
        /// How far text may overrun its strip, in points, and still count
        /// as fitting. A strip cut to its text's own length would otherwise
        /// be taken for too short by a rounding error.
        static let fitTolerance: CGFloat = 1
    }

    private static let defaultTag = "BREAKING NEWS"
    private static let defaultHeadline = "Headline goes here"
    private static let defaultDetail = "A second line, for the detail"
    private static let defaultY = -0.4
    /// How fast text too long for its strip runs along it, in banner widths a second.
    private static let defaultScrollSpeed = 0.1
    private static let scrollSpeedRange: ClosedRange<Double> = 0...0.5
    private static let defaultSize = 0.9
    private static let sizeRange: ClosedRange<Double> = 0.2...1.5
    private static let rotationRange: ClosedRange<Double> = -180...180
    private static let halfTurnDegrees = 180.0
    private static let defaultTagColor = (red: 0.8, green: 0.05, blue: 0.05)
    private static let defaultBarColor = (red: 1.0, green: 1.0, blue: 1.0)
    private static let defaultTextColor = (red: 0.08, green: 0.08, blue: 0.1)

    public static let parameters = [
        EffectParameter(key: tagKey, displayName: "Tag", kind: .string, defaultValue: .string(defaultTag)),
        EffectParameter(key: headlineKey, displayName: "Headline", kind: .string, defaultValue: .string(defaultHeadline)),
        EffectParameter(key: detailKey, displayName: "Second line", kind: .string, defaultValue: .string(defaultDetail)),
        color(tagColorKey, "Tag colour", defaultTagColor),
        color(barColorKey, "Bar colour", defaultBarColor),
        color(textColorKey, "Text colour", defaultTextColor),
        EffectParameter(key: xKey, displayName: "X Position", kind: .number, defaultValue: .number(0), range: OverlayRange.position),
        EffectParameter(
            key: yKey, displayName: "Y Position", kind: .number, defaultValue: .number(defaultY), range: OverlayRange.position
        ),
        EffectParameter(key: sizeKey, displayName: "Size", kind: .number, defaultValue: .number(defaultSize), range: sizeRange),
        EffectParameter(
            key: rotationKey, displayName: "Rotation", kind: .number, defaultValue: .number(0), range: rotationRange
        ),
        EffectParameter(
            key: scrollSpeedKey, displayName: "Scroll speed, for text too long to fit", kind: .number,
            defaultValue: .number(defaultScrollSpeed), range: scrollSpeedRange
        ),
    ]

    private static func color(_ key: String, _ name: String, _ value: (red: Double, green: Double, blue: Double)) -> EffectParameter {
        EffectParameter(
            key: key, displayName: name, kind: .color,
            defaultValue: .color(red: value.red, green: value.green, blue: value.blue, alpha: 1)
        )
    }

    private static func cgColor(_ value: (red: Double, green: Double, blue: Double)) -> CGColor {
        CGColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: 1)
    }

    private let canvas: CGSize
    private var values: [String: EffectValue] = [:]
    /// The last banner drawn, and whether any of its text was scrolling.
    private var drawn: (values: [String: EffectValue], image: CIImage, scrolls: Bool)?

    public init(canvas: CGSize) {
        self.canvas = canvas
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        // The banner is only redrawn when one of its settings changes, or
        // while text too long for its strip is running along it.
        if drawn?.values != values || drawn?.scrolls == true {
            drawn = banner(at: time).map { (values, $0.image, $0.scrolls) }
        }
        return drawn.map { $0.image.composited(over: image) } ?? image
    }

    private func banner(at time: TimeInterval) -> (image: CIImage, scrolls: Bool)? {
        let centre = OverlayPlacement.point(
            x: values.number(Self.xKey, default: 0), y: values.number(Self.yKey, default: Self.defaultY), canvas: canvas
        )
        let width = CGFloat(values.number(Self.sizeKey, default: Self.defaultSize)) * canvas.width
        let tag = values.string(Self.tagKey, default: Self.defaultTag)
        let headline = values.string(Self.headlineKey, default: Self.defaultHeadline)
        let detail = values.string(Self.detailKey, default: Self.defaultDetail)
        let tagColor = values.color(Self.tagColorKey, default: Self.cgColor(Self.defaultTagColor))
        let barColor = values.color(Self.barColorKey, default: Self.cgColor(Self.defaultBarColor))
        let textColor = values.color(Self.textColorKey, default: Self.cgColor(Self.defaultTextColor))
        let white = CGColor(gray: 1, alpha: 1)

        // From the bottom up: the second line, the headline's bar, the tag.
        let detailHeight = detail.isEmpty ? 0 : width * Design.detailHeight
        let barHeight = width * Design.barHeight
        let tagHeight = tag.isEmpty ? 0 : width * Design.tagHeight
        let left = centre.x - width / 2
        let bottom = centre.y - (detailHeight + barHeight + tagHeight) / 2
        let inset = width * Design.inset

        // Rotation is clockwise; Core Graphics turns anticlockwise.
        let angle = -CGFloat(values.number(Self.rotationKey, default: 0) * .pi / Self.halfTurnDegrees)

        let travelled = CGFloat(time * values.number(Self.scrollSpeedKey, default: Self.defaultScrollSpeed)) * width
        let gap = width * Design.scrollGap
        var scrolls = false

        let image = CanvasDrawing.image(size: canvas) { context in
            // The whole banner turns about its own middle.
            context.translateBy(x: centre.x, y: centre.y)
            context.rotate(by: angle)
            context.translateBy(x: -centre.x, y: -centre.y)
            func strip(
                _ text: String, font: String, color: CGColor, on fill: CGColor, shadedBy shade: CGFloat = 0,
                in rect: CGRect
            ) {
                context.setFillColor(fill)
                context.fill(rect)
                // A wash of black over the fill darkens it, whatever colour it is.
                context.setFillColor(CGColor(gray: 0, alpha: shade))
                context.fill(rect)
                let line = Self.line(text, font: font, size: rect.height * Design.textShare, color: color)
                let length = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                // The text sits on a baseline that centres its capitals in the strip.
                let baseline = rect.midY - rect.height * Design.textShare * Self.capitalHalfHeight
                context.saveGState()
                context.clip(to: rect)
                if length > rect.width - inset * 2 + Design.fitTolerance {
                    // Too long to fit: it runs along the strip, and comes
                    // round again a little after its end has gone by.
                    scrolls = true
                    let lap = length + gap
                    let start = rect.minX + inset - travelled.truncatingRemainder(dividingBy: lap)
                    for copy in [start, start + lap] {
                        context.textPosition = CGPoint(x: copy, y: baseline)
                        CTLineDraw(line, context)
                    }
                } else {
                    context.textPosition = CGPoint(x: rect.minX + inset, y: baseline)
                    CTLineDraw(line, context)
                }
                context.restoreGState()
            }
            if !detail.isEmpty {
                strip(
                    detail, font: Design.detailFont, color: textColor, on: barColor, shadedBy: Design.detailShade,
                    in: CGRect(x: left, y: bottom, width: width, height: detailHeight)
                )
            }
            strip(
                headline, font: Design.headlineFont, color: textColor, on: barColor,
                in: CGRect(x: left, y: bottom + detailHeight, width: width, height: barHeight)
            )
            if !tag.isEmpty {
                let size = tagHeight * Design.textShare
                let needed = CTLineGetTypographicBounds(
                    Self.line(tag, font: Design.headlineFont, size: size, color: white), nil, nil, nil
                )
                strip(
                    tag, font: Design.headlineFont, color: white, on: tagColor,
                    in: CGRect(
                        x: left, y: bottom + detailHeight + barHeight,
                        width: min(CGFloat(needed) + inset * 2, width), height: tagHeight
                    )
                )
            }
        }
        return image.map { ($0, scrolls) }
    }

    /// Half the height of a capital letter, as a share of the font size.
    private static let capitalHalfHeight: CGFloat = 0.36

    private static func line(_ text: String, font: String, size: CGFloat, color: CGColor) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]))
    }
}

public extension NativeEffect {
    /// A news channel's headline banner.
    static var headline: NativeEffect {
        NativeEffect(name: HeadlineEffect.name, kind: .overlay, parameters: HeadlineEffect.parameters) {
            HeadlineEffect(canvas: $0)
        }
    }
}
