import Foundation

/// How a colour is keyed out of a picture, with the same controls as the
/// chroma key most streaming software has.
public struct ChromaKeySettings: Codable, Equatable, Sendable {
    /// Every one of the three controls runs from nothing to everything.
    public static let range: ClosedRange<Double> = 0...1
    /// A green backdrop, keyed the way most streaming software starts out.
    public static let greenScreen = ChromaKeySettings(
        red: 0, green: 1, blue: 0, similarity: 0.4, smoothness: 0.08, spillReduction: 0.1
    )

    public var red: Double
    public var green: Double
    public var blue: Double
    /// How far from the key colour still counts as the key colour.
    public var similarity: Double
    /// How gradually the edge fades in beyond that.
    public var smoothness: Double
    /// How far beyond the key colour its tint is drained from what is kept.
    public var spillReduction: Double

    public init(red: Double, green: Double, blue: Double, similarity: Double, smoothness: Double, spillReduction: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.similarity = similarity
        self.smoothness = smoothness
        self.spillReduction = spillReduction
    }
}

/// A colour with its opacity, premultiplied.
public struct KeyedColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
}

/// Keys a colour out: what is near the key colour turns clear, the edge
/// fades, and the key colour's tint is drained from what stays.
public enum ChromaKey {
    /// Each side of the colour cube handed to Core Image.
    public static let cubeSize = 64

    private enum Chroma {
        // The colour-difference parts of BT.601, which ignore brightness.
        static let blueDifference = (red: -0.168736, green: -0.331264, blue: 0.5)
        static let redDifference = (red: 0.5, green: -0.418688, blue: -0.081312)
        static let luma = (red: 0.299, green: 0.587, blue: 0.114)
    }

    /// The fade is eased, as it is in the software this follows.
    private static let easing = 1.5

    public static func keyed(red: Double, green: Double, blue: Double, settings: ChromaKeySettings) -> KeyedColor {
        let pixel = hue(red: red, green: green, blue: blue)
        let key = hue(red: settings.red, green: settings.green, blue: settings.blue)
        let beyond = hypot(pixel.blue - key.blue, pixel.red - key.red) - settings.similarity
        let alpha = share(of: beyond, across: settings.smoothness)
        let kept = share(of: beyond, across: settings.spillReduction)
        // Draining the tint means moving towards grey of the same brightness.
        let grey = red * Chroma.luma.red + green * Chroma.luma.green + blue * Chroma.luma.blue
        func drained(_ value: Double) -> Double { (grey + (value - grey) * kept) * alpha }
        return KeyedColor(red: drained(red), green: drained(green), blue: drained(blue), alpha: alpha)
    }

    /// A colour cube for Core Image's colour cube filter: red changes
    /// fastest, then green, then blue.
    public static func cube(for settings: ChromaKeySettings) -> [Float] {
        let last = Double(cubeSize - 1)
        var data: [Float] = []
        data.reserveCapacity(cubeSize * cubeSize * cubeSize * 4)
        for blue in 0..<cubeSize {
            for green in 0..<cubeSize {
                for red in 0..<cubeSize {
                    let color = keyed(
                        red: Double(red) / last, green: Double(green) / last, blue: Double(blue) / last,
                        settings: settings
                    )
                    data += [Float(color.red), Float(color.green), Float(color.blue), Float(color.alpha)]
                }
            }
        }
        return data
    }

    /// Below this brightness a colour is too dark to say what colour it is.
    private static let darkest = 0.04
    /// From here up a colour's brightness is taken out of it entirely.
    private static let fullyLit = 0.16

    /// A colour's chroma with its brightness taken out, so that the lit and
    /// the shadowed parts of a backdrop count as the same colour. Screens
    /// are never evenly lit, and keying on plain chroma leaves the shadows
    /// behind. Colours near black keep their plain chroma, which is close
    /// to none, so black is never mistaken for the backdrop.
    private static func hue(red: Double, green: Double, blue: Double) -> (blue: Double, red: Double) {
        let brightest = max(red, green, blue)
        let lit = min(max((brightest - darkest) / (fullyLit - darkest), 0), 1)
        let scale = 1 + lit * (1 / max(brightest, darkest) - 1)
        return chroma(red: red * scale, green: green * scale, blue: blue * scale)
    }

    private static func chroma(red: Double, green: Double, blue: Double) -> (blue: Double, red: Double) {
        (
            red * Chroma.blueDifference.red + green * Chroma.blueDifference.green + blue * Chroma.blueDifference.blue,
            red * Chroma.redDifference.red + green * Chroma.redDifference.green + blue * Chroma.redDifference.blue
        )
    }

    /// How far a distance has got across a band, from 0 to 1, eased. With
    /// no band at all the answer is all or nothing.
    private static func share(of distance: Double, across band: Double) -> Double {
        guard band > 0 else { return distance > 0 ? 1 : 0 }
        return pow(min(max(distance / band, 0), 1), easing)
    }
}
