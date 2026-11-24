import Foundation

/// A grid of single byte values: brightness, edge strength and the like.
public struct ByteGrid: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var values: [UInt8]

    public init(width: Int, height: Int, values: [UInt8]) {
        // The values must fill the grid exactly.
        precondition(values.count == width * height)
        self.width = width
        self.height = height
        self.values = values
    }

    public init(width: Int, height: Int) {
        self.init(width: width, height: height, values: [UInt8](repeating: 0, count: width * height))
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        get { values[y * width + x] }
        set { values[y * width + x] = newValue }
    }
}

public enum ImageAnalysis {
    /// Bytes per pixel of the red, green, blue, alpha pictures used here.
    public static let bytesPerPixel = 4
    /// Where each channel sits within one pixel.
    public static let redOffset = 0
    public static let greenOffset = 1
    public static let blueOffset = 2
    public static let alphaOffset = 3

    /// How bright each pixel of an RGBA picture looks.
    public static func luminance(rgba: [UInt8], width: Int, height: Int) -> ByteGrid {
        var grid = ByteGrid(width: width, height: height)
        for index in 0..<(width * height) {
            let offset = index * bytesPerPixel
            let weighted = Int(rgba[offset + redOffset]) * redWeight
                + Int(rgba[offset + greenOffset]) * greenWeight
                + Int(rgba[offset + blueOffset]) * blueWeight
            grid.values[index] = UInt8(weighted >> weightShift)
        }
        return grid
    }

    /// Sobel edge strength: bright where brightness changes sharply. The
    /// outermost pixels have no full neighbourhood and stay at zero.
    public static func edges(of grid: ByteGrid) -> ByteGrid {
        var result = ByteGrid(width: grid.width, height: grid.height)
        guard grid.width > 2, grid.height > 2 else { return result }
        for y in 1..<(grid.height - 1) {
            for x in 1..<(grid.width - 1) {
                func value(_ dx: Int, _ dy: Int) -> Int { Int(grid[x + dx, y + dy]) }
                let horizontal = value(1, -1) + centreWeight * value(1, 0) + value(1, 1)
                    - value(-1, -1) - centreWeight * value(-1, 0) - value(-1, 1)
                let vertical = value(-1, 1) + centreWeight * value(0, 1) + value(1, 1)
                    - value(-1, -1) - centreWeight * value(0, -1) - value(1, -1)
                result[x, y] = UInt8(min(abs(horizontal) + abs(vertical), Int(UInt8.max)))
            }
        }
        return result
    }

    /// The Sobel kernel counts the pixel in line with the centre double.
    private static let centreWeight = 2

    // Standard luma weights, scaled to sum to 256.
    private static let redWeight = 77
    private static let greenWeight = 150
    private static let blueWeight = 29
    private static let weightShift = 8
}
