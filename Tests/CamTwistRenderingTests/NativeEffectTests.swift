import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

private let canvas = CGSize(width: 320, height: 180)

private func solid(_ color: CIColor, _ rect: CGRect) -> CIImage {
    CIImage(color: color).cropped(to: rect)
}

final class PixelAccessTests: XCTestCase {
    private let access = makePixelAccess()

    func testReadsTheTopRowFirst() {
        // Red across the top half, blue across the bottom half.
        let image = solid(.red, CGRect(x: 0, y: 90, width: 320, height: 90))
            .composited(over: solid(.blue, CGRect(origin: .zero, size: canvas)))

        let bytes = access.rgba(of: image, width: 32, height: 18)
        func pixel(x: Int, y: Int) -> [UInt8] { Array(bytes[(y * 32 + x) * 4..<(y * 32 + x) * 4 + 4]) }

        XCTAssertEqual(pixel(x: 16, y: 2), [255, 0, 0, 255], "the first rows are the top: red")
        XCTAssertEqual(pixel(x: 16, y: 15), [0, 0, 255, 255], "the last rows are the bottom: blue")
        XCTAssertEqual(pixel(x: 0, y: 0), [255, 0, 0, 255], "the corners stay solid")
    }

    func testAPictureMadeFromBytesReadsBackTheSame() {
        let bytes: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255]
        let image = access.image(rgba: bytes, width: 2, height: 2)

        XCTAssertEqual(image.extent, CGRect(x: 0, y: 0, width: 2, height: 2))
        XCTAssertEqual(access.rgba(of: image, width: 2, height: 2), bytes)
    }

    func testAnEmptyOrEndlessImageReadsAsNothing() {
        XCTAssertEqual(access.rgba(of: CIImage.empty(), width: 2, height: 1), [UInt8](repeating: 0, count: 8))
        XCTAssertEqual(access.rgba(of: CIImage(color: .red), width: 1, height: 1), [0, 0, 0, 0])
        XCTAssertEqual(CIImage.empty().stretched(to: canvas, smooth: true).extent.isNull, true)
        XCTAssertEqual(access.rgba(of: CIImage(color: .red), width: 0, height: 0), [])
    }
}

final class FlameEffectTests: XCTestCase {
    private let access = makePixelAccess()

    /// A white box on black: plenty of edge for the fire to catch on.
    private var box: CIImage {
        solid(.white, CGRect(x: 110, y: 40, width: 100, height: 60))
            .composited(over: solid(.black, CGRect(origin: .zero, size: canvas)))
    }

    private func burn(_ effect: FlameEffect, frames: Int) -> [UInt8] {
        var output = box
        for frame in 0..<frames {
            output = effect.apply(to: box, time: Double(frame) / 30)
        }
        return access.rgba(of: output, width: 320, height: 180)
    }

    private func pixel(_ bytes: [UInt8], x: Int, y: Int) -> [UInt8] {
        Array(bytes[(y * 320 + x) * 4..<(y * 320 + x) * 4 + 3])
    }

    func testFireRisesFromTheTopEdgeAndLeavesTheRestAlone() {
        let effect = FlameEffect(canvas: canvas, pixels: access, seed: 7)
        let bytes = burn(effect, frames: 40)

        // The box's top edge is at row 80 from the top; look just above it.
        let above = (120..<200).map { pixel(bytes, x: $0, y: 74) }
        XCTAssertTrue(above.contains { $0[0] > 60 && $0[0] > $0[2] }, "red glow above the top edge")
        XCTAssertEqual(pixel(bytes, x: 20, y: 20), [0, 0, 0], "no fire far from any edge")
        XCTAssertEqual(pixel(bytes, x: 160, y: 115), [255, 255, 255], "the middle of the box is untouched")
    }

    func testTheSameSeedBurnsTheSameWay() {
        let first = burn(FlameEffect(canvas: canvas, pixels: access, seed: 3), frames: 6)
        let second = burn(FlameEffect(canvas: canvas, pixels: access, seed: 3), frames: 6)
        XCTAssertEqual(first, second)
    }

    func testFlaresCanBeSwitchedOnAndOff() {
        let effect = FlameEffect(canvas: canvas, pixels: access, seed: 5)
        effect.setValues([FlameEffect.flaresKey: .boolean(true)])
        effect.setValues([FlameEffect.flaresKey: .boolean(true)])
        XCTAssertFalse(burn(effect, frames: 20).isEmpty)
        effect.setValues([:])
        XCTAssertFalse(burn(effect, frames: 2).isEmpty)
        XCTAssertEqual(FlameEffect.parameters.map(\.key), [FlameEffect.flaresKey])
    }
}

final class MatrixEffectTests: XCTestCase {
    private let access = makePixelAccess()
    private let font = DrawnMatrixFont.make()

