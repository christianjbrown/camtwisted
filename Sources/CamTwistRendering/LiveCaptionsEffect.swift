import CamTwistCore
import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// Something a preview can show with sample content in place of the real
/// thing, such as captions with words nobody has said.
protocol SamplePreviewing: AnyObject {
    func showSample()
}

/// An effect that hears the sources above it in its scene.
protocol HearsSourcesAbove: AnyObject {
    /// The sources above it that make sound, each with how loud it is.
    /// Told again before every frame.
    func hear(_ sources: HeardSources)
}

/// What is said in the sources above it, written along the bottom of the
/// picture as it is said, like subtitles. Each source is heard as loud as
/// it is in the mix, so one turned right down is left out. Only the last
/// few lines show, and they clear a few seconds after the talking stops.
public final class LiveCaptionsEffect: ImageEffect, SamplePreviewing, HearsSourcesAbove {
    public static let name = "Live Captions"
    public static let fontKey = EffectParameterKey.fontName
    public static let colorKey = EffectParameterKey.color
    public static let shadowKey = EffectParameterKey.shadow
    public static let backgroundKey = EffectParameterKey.background
    public static let sizeKey = EffectParameterKey.size
    public static let yKey = EffectParameterKey.yPosition
    public static let linesKey = "Lines"
    public static let lingerKey = "Linger"
    public static let startFont = "OpenSans-SemiBold"

    static let sampleWords = "Your words appear here as you speak"

    private enum Layout {
        /// How much of the picture's width a line may span before it wraps.
        static let widthShare: CGFloat = 0.8
        /// The space from one line to the next, in font sizes.
        static let lineSpacing: CGFloat = 1.3
    }

    private static let look = TextLook(
        fontKey: fontKey, colorKey: colorKey, shadowKey: shadowKey, backgroundKey: backgroundKey, startFont: startFont
    )
    /// The font's size as a share of the picture's height.
    private static let size = NumberControl(key: sizeKey, displayName: "Size", start: 0.06, range: 0.02...0.2)
    /// Where the bottom line sits, from -1 at the bottom of a square picture to 1 at its top.
    private static let y = NumberControl(key: yKey, displayName: "Y Position", start: -0.45, range: OverlayRange.position)
    private static let lines = NumberControl(key: linesKey, displayName: "Lines", start: 2, range: 1...4)
    private static let linger = NumberControl(
        key: lingerKey, displayName: "Seconds the words stay after you stop", start: 4, range: 1...10
    )

    public static let parameters = look.parameters + [size.parameter, y.parameter, lines.parameter, linger.parameter]

    private let canvas: CGSize
    private let listener: CaptionsListening
    private let now: () -> Date
    private var values: [String: EffectValue] = [:]
    private var wanted = HeardSources.none
    /// What it is listening to now, once a frame has been shown.
    private var joined: HeardSources?
    private var isSample = false

    init(canvas: CGSize, listener: CaptionsListening, now: @escaping () -> Date) {
        self.canvas = canvas
        self.listener = listener
        self.now = now
    }

    deinit {
        if let joined { listener.leave(joined) }
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    func hear(_ sources: HeardSources) {
        wanted = sources
    }

    /// A preview shows sample words and never starts listening.
    func showSample() {
        isSample = true
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        let words = isSample ? Self.sampleWords : heardWords()
        let fontName = Self.look.fontName(in: values)
        let fontSize = canvas.height * CGFloat(Self.size.value(in: values))
        let shown = Self.lines(
            of: words, fontName: fontName, fontSize: fontSize, width: canvas.width * Layout.widthShare
        ).suffix(Int(Self.lines.value(in: values).rounded()))
        guard !shown.isEmpty else { return image }
        let bottom = OverlayPlacement.point(x: 0, y: Self.y.value(in: values), canvas: canvas)
        let color = Self.look.color(in: values)
        let shadow = Self.look.shadow(in: values)
        let background = Self.look.background(in: values)
        let painted = CanvasDrawing.image(size: canvas) { context in
            // The newest line at the bottom, the older ones stacked above it.
            for (index, line) in shown.reversed().enumerated() {
                TextStamp.drawLine(
                    line, fontSize: fontSize,
                    at: CGPoint(x: bottom.x, y: bottom.y + CGFloat(index) * fontSize * Layout.lineSpacing),
                    rotation: 0, fontName: fontName, color: color, shadow: shadow, background: background,
                    context: context
                )
            }
        }
        return painted.map { $0.composited(over: image) } ?? image
    }

    /// The words heard lately, or none once the talking stopped a while ago.
    /// The first frame shown starts the listening, and a change in what is
    /// above it moves the listening over.
    private func heardWords() -> String {
        if joined != wanted {
            if let joined { listener.leave(joined) }
            joined = wanted.isEmpty ? nil : wanted
            if let joined { listener.join(joined) }
        }
        guard let joined else { return "" }
        let heard = listener.heard(from: joined)
        let quietFor = now().timeIntervalSince(heard.when)
        return quietFor <= Self.linger.value(in: values) ? heard.words : ""
    }

    /// The text broken into lines that each fit the width, in order.
    static func lines(of text: String, fontName: String, fontSize: CGFloat, width: CGFloat) -> [String] {
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(fontName as CFString, fontSize, nil),
        ])
        let setter = CTTypesetterCreateWithAttributedString(attributed)
        let whole = text as NSString
        var lines: [String] = []
        var start = 0
        while start < whole.length {
            // At least one character a line, however narrow, so it always moves on.
            let count = max(CTTypesetterSuggestLineBreak(setter, start, Double(width)), 1)
            let line = whole.substring(with: NSRange(location: start, length: count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { lines.append(line) }
            start += count
        }
        return lines
    }
}

extension NativeEffect {
    static func liveCaptions(listener: CaptionsListening, now: @escaping () -> Date) -> NativeEffect {
        NativeEffect(name: LiveCaptionsEffect.name, kind: .overlay, parameters: LiveCaptionsEffect.parameters) { canvas in
            LiveCaptionsEffect(canvas: canvas, listener: listener, now: now)
        }
    }
}
