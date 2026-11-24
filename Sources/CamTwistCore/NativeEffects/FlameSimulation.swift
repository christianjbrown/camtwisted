import Foundation

/// How the fire spreads. The numbers are xflame's.
public struct FlameSettings: Equatable, Sendable {
    /// Share of a cell's heat passed sideways each step, out of 256.
    public var horizontalSpread: Int
    /// Share passed upwards each step, out of 256.
    public var verticalSpread: Int
    /// Share a cell keeps for itself each step, out of 256.
    public var residual: Int
    /// Size of the random flicker along the bottom row.
    public var variance: Int
    /// How far that flicker leans towards cooling.
    public var varianceTrend: Int
    /// Let the spread flare up at random and settle back.
    public var flares: Bool

    /// The numbers xflame uses.
    public enum Standard {
        public static let horizontalSpread = 30
        public static let verticalSpread = 97
        public static let residual = 99
        public static let variance = 50
        public static let varianceTrend = 20
    }

    public init(
        horizontalSpread: Int = Standard.horizontalSpread,
        verticalSpread: Int = Standard.verticalSpread,
        residual: Int = Standard.residual,
        variance: Int = Standard.variance,
        varianceTrend: Int = Standard.varianceTrend,
        flares: Bool = false
    ) {
        self.horizontalSpread = horizontalSpread
        self.verticalSpread = verticalSpread
        self.residual = residual
        self.variance = variance
        self.varianceTrend = varianceTrend
        self.flares = flares
    }
}

/// The classic rising fire: every cell passes heat to the cells above and
/// beside it and keeps a little. Fuel is added wherever the caller says,
/// which for the effect is along the edges in the picture.
public struct FlameSimulation {
    private enum Fuel {
        /// Turns an edge strength of 0 to 255 into a fuel range of 1 to 16.
        static let multiplier = 241
        static let shift = 12
    }

    private enum Flare {
        /// One step in this many may flare each kind of spread.
        static let odds = 100
        static let residualRoll = 10
        static let verticalRoll = 20
        static let horizontalRoll = 30
        static let residualBoost = 10
        static let verticalBoost = 20
        static let horizontalBoost = 15
        /// Each step a flared value keeps this share and moves the rest of
        /// the way back to where it started.
        static let keptShare = 90
        static let restoredShare = 10
        static let shareTotal = 100
    }

    private static let spreadShift = 8
    /// Heat spreads to each target at this fraction of the share that moves.
    private static let spreadDivisor = 2
    /// The spare cells around the picture: one each side across, one above and one below.
    private static let borderCells = 2
    /// How many rows up the farthest cell that is warmed sits.
    private static let farUpwardRows = 2
    private static let maximumHeat = Int(UInt8.max)

    public let width: Int
    public let height: Int
    private let rowLength: Int
    private let baseline: FlameSettings
    /// The settings as they stand now, which flares push about.
    public private(set) var settings: FlameSettings
    private var cells: [UInt8]

    public init(width: Int, height: Int, settings: FlameSettings = FlameSettings()) {
        self.width = width
        self.height = height
        self.settings = settings
        baseline = settings
        // One spare cell on each side, a spare row above the picture for heat
        // to spill into, and the base row below it that feeds the fire.
        rowLength = width + Self.borderCells
        cells = [UInt8](repeating: 0, count: rowLength * (height + Self.borderCells))
    }

    /// The heat of one cell of the picture, 0 to 255.
    public func heat(x: Int, y: Int) -> UInt8 {
        cells[(y + 1) * rowLength + x + 1]
    }

    /// Advances the fire one step. `fuel` is as large as the picture.
    public mutating func step<Random: RandomSource>(fuel: ByteGrid, random: inout Random) {
        add(fuel, random: &random)
        flicker(random: &random)
        if settings.flares {
            flare(random: &random)
        }
        advance()
    }

    private mutating func add<Random: RandomSource>(_ fuel: ByteGrid, random: inout Random) {
        for y in 0..<min(height, fuel.height) {
            for x in 0..<min(width, fuel.width) {
                let range = ((Int(fuel[x, y]) * Fuel.multiplier) >> Fuel.shift) + 1
                cells[(y + 1) * rowLength + x + 1] &+= UInt8(random.below(range))
            }
        }
    }