    private func greenShare(of image: CIImage) -> (green: Int, other: Int) {
        let bytes = access.rgba(of: image, width: 160, height: 90)
        var green = 0
        var other = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            green += Int(bytes[index + 1])
            other += Int(bytes[index]) + Int(bytes[index + 2])
        }
        return (green, other)
    }

    private func fullStrength(seed: UInt32) -> MatrixEffect {
        let effect = MatrixEffect(canvas: canvas, pixels: access, font: font, seed: seed)
        effect.setValues([MatrixEffect.strengthKey: .number(1)])
        return effect
    }

    func testABrightPictureBecomesGreenCodeAndADarkOneStaysDark() {
        let bright = solid(CIColor(red: 0.08, green: 0.08, blue: 0.08), CGRect(origin: .zero, size: canvas))
        let dark = solid(.black, CGRect(origin: .zero, size: canvas))

        let lit = greenShare(of: fullStrength(seed: 1).apply(to: bright, time: 0))
        let unlit = greenShare(of: fullStrength(seed: 1).apply(to: dark, time: 0))

        XCTAssertGreaterThan(lit.green, lit.other, "the code is green")
        XCTAssertGreaterThan(lit.green, 50_000)
        XCTAssertLessThan(unlit.green, lit.green / 20)
    }

    func testTheRainFallsOverADarkPicture() {
        let dark = solid(.black, CGRect(origin: .zero, size: canvas))
        let effect = fullStrength(seed: 9)
        var output = dark
        for frame in 0..<60 {
            output = effect.apply(to: dark, time: Double(frame) / 30)
        }
        XCTAssertGreaterThan(greenShare(of: output).green, 5000, "blips light cells even with nothing on camera")
        XCTAssertEqual(output.extent, CGRect(origin: .zero, size: canvas))
    }

    func testStrengthSetsHowMuchOfThePictureShowsThrough() {
        let red = solid(.red, CGRect(origin: .zero, size: canvas))
        func redLeft(strength: EffectValue?) -> Int {
            let effect = MatrixEffect(canvas: canvas, pixels: access, font: font, seed: 2)
            effect.setValues(strength.map { [MatrixEffect.strengthKey: $0] } ?? [:])
            let bytes = access.rgba(of: effect.apply(to: red, time: 0), width: 16, height: 9)
            return stride(from: 0, to: bytes.count, by: 4).reduce(0) { $0 + Int(bytes[$1]) }
        }

        let none = redLeft(strength: .number(0))
        let byDefault = redLeft(strength: nil)
        let full = redLeft(strength: .number(1))

        XCTAssertEqual(none, 255 * 16 * 9, "at zero the picture is untouched")
        XCTAssertGreaterThan(byDefault, full, "by default the picture shows through")
        XCTAssertLessThan(byDefault, none)
        XCTAssertEqual(MatrixEffect.parameters.map(\.key), [MatrixEffect.strengthKey])
    }
}

final class DrawnMatrixFontTests: XCTestCase {
    func testDrawnFontHasInkInEveryGlyph() {
        let font = DrawnMatrixFont.make()
        let perGlyph = font.glyphSize * font.glyphSize

        XCTAssertGreaterThan(font.glyphCount, 60)
        XCTAssertEqual(font.levels.count, font.glyphCount * perGlyph)
        let inked = (0..<font.glyphCount).filter { glyph in
            font.levels[glyph * perGlyph..<(glyph + 1) * perGlyph].contains { $0 > 0 }
        }
        XCTAssertGreaterThan(inked.count, font.glyphCount * 9 / 10)
        XCTAssertTrue(font.levels.allSatisfy { $0 < MatrixFont.levelCount })
    }
}

final class BumpEffectTests: XCTestCase {
    private let access = makePixelAccess()

    /// Thin white vertical stripes on black: a bulge bends them.
    private var stripes: CIImage {
        (0..<16).reduce(solid(.black, CGRect(origin: .zero, size: canvas))) { image, index in
            solid(.white, CGRect(x: CGFloat(index) * 20 + 8, y: 0, width: 4, height: 180)).composited(over: image)
        }
    }

    private func changed(_ effect: BumpEffect, nearX x: Int) -> Int {
        let before = access.rgba(of: stripes, width: 320, height: 180)
        let after = access.rgba(of: effect.apply(to: stripes, time: 0), width: 320, height: 180)
        var count = 0
        for row in 60..<120 {
            for column in max(x - 30, 0)..<min(x + 30, 320) where before[(row * 320 + column) * 4] != after[(row * 320 + column) * 4] {
                count += 1
            }
        }
        return count
    }

    func testTheBulgeIsWhereItIsPut() {
        let effect = BumpEffect(canvas: canvas)
        effect.setValues([BumpEffect.xKey: .number(-0.6), BumpEffect.sizeKey: .number(0.3)])

        XCTAssertGreaterThan(changed(effect, nearX: 64), 200, "the picture bends around the bulge on the left")
        XCTAssertEqual(changed(effect, nearX: 280), 0, "and is untouched far away on the right")
    }

    func testDefaultsPutItInTheMiddleAndKeepThePictureSize() {
        let effect = BumpEffect(canvas: canvas)
        effect.setValues([:])
        XCTAssertGreaterThan(changed(effect, nearX: 160), 200)
        XCTAssertEqual(effect.apply(to: stripes, time: 0).extent, CGRect(origin: .zero, size: canvas))
        XCTAssertEqual(BumpEffect.parameters.map(\.displayName), ["X Position", "Y Position", "Size", "Amount"])
        XCTAssertTrue(NativeEffect.bump.make(canvas) is BumpEffect)
    }
}

