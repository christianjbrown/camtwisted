import XCTest
@testable import CamTwistCore

/// Hands out a fixed list of numbers, then zeros.
private struct ScriptedRandom: RandomSource {
    var values: [UInt32]

    mutating func next() -> UInt32 {
        values.isEmpty ? 0 : values.removeFirst()
    }
}

final class RandomSourceTests: XCTestCase {
    func testXorShiftRepeatsForASeedAndNeverSticksAtZero() {
        var first = XorShiftRandom(seed: 42)
        var second = XorShiftRandom(seed: 42)
        var zeroSeeded = XorShiftRandom(seed: 0)
        let numbers = (0..<5).map { _ in first.next() }

        XCTAssertEqual(numbers, (0..<5).map { _ in second.next() })
        XCTAssertEqual(Set(numbers).count, 5)
        XCTAssertNotEqual(zeroSeeded.next(), 0)
    }

    func testBelowStaysUnderItsBound() {
        var random = ScriptedRandom(values: [17, 5])
        XCTAssertEqual(random.below(10), 7)
        XCTAssertEqual(random.below(0), 0)
        XCTAssertEqual(random.below(10), 5)
    }
}

final class ImageAnalysisTests: XCTestCase {
    func testLuminanceWeighsTheChannels() {
        let rgba: [UInt8] = [255, 255, 255, 255, 0, 0, 0, 255, 255, 0, 0, 255, 0, 255, 0, 255]
        let grid = ImageAnalysis.luminance(rgba: rgba, width: 2, height: 2)
        XCTAssertEqual(grid.values, [255, 0, 76, 149])
    }

    func testEdgesAreBrightWhereBrightnessJumps() {
        var grid = ByteGrid(width: 5, height: 5)
        for y in 0..<5 {
            for x in 3..<5 { grid[x, y] = 255 }
        }
        let edges = ImageAnalysis.edges(of: grid)

        XCTAssertEqual(edges[2, 2], 255)
        XCTAssertEqual(edges[3, 2], 255)
        XCTAssertEqual(edges[1, 2], 0)
        XCTAssertEqual(edges[0, 2], 0, "the border has no full neighbourhood")
        XCTAssertEqual(edges[2, 0], 0)
    }

    func testAGridTooSmallForEdgesHasNone() {
        let grid = ByteGrid(width: 2, height: 2, values: [0, 255, 255, 0])
        XCTAssertEqual(ImageAnalysis.edges(of: grid), ByteGrid(width: 2, height: 2))
    }
}

final class FlameSimulationTests: XCTestCase {
    func testFuelHeatsItsCellWhichKeepsAShare() {
        var flame = FlameSimulation(width: 3, height: 20)
        var fuel = ByteGrid(width: 3, height: 20)
        fuel[1, 2] = 255
        // 60 fuel cells each take one number; only the fuelled one can use it.
        var random = ScriptedRandom(values: [UInt32](repeating: 15, count: 60) + [UInt32](repeating: 20, count: 5))

        flame.step(fuel: fuel, random: &random)

        XCTAssertEqual(flame.heat(x: 1, y: 2), 5, "keeps 99/256 of its 15")
        XCTAssertEqual(flame.heat(x: 0, y: 2), 0, "too little to spread sideways")
        XCTAssertEqual(flame.heat(x: 1, y: 10), 0)
    }

    func testSteadyFuelMakesAFlameThatRisesAndThins() {
        var flame = FlameSimulation(width: 3, height: 20)
        var fuel = ByteGrid(width: 3, height: 20)
        fuel[1, 10] = 255
        for _ in 0..<10 {
            var random = ScriptedRandom(values: [UInt32](repeating: 15, count: 60) + [UInt32](repeating: 20, count: 5))
            flame.step(fuel: fuel, random: &random)
        }

        XCTAssertGreaterThan(flame.heat(x: 1, y: 9), 0, "heat climbs above the fuel")
        XCTAssertGreaterThan(flame.heat(x: 1, y: 10), flame.heat(x: 1, y: 9))
        XCTAssertEqual(flame.heat(x: 1, y: 11), 0, "and never sinks below it")
        XCTAssertEqual(flame.heat(x: 1, y: 2), 0)
    }

    func testTheBaseFlickersAndHeatClimbsFromIt() {
        var flame = FlameSimulation(width: 4, height: 8)
        var random = ScriptedRandom(values: [])
        // With zeros for chance the base row cools by the trend, which wraps
        // round to hot: the simulation's bytes are meant to wrap.
        flame.step(fuel: ByteGrid(width: 4, height: 8), random: &random)

        XCTAssertGreaterThan(flame.heat(x: 2, y: 7), 0)
        XCTAssertGreaterThan(flame.heat(x: 2, y: 7), flame.heat(x: 2, y: 5))
        XCTAssertEqual(flame.heat(x: 2, y: 0), 0)
    }

