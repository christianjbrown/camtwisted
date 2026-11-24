import Foundation

/// The glyphs the rain is made of: square pictures whose pixels each hold
/// one of four brightness levels.
public struct MatrixFont: Equatable, Sendable {
    /// Brightness levels a glyph pixel can have, from off to full.
    public static let levelCount = 4

    public let glyphCount: Int
    /// Width and height of one glyph in pixels.
    public let glyphSize: Int
    /// Every glyph's pixels, glyph after glyph, row after row.
    public let levels: [UInt8]

    public init(glyphCount: Int, glyphSize: Int, levels: [UInt8]) {
        // The levels must fill every glyph exactly.
        precondition(levels.count == glyphCount * glyphSize * glyphSize)
        self.glyphCount = glyphCount
        self.glyphSize = glyphSize
        self.levels = levels
    }
}

/// The green of the rain, brightening into white at the top end.
public enum MatrixPalette {
    /// How much red and blue ride along with the green.
    private static let whiteShare = 0.45
    private static let fullChannel = 255
    /// Brightness at which a level reaches its full value.
    private static let fullBrightness = 170
    /// The peak value of each glyph level, from off to full.
    private static let levelPeaks = [0x00, 0x44, 0x99, 0xFF]

    /// Red, green and blue for a strength that may run past 255.
    public static func green(_ strength: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        if strength <= fullChannel {
            let green = max(strength, 0)
            let side = UInt8(Double(green) * whiteShare)
            return (side, UInt8(green), side)
        }
        let side = UInt8(min(strength - Int(Double(fullChannel) * whiteShare), fullChannel))
        return (side, UInt8(fullChannel), side)
    }

    /// The colour of a glyph pixel at a level, for a cell of a brightness.
    public static func color(brightness: UInt8, level: UInt8) -> (red: UInt8, green: UInt8, blue: UInt8) {
        green(levelPeaks[Int(level)] * Int(brightness) / fullBrightness)
    }
}

/// The falling code: a grid of glyphs, with a bright blip running down each
/// column now and then. The picture's own brightness lights the glyphs, so
/// what is in front of the camera shows through as code.
public struct MatrixRain {
    private enum BlipMode {
        case idle
        case falling
        case stopped
        case sliding
    }

    private struct Blip {
        var mode = BlipMode.idle
        var row = 0
        var timer = 0
        var speed = 0
    }

    private enum Tuning {
        /// A lit trail fades to this share each step.
        static let fadeNumerator = 9
        static let fadeDenominator = 10
        /// A cell at this value is "sticky": it sparkles instead of fading.
        static let sticky: UInt8 = 255
        static let trailHead = 254
        static let trailStep = 10
        static let sparkleFloor = 160
        static let stopBrightness: UInt8 = 254
        /// A roll with all these bits set starts a falling blip.
        static let fallChanceMask: UInt32 = 0xF0
        /// A roll with all these bits set starts a sliding column.
        static let slideChanceMask: UInt32 = 0x0F000
        /// A roll with all these bits set puts a falling blip into its sticky stretch.
        static let stickyChanceMask: UInt32 = 0x3F00
        /// A roll with all these bits set makes a fast blip stop.
        static let stopChanceMask: UInt32 = 0x7F
        /// The top two bits of the roll pick a falling blip's speed.
        static let fallSpeedShift = 30
        static let minimumFallSpeed = 1
        /// The top four bits of the roll pick how long a slide lasts.
        static let slideTimerShift = 28
        static let minimumSlideTimer = 15
        /// Two bits from the middle of the roll pick a slide's speed.
        static let slideSpeedShift = 24
        static let slideSpeedMask: UInt32 = 3
        static let minimumSlideSpeed = 2
        /// The top four bits of the roll pick how long the sticky stretch lasts.
        static let stickyTimerShift = 28
        static let minimumStickyTimer = 8
        /// The top six bits of the roll pick how long a stop lasts.
        static let stopTimerShift = 26
        static let minimumStopTimer = 30
        /// The sparkle takes the top byte of a roll.
        static let sparkleShift = 24
        /// Brightness drops the blue share by this many bits.
        static let blueShift = 6
        /// Red and green each count this many times in the brightness.
        static let redGreenWeight = 2
    }

    public let columns: Int
    public let rows: Int
    private let glyphCount: Int
    private var glyphs: [UInt8]
    private var glow: [UInt8]
    private var blips: [Blip]

    public init(columns: Int, rows: Int, glyphCount: Int) {
        self.columns = columns
        self.rows = rows
        self.glyphCount = glyphCount
        glyphs = [UInt8](repeating: 0, count: columns * rows)
        glow = [UInt8](repeating: 0, count: columns * rows)
        blips = [Blip](repeating: Blip(), count: columns)
    }

    /// The glyph shown in a cell.
    public func glyph(column: Int, row: Int) -> UInt8 { glyphs[row * columns + column] }

    /// How brightly the rain itself lights a cell, before the picture is added.
    public func glow(column: Int, row: Int) -> UInt8 { glow[row * columns + column] }

    /// Moves the rain on by one step.
    public mutating func update<Random: RandomSource>(random: inout Random) {
        for column in 0..<columns {
            fade(column)
            switch blips[column].mode {
            case .idle: idle(column, random: &random)
            case .falling: fall(column, random: &random)
            case .stopped: stop(column, random: &random)
            case .sliding: slide(column, random: &random)
            }
        }
    }