final class TransformEffectTests: XCTestCase {
    private let access = makePixelAccess()

    /// Bars of colour with a white box, so every kind of change shows.
    private var scene: CIImage {
        solid(.white, CGRect(x: 200, y: 100, width: 80, height: 50))
            .composited(over: solid(.red, CGRect(x: 0, y: 0, width: 160, height: 180)))
            .composited(over: solid(.blue, CGRect(origin: .zero, size: canvas)))
    }

    private func changedPixels(_ output: CIImage) -> Int {
        let before = access.rgba(of: scene, width: 160, height: 90)
        let after = access.rgba(of: output, width: 160, height: 90)
        return stride(from: 0, to: before.count, by: 4).filter { index in
            (0..<3).contains { abs(Int(before[index + $0]) - Int(after[index + $0])) > 12 }
        }.count
    }

    func testBadTVDisturbsThePictureAndKeepsItsSize() {
        let effect = NativeEffect.badTV.make(canvas)
        let output = effect.apply(to: scene, time: 1.3)

        XCTAssertEqual(output.extent, CGRect(origin: .zero, size: canvas))
        XCTAssertGreaterThan(changedPixels(output), 1500)
        XCTAssertEqual(NativeEffect.badTV.parameters.map(\.displayName), [
            "Vertical Sync", "Line Sync", "Distortion", "Scan Lines", "Bars",
        ])
    }

    func testBadTVWithEverythingAtZeroLeavesThePictureAlone() {
        let effect = NativeEffect.badTV.make(canvas)
        effect.setValues(Dictionary(uniqueKeysWithValues: DodgySignal.parameters.map { ($0.key, EffectValue.number(0)) }))
        XCTAssertEqual(changedPixels(effect.apply(to: scene, time: 1.3)), 0)
    }

    func testEachBadTVControlDoesSomethingOnItsOwn() {
        for parameter in DodgySignal.parameters {
            let effect = NativeEffect.badTV.make(canvas)
            var values = Dictionary(uniqueKeysWithValues: DodgySignal.parameters.map { ($0.key, EffectValue.number(0)) })
            values[parameter.key] = .number(1)
            effect.setValues(values)
            // The scene is mostly flat colour, where a sideways wobble only shows at edges.
            XCTAssertGreaterThan(changedPixels(effect.apply(to: scene, time: 1.3)), 20, parameter.displayName)
        }
    }

    func testPillarBoxPutsBarsDownBothSidesOnly() {
        let effect = NativeEffect.pillarBox.make(canvas)
        effect.setValues([
            PillarBox.percentKey: .number(50),
            PillarBox.colorKey: .color(red: 0, green: 1, blue: 0, alpha: 1),
        ])
        let bytes = access.rgba(of: effect.apply(to: scene, time: 0), width: 320, height: 180)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(bytes[(y * 320 + x) * 4..<(y * 320 + x) * 4 + 3]) }

        XCTAssertEqual(pixel(40, 90), [0, 255, 0], "a quarter of the width each side at 50 percent")
        XCTAssertEqual(pixel(280, 90), [0, 255, 0])
        XCTAssertEqual(pixel(120, 90), [255, 0, 0], "the middle is the picture")

        effect.setValues([PillarBox.percentKey: .number(0)])
        XCTAssertEqual(changedPixels(effect.apply(to: scene, time: 0)), 0, "no bars at zero")
        effect.setValues([:])
        XCTAssertGreaterThan(changedPixels(effect.apply(to: scene, time: 0)), 1000, "black bars by default")
        XCTAssertEqual(PillarBox.parameters.map(\.displayName), ["Percent", "Color"])
    }

    func testComicBookAndCharcoalSketchRedrawThePicture() {
        for effect in [NativeEffect.comicBook, NativeEffect.charcoalSketch] {
            let output = effect.make(canvas).apply(to: scene, time: 0)
            XCTAssertEqual(output.extent, CGRect(origin: .zero, size: canvas), effect.name)
            XCTAssertGreaterThan(changedPixels(output), 3000, effect.name)
            XCTAssertTrue(effect.parameters.contains { $0.displayName == "Strength" }, effect.name)
        }
    }

    func testStrengthFadesARestyleBackTowardsThePicture() {
        for effect in [NativeEffect.comicBook, NativeEffect.charcoalSketch] {
            let made = effect.make(canvas)
            made.setValues(["Strength": .number(0)])
            XCTAssertEqual(changedPixels(made.apply(to: scene, time: 0)), 0, effect.name)
            made.setValues(["Strength": .number(0.5)])
            XCTAssertGreaterThan(changedPixels(made.apply(to: scene, time: 0)), 500, effect.name)
        }
        XCTAssertEqual(
            NativeEffect.charcoalSketch.parameters.map(\.displayName), ["Line strength", "Detail", "Contrast", "Strength"]
        )
    }
}


final class TextOverlayTests: XCTestCase {
    private let access = makePixelAccess()
    private let black = solid(.black, CGRect(origin: .zero, size: canvas))