    func testHeatNeverPassesTheMaximum() {
        var flame = FlameSimulation(width: 2, height: 2, settings: FlameSettings(
            horizontalSpread: 255, verticalSpread: 255, residual: 400, variance: 1, varianceTrend: -200
        ))
        var random = ScriptedRandom(values: [])
        for _ in 0..<5 {
            flame.step(fuel: ByteGrid(width: 2, height: 2), random: &random)
        }
        XCTAssertEqual(flame.heat(x: 0, y: 1), 255)
        XCTAssertEqual(flame.heat(x: 1, y: 0), 255)
    }

    func testFlaresBoostEachSpreadAndSettleBack() {
        func settings(afterRoll roll: UInt32, boost: UInt32) -> FlameSettings {
            var flame = FlameSimulation(width: 1, height: 1, settings: FlameSettings(flares: true))
            // One number for the fuel cell, three for the base row, then the roll.
            var random = ScriptedRandom(values: [0, 0, 0, 0, roll, boost])
            flame.step(fuel: ByteGrid(width: 1, height: 1), random: &random)
            return flame.settings
        }

        XCTAssertEqual(settings(afterRoll: 10, boost: 9).residual, 107)
        XCTAssertEqual(settings(afterRoll: 20, boost: 19).verticalSpread, 114)
        XCTAssertEqual(settings(afterRoll: 30, boost: 14).horizontalSpread, 42)
        XCTAssertEqual(settings(afterRoll: 55, boost: 0), FlameSettings(flares: true))
    }

    func testPaletteRunsFromClearThroughRedAndYellowToWhite() {
        XCTAssertTrue(FlamePalette.color(forHeat: 0) == (0, 0, 0, 0))
        XCTAssertTrue(FlamePalette.color(forHeat: 30) == (180, 0, 0, 60))
        XCTAssertTrue(FlamePalette.color(forHeat: 50) == (255, 60, 0, 105))
        XCTAssertTrue(FlamePalette.color(forHeat: 100) == (255, 255, 120, 210))
        XCTAssertTrue(FlamePalette.color(forHeat: 255) == (255, 255, 255, 255))
    }

    func testPictureIsOnePixelPerCell() {
        var flame = FlameSimulation(width: 2, height: 3)
        var fuel = ByteGrid(width: 2, height: 3)
        fuel[1, 0] = 255
        var random = ScriptedRandom(values: [0, 15] + [UInt32](repeating: 20, count: 20))
        flame.step(fuel: fuel, random: &random)

        let picture = FlamePalette.picture(of: flame)

        XCTAssertEqual(picture.count, 2 * 3 * 4)
        XCTAssertEqual(Array(picture[4..<8]), [30, 0, 0, 10], "the fuelled cell at (1, 0) glows faintly red")
        XCTAssertEqual(Array(picture[0..<4]), [0, 0, 0, 0])
    }
}

final class MatrixFontTests: XCTestCase {
    func testAFontKeepsItsGlyphs() {
        let font = MatrixFont(glyphCount: 2, glyphSize: 1, levels: [3, 1])
        XCTAssertEqual(font.glyphCount, 2)
        XCTAssertEqual(font.glyphSize, 1)
        XCTAssertEqual(font.levels, [3, 1])
        XCTAssertEqual(MatrixFont.levelCount, 4)
    }
}

final class MatrixPaletteTests: XCTestCase {
    func testGreenBrightensIntoWhite() {
        XCTAssertTrue(MatrixPalette.green(0) == (0, 0, 0))
        XCTAssertTrue(MatrixPalette.green(-5) == (0, 0, 0))
        XCTAssertTrue(MatrixPalette.green(100) == (45, 100, 45))
        XCTAssertTrue(MatrixPalette.green(300) == (186, 255, 186))
        XCTAssertTrue(MatrixPalette.green(900) == (255, 255, 255))
    }

    func testLevelsScaleWithTheCellsBrightness() {
        XCTAssertTrue(MatrixPalette.color(brightness: 170, level: 3) == (114, 255, 114))
        XCTAssertTrue(MatrixPalette.color(brightness: 170, level: 0) == (0, 0, 0))
        XCTAssertTrue(MatrixPalette.color(brightness: 85, level: 1) == (15, 34, 15))
    }
}

final class MatrixRainTests: XCTestCase {
    private let startFalling: UInt32 = 0xF0
    private let startSliding: UInt32 = 0xF000

    func testABlipFallsDownItsColumnLeavingAFadingTrail() {
        var rain = MatrixRain(columns: 1, rows: 3, glyphCount: 80)
        var random = ScriptedRandom(values: [startFalling, 7, 0, 9, 0, 11, 0])

        rain.update(random: &random)
        XCTAssertEqual(rain.glow(column: 0, row: 0), 0, "the blip only starts on this step")

        rain.update(random: &random)
        XCTAssertEqual(rain.glow(column: 0, row: 0), 244)
        XCTAssertEqual(rain.glyph(column: 0, row: 0), 7)

        rain.update(random: &random)
        XCTAssertEqual(rain.glow(column: 0, row: 0), 219, "the trail fades by a tenth")
        XCTAssertEqual(rain.glow(column: 0, row: 1), 244)
        XCTAssertEqual(rain.glyph(column: 0, row: 1), 9)

        rain.update(random: &random)
        XCTAssertEqual(rain.glyph(column: 0, row: 2), 11)
        rain.update(random: &random)
        XCTAssertEqual(rain.glow(column: 0, row: 2), 219, "the blip is done, so the last cell fades too")
    }

