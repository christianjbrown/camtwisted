import CamTwistCore
import CoreGraphics
import Foundation

/// A pair of chunky sunglasses made of big square pixels, sat on the eyes.
struct PixelSunglasses: Wearable {
    static let name = "Pixel Sunglasses"
    static let colorKey = "Color"
    /// Very nearly black.
    private static let color = ColorControl(key: colorKey, displayName: "Color", red: 0.05, green: 0.05, blue: 0.05)

    private enum Pixel {
        static let lens: Character = "#"
        static let shine: Character = "o"
        static let clear: Character = "."
        /// The glasses, a character to a pixel: a bar across the top that
        /// runs on past one side, and two lenses with a glint on each.
        static let rows = [
            "####################",
            "..#o#o####..#o#o####",
            "..##o#o###..##o#o###",
            "...######....######.",
            "....####......####..",
        ]
        /// The eyes sit in the middles of the lenses, this many pixels apart.
        static let betweenEyes: CGFloat = 10
        /// The point half way between the eyes, in pixels from the top left.
        static let eyeLine = CGPoint(x: 11, y: 2.5)
        /// How far the drawing reaches from there, in eye distances.
        static let reach: CGFloat = 1.2
    }

    private enum Paint {
        static let shine = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }

    let parameters = [color.parameter]
    let reach = Pixel.reach

    func anchor(on face: FaceExpression) -> CGPoint { face.eyeLine }

    /// One unit is the distance between the eyes.
    func unit(on face: FaceExpression) -> CGFloat { face.eyeSpan }

    func draw(on face: FaceExpression, time: TimeInterval, values: [String: EffectValue], in context: CGContext) {
        let lens = Self.color.value(in: values)
        let side = 1 / Pixel.betweenEyes
        // Hard edges: these are meant to look like pixels.
        context.setShouldAntialias(false)
        for (row, line) in Pixel.rows.enumerated() {
            for (column, pixel) in line.enumerated() where pixel != Pixel.clear {
                context.setFillColor(pixel == Pixel.shine ? Paint.shine : lens)
                // Rows are written top down; the picture's points count up.
                context.fill(CGRect(
                    x: (CGFloat(column) - Pixel.eyeLine.x) * side, y: (Pixel.eyeLine.y - CGFloat(row + 1)) * side,
                    width: side, height: side
                ))
            }
        }
    }
}