    private func bright(_ image: CIImage, columns: Range<Int>, rows: Range<Int>) -> Int {
        let bytes = access.rgba(of: image, width: 320, height: 180)
        var count = 0
        for row in rows {
            for column in columns where bytes[(row * 320 + column) * 4] > 150 { count += 1 }
        }
        return count
    }

    func testTheClockShowsTheTimeInTheFormatAskedFor() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(year: 2030, month: 6, day: 15, hour: 9, minute: 5))!
        let effect = ClockEffect(canvas: canvas) { date }

        // The time spans the same width whatever it says, so two digits are
        // drawn far taller than a whole date.
        effect.setValues([ClockEffect.formatKey: .string("HH")])
        let short = bright(effect.apply(to: black, time: 0), columns: 0..<320, rows: 0..<180)
        effect.setValues([ClockEffect.formatKey: .string("HH:mm EEEE d MMMM yyyy")])
        let long = bright(effect.apply(to: black, time: 0), columns: 0..<320, rows: 0..<180)
        XCTAssertGreaterThan(long, 30, "the date is drawn")
        XCTAssertGreaterThan(short, long * 3, "two digits across the same width are much bigger")

        effect.setValues([ClockEffect.formatKey: .string("")])
        XCTAssertEqual(bright(effect.apply(to: black, time: 0), columns: 0..<320, rows: 0..<180), 0, "no format, nothing drawn")
        XCTAssertEqual(
            ClockEffect.parameters.map(\.displayName), ["Format", "Color", "X Position", "Y Position", "Size", "Rotation"]
        )
        XCTAssertEqual(TextStamp.steadied("09:41 pm"), "00:00 pm")
    }

    func testTheClockGoesWhereItIsPutIsResizedTurnedAndRedrawnOnlyWhenItChanges() {
        let effect = ClockEffect(canvas: canvas) { Date(timeIntervalSince1970: 0) }
        effect.setValues([ClockEffect.xKey: .number(-0.6), ClockEffect.sizeKey: .number(0.3)])
        let output = effect.apply(to: black, time: 0)

        XCTAssertGreaterThan(bright(output, columns: 0..<140, rows: 50..<130), 100)
        XCTAssertEqual(bright(output, columns: 220..<320, rows: 0..<180), 0)
        XCTAssertEqual(bright(effect.apply(to: black, time: 1), columns: 0..<140, rows: 50..<130),
                       bright(output, columns: 0..<140, rows: 50..<130))

        // Twice the size draws about four times the ink.
        effect.setValues([ClockEffect.sizeKey: .number(0.3)])
        let small = bright(effect.apply(to: black, time: 0), columns: 0..<320, rows: 0..<180)
        effect.setValues([ClockEffect.sizeKey: .number(0.6)])
        let large = bright(effect.apply(to: black, time: 0), columns: 0..<320, rows: 0..<180)
        XCTAssertGreaterThan(large, small * 3)

        // Flat, it is wider than it is tall; turned a quarter, it stands up.
        XCTAssertEqual(bright(effect.apply(to: black, time: 0), columns: 0..<320, rows: 0..<40), 0)
        effect.setValues([ClockEffect.sizeKey: .number(0.6), ClockEffect.rotationKey: .number(90)])
        let upright = effect.apply(to: black, time: 0)
        XCTAssertGreaterThan(bright(upright, columns: 0..<320, rows: 0..<40), 20)
        XCTAssertEqual(bright(upright, columns: 0..<100, rows: 0..<180), 0)
    }

    func testTheCountdownCountsEitherWayAndCanBePausedAndHeld() {
        let effect = CountdownEffect(canvas: canvas)
        func ink(at time: TimeInterval) -> Int {
            bright(effect.apply(to: black, time: time), columns: 0..<320, rows: 0..<180)
        }
        // 10:00 has more ink than 09:5x would lose, so compare with a count
        // that has clearly changed digit shapes: 1:00:00 down to 59:59.
        effect.setValues([CountdownEffect.timeKey: .string("1:00:00")])
        let start = ink(at: 0)
        XCTAssertGreaterThan(start, 200, "the time is drawn")
        XCTAssertEqual(ink(at: 0), start, "and not redrawn while it reads the same")
        let later = ink(at: 5)
        XCTAssertNotEqual(later, start, "it has counted down below the hour, and lost the hours")

        effect.setValues([CountdownEffect.timeKey: .string("1:00:00"), CountdownEffect.pauseKey: .boolean(true)])
        let paused = ink(at: 6)
        XCTAssertEqual(ink(at: 600), paused, "paused, it stands still")

        effect.setValues([CountdownEffect.timeKey: .string("1:00:00"), CountdownEffect.holdKey: .boolean(true)])
        XCTAssertEqual(ink(at: 601), start, "held, it shows the start again")

        effect.setValues([
            CountdownEffect.timeKey: .string("1:00:00"), CountdownEffect.countsUpKey: .boolean(true),
            CountdownEffect.carriesOnKey: .boolean(true), CountdownEffect.xKey: .number(-0.6),
        ])
        let up = effect.apply(to: black, time: 700)
        XCTAssertGreaterThan(bright(up, columns: 0..<160, rows: 0..<180), 100, "counting up from 00:00, on the left")
        XCTAssertEqual(bright(up, columns: 260..<320, rows: 0..<180), 0)
        XCTAssertEqual(CountdownEffect.parameters.map(\.displayName), [
            "Time", "Count up", "Count up after zero", "Pause", "Hold at the start",
            "Color", "X Position", "Y Position", "Size", "Rotation",
        ])
        XCTAssertEqual(NativeEffect.countdown.name, "Countdown")
        let nowhere = CountdownEffect(canvas: .zero)
        XCTAssertEqual(nowhere.apply(to: black, time: 0), black, "with nowhere to draw, the picture passes through")
        XCTAssertNotNil(NativeEffect.countdown.make(canvas))
    }

    func testTheHaloIsARingThatGoesWhereItIsPutAndTurns() {
        let effect = HaloEffect(canvas: canvas)
        effect.setValues([HaloEffect.yKey: .number(0), HaloEffect.sizeKey: .number(0.5)])
        let flat = effect.apply(to: black, time: 0)
        // 160 points wide and 48 tall, round the middle of the picture.
        XCTAssertGreaterThan(bright(flat, columns: 84..<92, rows: 85..<95), 20, "its left edge is lit")
        XCTAssertEqual(bright(flat, columns: 150..<170, rows: 85..<95), 0, "the middle of the ring is empty")
        XCTAssertEqual(bright(flat, columns: 150..<170, rows: 0..<40), 0, "and nothing is drawn far above it")
        XCTAssertEqual(bright(effect.apply(to: black, time: 1), columns: 0..<320, rows: 0..<180),
                       bright(flat, columns: 0..<320, rows: 0..<180))

        effect.setValues([
            HaloEffect.yKey: .number(0), HaloEffect.sizeKey: .number(0.5), HaloEffect.rotationKey: .number(90),
        ])
        let upright = effect.apply(to: black, time: 0)
        XCTAssertGreaterThan(bright(upright, columns: 150..<170, rows: 8..<20), 20, "turned, it reaches up the picture")
        XCTAssertEqual(bright(upright, columns: 84..<92, rows: 85..<95), 0)

        effect.setValues([HaloEffect.xKey: .number(-0.5), HaloEffect.yKey: .number(0), HaloEffect.sizeKey: .number(0.2)])
        let left = effect.apply(to: black, time: 0)
        XCTAssertGreaterThan(bright(left, columns: 40..<120, rows: 70..<110), 50)
        XCTAssertEqual(bright(left, columns: 160..<320, rows: 0..<180), 0)

        // More glow lights more of the picture round the ring.
        func lit(glow: Double) -> Int {
            effect.setValues([
                HaloEffect.yKey: .number(0), HaloEffect.sizeKey: .number(0.5), HaloEffect.glowKey: .number(glow),
            ])
            let picture = access.rgba(of: effect.apply(to: black, time: 0), width: 320, height: 180)
            return stride(from: 0, to: picture.count, by: 4).filter { picture[$0] > 20 }.count
        }
        XCTAssertGreaterThan(lit(glow: 1), lit(glow: 0) * 2)

        XCTAssertEqual(
            HaloEffect.parameters.map(\.displayName), ["X Position", "Y Position", "Size", "Rotation", "Glow", "Color"]
        )
        XCTAssertEqual(NativeEffect.halo.name, "Halo")
        XCTAssertTrue(NativeEffect.halo.make(canvas) is HaloEffect)
        XCTAssertEqual(HaloEffect(canvas: .zero).apply(to: black, time: 0), black)
    }

    func testABadConnectionHoldsThePictureWhileItIsFrozen() {
        let effect = BadConnectionEffect(canvas: canvas)
        effect.setValues([BadConnectionEffect.frequencyKey: .number(60), BadConnectionEffect.longestKey: .number(0.2)])
        let red = solid(.red, CGRect(origin: .zero, size: canvas))
        let blue = solid(.blue, CGRect(origin: .zero, size: canvas))
        func redness(_ image: CIImage) -> Int { bright(image, columns: 0..<320, rows: 0..<180) }
        let everything = 320 * 180

        XCTAssertEqual(redness(effect.apply(to: red, time: 0)), everything, "live, the picture passes through")
        // From then on the camera shows blue. Whenever red still comes out,
        // the connection is stuck on the old picture.
        var stuck = 0
        var live = 0
        for step in 1...600 {
            let output = effect.apply(to: step == 1 ? red : blue, time: Double(step) * 0.05)
            if redness(output) == everything { stuck += 1 } else { live += 1 }
        }
        XCTAssertGreaterThan(live, 100, "most of the time it runs")
        XCTAssertEqual(stuck, 1, "the only red frame after the first is the red one itself, shown live")

        // Hold the picture on red, then change the camera while frozen.
        let sticky = BadConnectionEffect(canvas: canvas)
        sticky.setValues([
            BadConnectionEffect.frequencyKey: .number(60), BadConnectionEffect.longestKey: .number(10),
            BadConnectionEffect.blockinessKey: .number(1),
        ])
        var held = 0
        _ = sticky.apply(to: red, time: 0)
        // The first freeze starts within a second and a half, so by then
        // the camera has turned blue and any red is the picture held.
        let turnsBlueAt = 30
        for step in 1...200 where redness(
            sticky.apply(to: step < turnsBlueAt ? red : blue, time: Double(step) * 0.05)
        ) == everything {
            held += 1
        }
        XCTAssertGreaterThan(held, turnsBlueAt, "frozen on red after the camera turned blue, blocks and all")

        XCTAssertEqual(BadConnectionEffect.parameters.map(\.displayName), [
            "Freezes a minute", "Longest freeze in seconds", "Blocky while frozen",
        ])
        XCTAssertEqual(NativeEffect.badConnection.name, "Bad Connection")
        XCTAssertTrue(NativeEffect.badConnection.make(canvas) is BadConnectionEffect)
    }

    func testTheNewsHeadlineIsABannerWithATagABarAndASecondLine() {
        let effect = HeadlineEffect(canvas: canvas)
        // The canvas is 320 by 180 and rows count down from the top. At size
        // 0.9 the banner is 288 wide: a 13 point tag over a 22 point bar over
        // an 11.5 point second line, centred 64 points below the middle.
        func pixel(_ image: CIImage, column: Int, row: Int) -> [UInt8] {
            let bytes = access.rgba(of: image, width: 320, height: 180)
            return Array(bytes[(row * 320 + column) * 4..<(row * 320 + column) * 4 + 3])
        }
        let banner = effect.apply(to: black, time: 0)
        let tag = pixel(banner, column: 20, row: 134)
        XCTAssertGreaterThan(tag[0], 150, "the tag is red")
        XCTAssertLessThan(tag[1], 60)
        XCTAssertEqual(pixel(banner, column: 300, row: 134), [0, 0, 0], "and only as wide as its words")
        XCTAssertEqual(pixel(banner, column: 300, row: 155), [255, 255, 255], "the bar runs the full width")
        let second = pixel(banner, column: 300, row: 170)
        XCTAssertGreaterThan(second[0], 150)
        XCTAssertLessThan(second[0], 240, "the second line's strip is a shade darker")
        XCTAssertEqual(pixel(banner, column: 160, row: 60), [0, 0, 0], "nothing is drawn above it")
        XCTAssertEqual(bright(effect.apply(to: black, time: 1), columns: 0..<320, rows: 0..<180),
                       bright(banner, columns: 0..<320, rows: 0..<180))

        // With no tag and no second line only the bar is left.
        effect.setValues([
            HeadlineEffect.tagKey: .string(""), HeadlineEffect.detailKey: .string(""),
            HeadlineEffect.barColorKey: .color(red: 0, green: 0, blue: 1, alpha: 1),
            HeadlineEffect.yKey: .number(0),
        ])
        let bar = effect.apply(to: black, time: 0)
        XCTAssertEqual(pixel(bar, column: 300, row: 90), [0, 0, 255])
        XCTAssertEqual(pixel(bar, column: 300, row: 70), [0, 0, 0])
        XCTAssertEqual(pixel(bar, column: 300, row: 110), [0, 0, 0])

        // Turned a quarter, the bar stands upright through the middle.
        effect.setValues([
            HeadlineEffect.tagKey: .string(""), HeadlineEffect.detailKey: .string(""),
            HeadlineEffect.headlineKey: .string(""),
            HeadlineEffect.barColorKey: .color(red: 0, green: 0, blue: 1, alpha: 1),
            HeadlineEffect.yKey: .number(0), HeadlineEffect.rotationKey: .number(90),
        ])
        let upright = effect.apply(to: black, time: 0)
        XCTAssertEqual(pixel(upright, column: 160, row: 10), [0, 0, 255])
        XCTAssertEqual(pixel(upright, column: 300, row: 90), [0, 0, 0])

        // The tag is cut to its own words, which fit it: it stands still.
        let still = HeadlineEffect(canvas: canvas)
        still.setValues([HeadlineEffect.tagKey: .string("LIVE NOW")])
        XCTAssertEqual(
            access.rgba(of: still.apply(to: black, time: 0), width: 320, height: 180),
            access.rgba(of: still.apply(to: black, time: 3), width: 320, height: 180),
            "words that fit their strip do not scroll"
        )

        // A headline too long for the bar runs along it, and comes round again.
        let long = String(repeating: "MMMM WWWW ", count: 12)
        effect.setValues([
            HeadlineEffect.tagKey: .string(""), HeadlineEffect.detailKey: .string(""),
            HeadlineEffect.headlineKey: .string(long), HeadlineEffect.yKey: .number(0),
        ])
        func ink(at time: TimeInterval) -> [UInt8] { access.rgba(of: effect.apply(to: black, time: time), width: 320, height: 180) }
        XCTAssertNotEqual(ink(at: 0), ink(at: 0.7), "it has moved along")
        XCTAssertEqual(ink(at: 0.7), ink(at: 0.7))
        effect.setValues([
            HeadlineEffect.tagKey: .string(""), HeadlineEffect.detailKey: .string(""),
            HeadlineEffect.headlineKey: .string(long), HeadlineEffect.yKey: .number(0),
            HeadlineEffect.scrollSpeedKey: .number(0),
        ])
        XCTAssertEqual(ink(at: 0), ink(at: 5), "at no speed it stands still")
        XCTAssertEqual(HeadlineEffect.parameters.last?.key, HeadlineEffect.scrollSpeedKey)

        XCTAssertEqual(HeadlineEffect.parameters.map(\.displayName), [
            "Tag", "Headline", "Second line", "Tag colour", "Bar colour", "Text colour",
            "X Position", "Y Position", "Size", "Rotation", "Scroll speed, for text too long to fit",
        ])
        XCTAssertEqual(NativeEffect.headline.name, "News Headline")
        XCTAssertTrue(NativeEffect.headline.make(canvas) is HeadlineEffect)
        XCTAssertEqual(HeadlineEffect(canvas: .zero).apply(to: black, time: 0), black)
    }

    func testTheThoughtBubbleIsAWhiteCloudWithItsMessageInside() {
        let effect = ThoughtBubbleEffect(canvas: canvas)
        effect.setValues([
            ThoughtBubbleEffect.xKey: .number(0), ThoughtBubbleEffect.yKey: .number(0),
            ThoughtBubbleEffect.sizeKey: .number(0.6), ThoughtBubbleEffect.messageKey: .string("MMMM MMMM"),
        ])
        let output = effect.apply(to: black, time: 0)
        let bytes = access.rgba(of: output, width: 320, height: 180)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(bytes[(y * 320 + x) * 4..<(y * 320 + x) * 4 + 3]) }

        XCTAssertEqual(pixel(80, 60), [255, 255, 255], "inside the cloud, clear of the text")
        XCTAssertEqual(pixel(5, 5), [0, 0, 0], "outside it the picture is untouched")
        let dark = (130..<190).filter { pixel($0, 90)[0] < 100 }.count
        XCTAssertGreaterThan(dark, 5, "the message is written across the middle")
        // Each shape fills the middle in white, clear of its outline, and
        // each has an outline of its own, so no two draw the same picture.
        var counts: [Int] = []
        for kind in ["Thought", "Speech", "Shout", "Something else"] {
            effect.setValues([
                ThoughtBubbleEffect.xKey: .number(0), ThoughtBubbleEffect.yKey: .number(0),
                ThoughtBubbleEffect.sizeKey: .number(0.6), ThoughtBubbleEffect.messageKey: .string(""),
                ThoughtBubbleEffect.kindKey: .string(kind),
            ])
            let shape = effect.apply(to: black, time: 0)
            let shapeBytes = access.rgba(of: shape, width: 320, height: 180)
            XCTAssertEqual(Array(shapeBytes[(90 * 320 + 160) * 4..<(90 * 320 + 160) * 4 + 3]), [255, 255, 255], kind)
            XCTAssertEqual(Array(shapeBytes[(5 * 320 + 5) * 4..<(5 * 320 + 5) * 4 + 3]), [0, 0, 0], kind)
            counts.append(bright(shape, columns: 0..<320, rows: 0..<180))
        }
        XCTAssertEqual(Set(counts.prefix(3)).count, 3, "three shapes, three pictures")
        XCTAssertEqual(counts[3], counts[0], "an unknown shape is a thought bubble")
        // The message is set in the font chosen: a bold face lays down more ink.
        func ink(font: String) -> Int {
            effect.setValues([
                ThoughtBubbleEffect.xKey: .number(0), ThoughtBubbleEffect.yKey: .number(0),
                ThoughtBubbleEffect.sizeKey: .number(0.6), ThoughtBubbleEffect.messageKey: .string("MMMM MMMM"),
                ThoughtBubbleEffect.fontKey: .string(font),
            ])
            let written = access.rgba(of: effect.apply(to: black, time: 0), width: 320, height: 180)
            return (100..<220).filter { written[(90 * 320 + $0) * 4] < 100 }.count
        }
        XCTAssertGreaterThan(ink(font: "Helvetica-Bold"), ink(font: "Helvetica-Light"))
        XCTAssertEqual(ThoughtBubbleEffect.parameters.first { $0.key == ThoughtBubbleEffect.fontKey }?.isFont, true)
        XCTAssertEqual(ThoughtBubbleEffect.parameters.map(\.displayName).prefix(3), ["Message", "Shape", "Font"])
        XCTAssertEqual(ThoughtBubbleEffect.parameters.first?.key, ThoughtBubbleEffect.messageKey)
        XCTAssertTrue(NativeEffect.thoughtBubble.make(canvas) is ThoughtBubbleEffect)
        XCTAssertTrue(NativeEffect.clock(now: Date.init).make(canvas) is ClockEffect)
    }
}

