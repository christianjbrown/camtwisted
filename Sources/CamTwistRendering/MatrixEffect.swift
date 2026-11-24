import CamTwistCore
import CoreImage
import CoreText
import Foundation

/// The picture as falling green code, the way MatrixTV draws it.
public final class MatrixEffect: ImageEffect {
    public static let name = "Matrix"
    public static let strengthKey = "Strength"

    /// The rain is this many glyphs across; the rows follow the canvas shape.
    private static let columns = 80
    /// How much of the picture the code takes over: none of it at 0, all
    /// of it at 1. The default leaves the picture clearly visible underneath.
    private static let defaultStrength = 0.45

    private let canvas: CGSize
    private let pixels: PixelAccess
    private let font: MatrixFont
    private let rows: Int
    private var rain: MatrixRain
    private var random: XorShiftRandom
    private var strength = MatrixEffect.defaultStrength

    public init(canvas: CGSize, pixels: PixelAccess, font: MatrixFont, seed: UInt32) {
        self.canvas = canvas
        self.pixels = pixels
        self.font = font
        rows = max(Int((CGFloat(Self.columns) * canvas.height / canvas.width).rounded()), 1)
        rain = MatrixRain(columns: Self.columns, rows: rows, glyphCount: font.glyphCount)
        random = XorShiftRandom(seed: seed)
    }

    public static let parameters = [
        EffectParameter(
            key: strengthKey, displayName: "Strength", kind: .number, defaultValue: .number(defaultStrength),
            range: 0...1
        ),
    ]

    public func setValues(_ values: [String: EffectValue]) {
        if case .number(let value) = values[Self.strengthKey] {
            strength = value
        } else {
            strength = Self.defaultStrength
        }
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        let small = pixels.rgba(of: image, width: Self.columns, height: rows)
        rain.update(random: &random)
        let picture = rain.picture(
            brightness: MatrixRain.brightness(rgba: small, width: Self.columns, height: rows),
            font: font,
            random: &random
        )
        let code = pixels
            .image(rgba: picture, width: Self.columns * font.glyphSize, height: rows * font.glyphSize)
            .stretched(to: canvas, smooth: false)
        // The code is laid over the picture, as see-through as the strength says.
        return image.applyingFilter(CIFilterName.dissolveTransition, parameters: [
            kCIInputTargetImageKey: code,
            kCIInputTimeKey: min(max(strength, 0), 1),
        ])
    }
}

/// Draws a Matrix font from the system's own typefaces: half-width katakana
/// and digits, as in the film.
public enum DrawnMatrixFont {
    private static let glyphSize = 16
    private static let fontName = "Hiragino Sans W6"
    /// Text size as a share of the cell, leaving a little air around it.
    private static let textShare: CGFloat = 0.85
    private static let firstKatakana: UInt32 = 0xFF66
    private static let katakanaCount = 56
    private static let extras = "0123456789Z:.=*+-<>¦|ﾞ"
    private static let bitsPerComponent = 8
    /// Ink coverage, out of 255, at which each brighter level starts.
    private static let levelThresholds: [UInt8] = [40, 110, 190]

    public static func make() -> MatrixFont {
        let characters = (0..<katakanaCount).compactMap { UnicodeScalar(firstKatakana + UInt32($0)) }
            .map { String(Character($0)) } + extras.map(String.init)
        var levels: [UInt8] = []
        for character in characters {
            levels += draw(character, glyphSize: glyphSize)
        }
        return MatrixFont(glyphCount: characters.count, glyphSize: glyphSize, levels: levels)
    }

    /// The character's ink coverage as brightness levels, in a square of the
    /// given size. Blank when no drawing surface can be made at that size.
    static func draw(_ character: String, glyphSize: Int) -> [UInt8] {
        var ink = [UInt8](repeating: 0, count: glyphSize * glyphSize)
        ink.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: glyphSize,
                height: glyphSize,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: glyphSize,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            let font = CTFontCreateWithName(fontName as CFString, CGFloat(glyphSize) * textShare, nil)
            let text = NSAttributedString(string: character, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(gray: 1, alpha: 1),
            ])
            let line = CTLineCreateWithAttributedString(text)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            context.textPosition = CGPoint(
                x: (CGFloat(glyphSize) - bounds.width) / 2 - bounds.minX,
                y: (CGFloat(glyphSize) - bounds.height) / 2 - bounds.minY
            )
            CTLineDraw(line, context)
        }
        return ink.map { coverage in
            UInt8(levelThresholds.filter { coverage >= $0 }.count)
        }
    }
}