    func testAFastBlipCoversSeveralRowsAStep() {
        var rain = MatrixRain(columns: 1, rows: 5, glyphCount: 80)
        // The top two bits make the speed 4.
        var random = ScriptedRandom(values: [0xC000_00F0, 1, 2, 3, 4, 0])
        rain.update(random: &random)
        rain.update(random: &random)

        XCTAssertEqual((0..<5).map { rain.glow(column: 0, row: $0) }, [214, 224, 234, 244, 0])
        XCTAssertEqual((0..<4).map { rain.glyph(column: 0, row: $0) }, [1, 2, 3, 4])
    }

    func testAStickyBlipLeavesCellsThatDoNotFade() {
        var rain = MatrixRain(columns: 1, rows: 30, glyphCount: 80)
        // After its first step the blip rolls a sticky timer of 8.
        var random = ScriptedRandom(values: [startFalling, 0, 0x3F00])
        rain.update(random: &random)
        rain.update(random: &random)
        for _ in 0..<8 { rain.update(random: &random) }

        XCTAssertEqual(rain.glow(column: 0, row: 1), 255)
        XCTAssertEqual(rain.glow(column: 0, row: 8), 255)
        rain.update(random: &random)
        XCTAssertEqual(rain.glow(column: 0, row: 1), 255, "sticky cells stay lit")
        XCTAssertEqual(rain.glow(column: 0, row: 9), 244, "the timer has run out")
    }

    func testABlipCanStopForAWhileThenCarryOn() {
        var rain = MatrixRain(columns: 1, rows: 40, glyphCount: 80)
        // Speed 2, then a roll that stops it for 30 steps.
        var random = ScriptedRandom(values: [0x4000_00F0, 0, 0, 0x7F])
        rain.update(random: &random)
        rain.update(random: &random)
        XCTAssertEqual(rain.glow(column: 0, row: 1), 244)

        for _ in 0..<31 { rain.update(random: &random) }
        XCTAssertEqual(rain.glow(column: 0, row: 2), 254, "held bright where it stopped")
        XCTAssertEqual(rain.glow(column: 0, row: 3), 0)

        rain.update(random: &random)
        XCTAssertEqual(rain.glow(column: 0, row: 3), 244, "falling again")
    }

    func testASlidingColumnMovesItsGlyphsDown() {
        var rain = MatrixRain(columns: 1, rows: 4, glyphCount: 80)
        var random = ScriptedRandom(values: [startSliding, 5, 6, 7, 8])
        rain.update(random: &random)

        rain.update(random: &random)
        XCTAssertEqual((0..<4).map { rain.glyph(column: 0, row: $0) }, [5, 6, 0, 0])

        rain.update(random: &random)
        XCTAssertEqual((0..<4).map { rain.glyph(column: 0, row: $0) }, [7, 8, 5, 6])

        // The slide lasts 15 steps, then the column is idle and can start a blip.
        for _ in 0..<14 { rain.update(random: &random) }
        random = ScriptedRandom(values: [startFalling, 9, 0])
        rain.update(random: &random)
        rain.update(random: &random)
        XCTAssertEqual(rain.glow(column: 0, row: 0), 244)
    }

    func testASlideLongerThanTheColumnReplacesAllOfIt() {
        var rain = MatrixRain(columns: 1, rows: 1, glyphCount: 80)
        var random = ScriptedRandom(values: [startSliding, 5, 6])
        rain.update(random: &random)
        rain.update(random: &random)
        XCTAssertEqual(rain.glyph(column: 0, row: 0), 5)
    }

    func testPictureLightsGlyphsWithTheCamerasBrightness() {
        let font = MatrixFont(glyphCount: 1, glyphSize: 2, levels: [3, 0, 1, 2])
        let rain = MatrixRain(columns: 2, rows: 1, glyphCount: 1)
        var random = ScriptedRandom(values: [0])

        let picture = rain.picture(
            brightness: ByteGrid(width: 2, height: 1, values: [170, 255]), font: font, random: &random
        )

        XCTAssertEqual(picture.count, 4 * 2 * 4)
        XCTAssertEqual(Array(picture[0..<4]), [114, 255, 114, 255], "full level at brightness 170")
        XCTAssertEqual(Array(picture[4..<8]), [0, 0, 0, 255], "an off pixel is black")
        XCTAssertEqual(Array(picture[8..<12]), [108, 240, 108, 255], "a fully bright cell sparkles instead")
        XCTAssertEqual(Array(picture[16..<20]), [30, 68, 30, 255], "second row, level 1")
    }

    func testBrightnessFavoursRedAndGreen() {
        let rgba: [UInt8] = [10, 20, 128, 255, 200, 200, 0, 255]
        XCTAssertEqual(MatrixRain.brightness(rgba: rgba, width: 2, height: 1).values, [62, 255])
    }
}