final class ImageSourceTests: XCTestCase {
    func testShowsAPictureFileAndNothingWithoutOne() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let red = solid(.red, CGRect(x: 0, y: 0, width: 12, height: 8))
        try CIContext().writePNGRepresentation(
            of: red, to: url, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        let provider = ImageSourceProvider()

        let source = try XCTUnwrap(provider.makeSource(for: .image(path: url.path)))
        source.start()
        XCTAssertEqual(source.latestFrame?.extent.size, CGSize(width: 12, height: 8))
        XCTAssertTrue(source.update(to: .image(path: url.path)))
        XCTAssertFalse(source.update(to: .image(path: "/other.png")))
        source.stop()

        XCTAssertNil(provider.makeSource(for: .image(path: ""))?.latestFrame)
        XCTAssertNil(provider.makeSource(for: .image(path: "/no/such/file.png"))?.latestFrame)
        XCTAssertNil(provider.makeSource(for: .colorBars))
    }
}

final class TestCardSourceTests: XCTestCase {
    func testTheCardHasAGridColourBarsAndAGreyScale() throws {
        let source = TestCardSource(canvas: canvas, label: "Card")
        source.start()
        let image = try XCTUnwrap(source.latestFrame)
        let bytes = makePixelAccess().rgba(of: image, width: 320, height: 180)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(bytes[(y * 320 + x) * 4..<(y * 320 + x) * 4 + 3]) }

