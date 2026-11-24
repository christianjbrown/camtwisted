import CoreGraphics
import Foundation

/// A colour as plain red, green and blue amounts between 0 and 1.
public struct RGBColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// The colour bar test pattern: the camera's idle picture and a built-in
/// source in the app.
public enum ColorBars {
    private static let level = 0.75

    /// The seven bars of the standard pattern, left to right.
    public static let colors: [RGBColor] = [
        RGBColor(red: level, green: level, blue: level),
        RGBColor(red: level, green: level, blue: 0),
        RGBColor(red: 0, green: level, blue: level),
        RGBColor(red: 0, green: level, blue: 0),
        RGBColor(red: level, green: 0, blue: level),
        RGBColor(red: level, green: 0, blue: 0),
        RGBColor(red: 0, green: 0, blue: level),
    ]

    /// The frame of each bar on a canvas, left to right, with its colour.
    public static func bars(in canvas: CGSize) -> [(frame: CGRect, color: RGBColor)] {
        let width = canvas.width / CGFloat(colors.count)
        return colors.enumerated().map { index, color in
            (CGRect(x: CGFloat(index) * width, y: 0, width: width, height: canvas.height), color)
        }
    }
}
