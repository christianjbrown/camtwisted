import CamTwistCore
import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// A source whose picture is drawn from its settings and only changes when
/// they do.
protocol DrawnPicture {
    /// The picture for these settings, or nil when there is nothing to draw.
    func picture(canvas: CGSize) -> CIImage?
}

/// Shared behaviour of the drawn sources: draw once, redraw on a change.
final class DrawnSource<Settings: Equatable & DrawnPicture>: FrameSource {
    private let canvas: CGSize
    private let lock = NSLock()
    private var settings: Settings
    private var drawn: CIImage?
    private var isDrawn = false
    private let settingsOf: (SourceSpec) -> Settings?

    init(settings: Settings, canvas: CGSize, settingsOf: @escaping (SourceSpec) -> Settings?) {
        self.settings = settings
        self.canvas = canvas
        self.settingsOf = settingsOf
    }

    func start() {}
    func stop() {}

    var latestFrame: CIImage? {
        lock.lock()
        defer { lock.unlock() }
        if !isDrawn {
            drawn = settings.picture(canvas: canvas)
            isDrawn = true
        }
        return drawn
    }

    func update(to spec: SourceSpec) -> Bool {
        guard let new = settingsOf(spec) else { return false }
        lock.lock()
        if new != settings {
            settings = new
            isDrawn = false
        }
        lock.unlock()
        return true
    }
}

extension TextSettings: DrawnPicture {
    private enum Drawing {
        /// Clear space round the text, as a share of the font size.
        static let padding: CGFloat = 0.15
        static let opaque: CGFloat = 1
        /// The drop shadow, as shares of the font size.
        static let shadowOffset: CGFloat = 0.04
        static let shadowBlur: CGFloat = 0.06
        static let shadowColor = CGColor(gray: 0, alpha: 0.6)
    }

    /// The text is set in a clear box as wide as the canvas, centred, and
    /// wraps at its edges. A fixed width keeps the letters the size asked
    /// for however many words there are.
    func picture(canvas: CGSize) -> CIImage? {
        guard !text.isEmpty else { return nil }
        let size = CGFloat(min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound))
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(fontName as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: Drawing.opaque),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle,
        ])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let padding = size * Drawing.padding
        let width = canvas.width - padding * 2
        let everything = CFRange(location: 0, length: 0)
        let needed = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, everything, nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil
        )
        let height = needed.height.rounded(.up)
        let hasShadow = hasShadow
        return CanvasDrawing.image(size: CGSize(width: canvas.width, height: height + padding * 2)) { context in
            if hasShadow {
                context.setShadow(
                    offset: CGSize(width: size * Drawing.shadowOffset, height: -size * Drawing.shadowOffset),
                    blur: size * Drawing.shadowBlur, color: Drawing.shadowColor
                )
            }
            let box = CGRect(x: padding, y: padding, width: width, height: height)
            CTFrameDraw(CTFramesetterCreateFrame(setter, everything, CGPath(rect: box, transform: nil), nil), context)
        }
    }

    /// Lines aligned and spaced as asked for.
    private var paragraphStyle: CTParagraphStyle {
        var alignment = coreTextAlignment
        var multiple = CGFloat(
            min(max(lineHeight, Self.lineHeightRange.lowerBound), Self.lineHeightRange.upperBound)
        )
        return withUnsafePointer(to: &alignment) { alignment in
            withUnsafePointer(to: &multiple) { multiple in
                CTParagraphStyleCreate([
                    CTParagraphStyleSetting(
                        spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignment
                    ),
                    CTParagraphStyleSetting(
                        spec: .lineHeightMultiple, valueSize: MemoryLayout<CGFloat>.size, value: multiple
                    ),
                ], Self.paragraphSettingCount)
            }
        }
    }

    private static let paragraphSettingCount = 2

    private var coreTextAlignment: CTTextAlignment {
        switch alignment {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justified: return .justified
        }
    }
}

extension ShapeSettings: DrawnPicture {
    func picture(canvas: CGSize) -> CIImage? {
        // The shape is drawn as wide as the canvas, in a box of its own shape.
        let aspect = ShapeGeometry.aspect(of: kind, canvasAspect: canvas.width / canvas.height)
        let size = CGSize(width: canvas.width, height: (canvas.width / aspect).rounded())
        let fill = CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: opacity)
        return CanvasDrawing.image(size: size) { context in
            context.setFillColor(fill)
            if ShapeGeometry.isRound(kind) {
                context.fillEllipse(in: CGRect(origin: .zero, size: size))
                return
            }
            let points = ShapeGeometry.corners(of: kind).map {
                CGPoint(x: $0.x * size.width, y: $0.y * size.height)
            }
            context.addLines(between: points)
            context.closePath()
            context.fillPath()
        }
    }
}

public struct TextSourceProvider: SourceProvider {
    public init() {}

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .text(let settings) = spec else { return nil }
        return DrawnSource(settings: settings, canvas: CameraContract.size) { spec in
            if case .text(let new) = spec { return new }
            return nil
        }
    }
}

public struct ShapeSourceProvider: SourceProvider {
    public init() {}

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .shape(let settings) = spec else { return nil }
        return DrawnSource(settings: settings, canvas: CameraContract.size) { spec in
            if case .shape(let new) = spec { return new }
            return nil
        }
    }
}