        XCTAssertEqual(image.extent, CGRect(origin: .zero, size: canvas))
        let bar = pixel(100, 70)
        XCTAssertEqual(bar[0], bar[1], "the first colour bar is grey-white")
        XCTAssertGreaterThan(bar[0], 150)
        let blue = pixel(230, 70)
        XCTAssertGreaterThan(blue[2], blue[0] + 80, "the last colour bar is blue")
        XCTAssertLessThan(pixel(88, 98)[0], 40, "the grey scale starts at black")
        XCTAssertGreaterThan(pixel(232, 98)[0], 215, "and ends at white")
        XCTAssertTrue(source.update(to: .testCard))
        XCTAssertFalse(source.update(to: .colorBars))
        source.stop()
        XCTAssertNotNil(TestCardSourceProvider().makeSource(for: .testCard))
        XCTAssertNil(TestCardSourceProvider().makeSource(for: .colorBars))
    }
}

final class NativeEffectLibraryTests: XCTestCase {
    func testListsAndMakesTheBuiltInEffects() {
        let access = makePixelAccess()
        let folder = FileManager.default.temporaryDirectory
        let library = NativeEffectLibrary(directory: folder, effects: [
            .flame(pixels: access) { 1 },
            .matrix(pixels: access) { 2 },
        ])

        XCTAssertEqual(library.directory, folder)
        XCTAssertEqual(library.availableEffects(), [
            EffectListing(name: "Flame", kind: .filter), EffectListing(name: "Matrix", kind: .filter),
        ])
        XCTAssertEqual(library.parameters(forEffectNamed: "Flame").map(\.displayName), ["Flares"])
        XCTAssertEqual(library.parameters(forEffectNamed: "Matrix").map(\.displayName), ["Strength"])
        XCTAssertEqual(library.parameters(forEffectNamed: "Missing"), [])
        XCTAssertTrue(library.makeEffect(named: "Flame", canvas: canvas) is FlameEffect)
        XCTAssertTrue(library.makeEffect(named: "Matrix", canvas: canvas) is MatrixEffect)
        XCTAssertNil(library.makeEffect(named: "Missing", canvas: canvas))
    }
}

