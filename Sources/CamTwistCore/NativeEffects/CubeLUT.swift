import Foundation

/// A colour look-up table read from a `.cube` file, the format colour
/// grading tools share: for every colour in, the colour that comes out.
public struct CubeLUT: Equatable, Sendable {
    /// The largest table Core Image's colour cube takes on each side.
    public static let largestSize = 64

    private enum Keyword {
        static let size = "LUT_3D_SIZE"
        static let comment: Character = "#"
    }

    private static let channels = 3
    private static let opaque: Float = 1

    /// How many steps each of red, green and blue is cut into.
    public let size: Int
    /// The colours out, as red, green, blue and opacity, with red changing
    /// fastest, then green, then blue.
    public let values: [Float]

    public init(size: Int, values: [Float]) {
        self.size = size
        self.values = values
    }

    /// Reads a `.cube` file's text. Nil when it has no size, the wrong
    /// number of colours for its size, or a colour that is not three numbers.
    public init?(text: String) {
        var size: Int?
        var values: [Float] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: \.isWhitespace)
            guard let first = words.first, first.first != Keyword.comment else { continue }
            if first == Keyword.size {
                size = words.dropFirst().first.flatMap { Int($0) }
            } else if Float(first) != nil {
                // A line that starts with a number is a colour.
                let colour = words.compactMap { Float($0) }
                guard colour.count == Self.channels, words.count == Self.channels else { return nil }
                values += colour + [Self.opaque]
            }
            // Any other keyword (a title, a range) changes nothing here.
        }
        guard let size, size > 1, values.count == size * size * size * (Self.channels + 1) else { return nil }
        self.init(size: size, values: values)
    }

    /// The table cut down to a size Core Image takes, by keeping the
    /// nearest entries. A table already small enough is handed back as it is.
    public var fittingCoreImage: CubeLUT {
        guard size > Self.largestSize else { return self }
        let small = Self.largestSize
        let stride = Self.channels + 1
        var fitted: [Float] = []
        fitted.reserveCapacity(small * small * small * stride)
        func nearest(_ index: Int) -> Int {
            Int((Double(index) * Double(size - 1) / Double(small - 1)).rounded())
        }
        for blue in 0..<small {
            for green in 0..<small {
                for red in 0..<small {
                    let at = ((nearest(blue) * size + nearest(green)) * size + nearest(red)) * stride
                    fitted += values[at..<at + stride]
                }
            }
        }
        return CubeLUT(size: small, values: fitted)
    }
}