    /// Random heat along the row below the picture keeps the base alive.
    private mutating func flicker<Random: RandomSource>(random: inout Random) {
        let row = (height + 1) * rowLength
        for x in 0..<rowLength {
            let change = random.below(settings.variance) - settings.varianceTrend
            cells[row + x] = UInt8(truncatingIfNeeded: Int(cells[row + x]) + change)
        }
    }

    private mutating func flare<Random: RandomSource>(random: inout Random) {
        switch random.below(Flare.odds) {
        case Flare.residualRoll: settings.residual += random.below(Flare.residualBoost)
        case Flare.verticalRoll: settings.verticalSpread += random.below(Flare.verticalBoost)
        case Flare.horizontalRoll: settings.horizontalSpread += random.below(Flare.horizontalBoost)
        default: break
        }
        func settle(_ value: Int, towards start: Int) -> Int {
            (value * Flare.keptShare + start * Flare.restoredShare) / Flare.shareTotal
        }
        settings.residual = settle(settings.residual, towards: baseline.residual)
        settings.horizontalSpread = settle(settings.horizontalSpread, towards: baseline.horizontalSpread)
        settings.verticalSpread = settle(settings.verticalSpread, towards: baseline.verticalSpread)
    }

    private mutating func advance() {
        for y in stride(from: height + 1, through: 1, by: -1) {
            for x in stride(from: width, through: 1, by: -1) {
                let index = y * rowLength + x
                let heat = Int(cells[index])
                guard heat > 0 else { continue }
                let upward = ((heat * settings.verticalSpread) >> Self.spreadShift) / Self.spreadDivisor
                warm(index - Self.farUpwardRows * rowLength, by: upward)
                warm(index - rowLength, by: upward)
                let sideways = ((heat * settings.horizontalSpread) >> Self.spreadShift) / Self.spreadDivisor
                warm(index - rowLength - 1, by: sideways)
                warm(index - rowLength + 1, by: sideways)
                warm(index - 1, by: sideways)
                warm(index + 1, by: sideways)
                cells[index] = UInt8(min((heat * settings.residual) >> Self.spreadShift, Self.maximumHeat))
            }
        }
    }

    private mutating func warm(_ index: Int, by amount: Int) {
        guard index >= 0 else { return }
        cells[index] = UInt8(min(Int(cells[index]) + amount, Self.maximumHeat))
    }
}

/// Turns heat into fire colours: black, through red and yellow, to white.
/// The ramp is xflame's, read out of its palette routine.
public enum FlamePalette {
    private static let rampSlope = 6
    private static let greenStart = 40
    private static let blueStart = 80
    private static let channelCount = 3

    /// Red, green, blue and alpha for a heat. Alpha is the average of the
    /// three colours, which is less than the brightest of them: laid over a
    /// picture, the fire adds its light to what is behind it and only
    /// white-hot fire hides it completely.
    public static func color(forHeat heat: UInt8) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        func ramp(from start: Int) -> Int {
            min(max((Int(heat) - start) * rampSlope, 0), Int(UInt8.max))
        }
        let (red, green, blue) = (ramp(from: 0), ramp(from: greenStart), ramp(from: blueStart))
        return (UInt8(red), UInt8(green), UInt8(blue), UInt8((red + green + blue) / channelCount))
    }

    /// The whole fire as an RGBA picture, first row at the top.
    public static func picture(of simulation: FlameSimulation) -> [UInt8] {
        var pixels = [UInt8](
            repeating: 0, count: simulation.width * simulation.height * ImageAnalysis.bytesPerPixel
        )
        for y in 0..<simulation.height {
            for x in 0..<simulation.width {
                let color = color(forHeat: simulation.heat(x: x, y: y))
                let offset = (y * simulation.width + x) * ImageAnalysis.bytesPerPixel
                pixels[offset + ImageAnalysis.redOffset] = color.red
                pixels[offset + ImageAnalysis.greenOffset] = color.green
                pixels[offset + ImageAnalysis.blueOffset] = color.blue
                pixels[offset + ImageAnalysis.alphaOffset] = color.alpha
            }
        }
        return pixels
    }
}