private final class TintingEffect: ImageEffect {
    func setValues(_ values: [String: EffectValue]) {}

    func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        solid(.red, CGRect(origin: .zero, size: canvas))
    }
}

private struct TintingFactory: ImageEffectFactory {
    func makeEffect(named name: String, canvas: CGSize) -> ImageEffect? {
        name == "Tint" ? TintingEffect() : nil
    }
}

private struct FadingFactory: TransitionFactory {
    func makeTransition(named name: String, canvas: CGSize) -> TransitionEffect? {
        name == DissolveTransition.name ? DissolveTransition() : nil
    }
}

final class EffectThumbnailerTests: XCTestCase {
    private func centre(of image: CGImage) -> [UInt8] {
        let bytes = makePixelAccess().rgba(of: CIImage(cgImage: image), width: 3, height: 3)
        return Array(bytes[16..<19])
    }

    func testAThumbnailShowsTheEffectAppliedToTheSampleScene() throws {
        let thumbnailer = EffectThumbnailer(factory: TintingFactory(), transitions: FadingFactory(), size: canvas)

        let tinted = try XCTUnwrap(thumbnailer.thumbnail(forEffectNamed: "Tint"))
        XCTAssertEqual(tinted.width, 320)
        XCTAssertEqual(tinted.height, 180)
        XCTAssertEqual(centre(of: tinted), [255, 0, 0])
        XCTAssertNil(thumbnailer.thumbnail(forEffectNamed: "Missing"))

        // Half way through a fade the picture is neither scene: the sun on
        // the right of the first shows through on the left of the second.
        let fading = try XCTUnwrap(thumbnailer.thumbnail(forTransitionNamed: DissolveTransition.name))
        let whole = makePixelAccess().rgba(of: EffectThumbnailer.sampleScene(size: canvas), width: 3, height: 3)
        XCTAssertNotEqual(centre(of: fading), Array(whole[16..<19]))
        XCTAssertNil(thumbnailer.thumbnail(forTransitionNamed: "Missing"))
        XCTAssertNotEqual(Array(whole[16..<19]), [255, 0, 0], "the sample scene has a figure in the middle")
    }
}