    private mutating func fade(_ column: Int) {
        for row in 0..<rows {
            let index = row * columns + column
            if glow[index] < Tuning.sticky {
                glow[index] = UInt8(Int(glow[index]) * Tuning.fadeNumerator / Tuning.fadeDenominator)
            }
        }
    }

    /// One random number decides whether a blip starts, and how.
    private mutating func idle<Random: RandomSource>(_ column: Int, random: inout Random) {
        let roll = random.next()
        if roll & Tuning.fallChanceMask == Tuning.fallChanceMask {
            blips[column] = Blip(
                mode: .falling, row: 0, timer: 0,
                speed: Int(roll >> Tuning.fallSpeedShift) + Tuning.minimumFallSpeed
            )
        } else if roll & Tuning.slideChanceMask == Tuning.slideChanceMask {
            blips[column].mode = .sliding
            blips[column].timer = Int(roll >> Tuning.slideTimerShift) + Tuning.minimumSlideTimer
            blips[column].speed = Int((roll >> Tuning.slideSpeedShift) & Tuning.slideSpeedMask)
                + Tuning.minimumSlideSpeed
        }
    }

    private mutating func fall<Random: RandomSource>(_ column: Int, random: inout Random) {
        var row = blips[column].row
        for step in stride(from: blips[column].speed, to: 0, by: -1) {
            let index = row * columns + column
            glow[index] = blips[column].timer > 0
                ? Tuning.sticky
                : UInt8(Tuning.trailHead - step * Tuning.trailStep)
            glyphs[index] = UInt8(random.below(glyphCount))
            row += 1
            if row >= rows { break }
        }
        if blips[column].timer > 0 {
            blips[column].timer -= 1
        }
        if row >= rows {
            blips[column].mode = .idle
        }
        blips[column].row = min(row, rows - 1)
        guard blips[column].timer == 0 else { return }
        let roll = random.next()
        if roll & Tuning.stickyChanceMask == Tuning.stickyChanceMask {
            blips[column].timer = Int(roll >> Tuning.stickyTimerShift) + Tuning.minimumStickyTimer
        } else if blips[column].speed > 1, roll & Tuning.stopChanceMask == Tuning.stopChanceMask {
            blips[column].mode = .stopped
            blips[column].timer = Int(roll >> Tuning.stopTimerShift) + Tuning.minimumStopTimer
        }
    }

    private mutating func stop<Random: RandomSource>(_ column: Int, random: inout Random) {
        let index = blips[column].row * columns + column
        glow[index] = Tuning.stopBrightness
        glyphs[index] = UInt8(random.below(glyphCount))
        blips[column].timer -= 1
        if blips[column].timer < 0 {
            blips[column].mode = .falling
        }
    }

    /// The whole column of glyphs slips down, with new ones at the top.
    private mutating func slide<Random: RandomSource>(_ column: Int, random: inout Random) {
        blips[column].timer -= 1
        if blips[column].timer < 0 {
            blips[column].mode = .idle
        }
        let distance = min(blips[column].speed, rows)
        for row in stride(from: rows - 1, through: distance, by: -1) {
            glyphs[row * columns + column] = glyphs[(row - distance) * columns + column]
        }
        for row in 0..<distance {
            glyphs[row * columns + column] = UInt8(random.below(glyphCount))
        }
    }

    /// Draws the rain as an RGBA picture, first row at the top. `brightness`
    /// is the camera picture shrunk to one value per cell.
    public func picture<Random: RandomSource>(
        brightness: ByteGrid,
        font: MatrixFont,
        random: inout Random
    ) -> [UInt8] {
        let size = font.glyphSize
        let width = columns * size
        var pixels = [UInt8](repeating: UInt8.max, count: width * rows * size * ImageAnalysis.bytesPerPixel)
        for row in 0..<rows {
            for column in 0..<columns {
                let cell = row * columns + column
                var strength = glow[cell] | brightness.values[cell]
                if strength == Tuning.sticky {
                    strength = UInt8(truncatingIfNeeded: Tuning.sparkleFloor + Int(random.next() >> Tuning.sparkleShift))
                }
                let glyphStart = Int(glyphs[cell]) % font.glyphCount * size * size
                for y in 0..<size {
                    for x in 0..<size {
                        let color = MatrixPalette.color(
                            brightness: strength, level: font.levels[glyphStart + y * size + x]
                        )
                        let offset = ((row * size + y) * width + column * size + x) * ImageAnalysis.bytesPerPixel
                        pixels[offset + ImageAnalysis.redOffset] = color.red
                        pixels[offset + ImageAnalysis.greenOffset] = color.green
                        pixels[offset + ImageAnalysis.blueOffset] = color.blue
                    }
                }
            }
        }
        return pixels
    }

    /// The brightness MatrixTV takes from a pixel: mostly red and
    /// green, with a trace of blue.
    public static func brightness(rgba: [UInt8], width: Int, height: Int) -> ByteGrid {
        var grid = ByteGrid(width: width, height: height)
        for index in 0..<(width * height) {
            let offset = index * ImageAnalysis.bytesPerPixel
            let red = Int(rgba[offset + ImageAnalysis.redOffset])
            let green = Int(rgba[offset + ImageAnalysis.greenOffset])
            let blue = Int(rgba[offset + ImageAnalysis.blueOffset])
            let value = (red + green) * Tuning.redGreenWeight + (blue >> Tuning.blueShift)
            grid.values[index] = UInt8(min(value, Int(UInt8.max)))
        }
        return grid
    }
}
