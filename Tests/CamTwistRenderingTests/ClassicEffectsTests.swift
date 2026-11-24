import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

/// The classic looks, motion, sky and text effects the app comes with.
final class ClassicEffectsTests: XCTestCase {
    private let canvas = CGSize(width: 320, height: 180)
    private let access = makePixelAccess()
    private var bounds: CGRect { CGRect(origin: .zero, size: canvas) }
    private var picture: CIImage { EffectThumbnailer.sampleScene(size: canvas) }
    private let time = 0.4

    private func bytes(_ image: CIImage) -> [UInt8] {
        access.rgba(of: image, width: 320, height: 180)
    }

    private func startingValues(of native: NativeEffect) -> [String: EffectValue] {
        Dictionary(uniqueKeysWithValues: native.parameters.map { ($0.key, $0.defaultValue) })
    }

    /// The picture after the effect has run with some controls changed.
    private func render(
        _ native: NativeEffect, _ changes: [String: EffectValue] = [:], at time: TimeInterval? = nil
    ) -> [UInt8] {
        let made = native.make(canvas)
        made.setValues(startingValues(of: native).merging(changes) { _, changed in changed })
        let result = made.apply(to: picture, time: time ?? self.time)
        XCTAssertEqual(result.extent, bounds, native.name)
        return bytes(result)
    }

    private func find(_ name: String, in effects: [NativeEffect]) throws -> NativeEffect {
        try XCTUnwrap(effects.first { $0.name == name }, name)
    }

    private func assertChanges(
        _ native: NativeEffect, _ changes: [String: EffectValue], file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertNotEqual(
            render(native), render(native, changes), "\(native.name) changes with \(changes.keys.sorted())",
            file: file, line: line
        )
    }

    // MARK: Looks

    private var classic: [NativeEffect] { NativeEffect.classicFilters }

    func testEveryClassicFilterChangesThePictureAndKeepsItsSize() {
        let before = bytes(picture)
        XCTAssertEqual(classic.map(\.name), [
            "Glowing Edges", "Edges", "Sobel", "Monochrome", "Watercolor", "Ink Noir", "Troll", "Whirlpool",
            "Colour Burst", "Frosted Glass", "Goo", "Ablaze", "Liquid Metal",
        ])
        for native in classic {
            XCTAssertEqual(native.kind, .filter)
            XCTAssertNotEqual(render(native), before, "\(native.name) changes the picture")
        }
    }

    func testEveryClassicFilterControlDoesSomething() throws {
        let red = EffectValue.color(red: 1, green: 0, blue: 0, alpha: 1)
        let changes: [String: [[String: EffectValue]]] = [
            "Glowing Edges": [["Radius": .number(8)]],
            "Edges": [["Intensity": .number(1)]],
            "Sobel": [["Color": red]],
            "Monochrome": [["Color": red], ["Intensity": .number(0.2)]],
            "Ink Noir": [["Blobbiness": .number(8)]],
            "Troll": [["Amount": .number(40)]],
            "Whirlpool": [["Zoom": .number(0.5)], ["Spin": .number(0.5)]],
            "Colour Burst": [
                ["Master_Zoom": .number(0.5)], ["Zoom_Red": .number(1.4)], ["Zoom_Green": .number(1.3)],
                ["Zoom_Blue": .number(1.4)],
            ],
            "Frosted Glass": [["Amount": .number(200)], ["Fine": .boolean(true)], ["Scale": .number(3)]],
            "Goo": [["Color": red]],
            "Ablaze": [["Length": .number(80)], ["Flicker": .number(0)], ["Power": .number(2)]],
            "Liquid Metal": [["Height": .number(20)]],
        ]
        for (name, variations) in changes {
            let native = try find(name, in: classic)
            for variation in variations { assertChanges(native, variation) }
        }
        XCTAssertEqual(try find("Watercolor", in: classic).parameters, [])
    }

    func testTheAnimatedClassicFiltersMoveWithTheTime() throws {
        for name in ["Troll", "Ablaze", "Liquid Metal"] {
            let native = try find(name, in: classic)
            XCTAssertNotEqual(render(native, at: 0.4), render(native, at: 0.9), "\(name) moves")
        }
    }

    func testEachEffectStartsAtItsOwnDefaults() throws {
        func start(_ name: String, _ key: String) throws -> EffectValue? {
            try find(name, in: classic).parameters.first { $0.key == key }?.defaultValue
        }
        XCTAssertEqual(try start("Glowing Edges", "Radius"), .number(1))
        XCTAssertEqual(try start("Edges", "Intensity"), .number(5))
        XCTAssertEqual(try start("Whirlpool", "Zoom"), .number(-0.5))
        XCTAssertEqual(try start("Whirlpool", "Spin"), .number(-0.5))
        XCTAssertEqual(try start("Frosted Glass", "Amount"), .number(40))
    }

    // MARK: Motion

    private var motion: [NativeEffect] { NativeEffect.motionFilters }

    func testTheMotionFiltersChangeThePictureAndKeepItsSize() {
        let before = bytes(picture)
        XCTAssertEqual(motion.map(\.name), ["Earthquake", "Dodge bullets", "Old movie"])
        for native in motion {
            XCTAssertNotEqual(render(native), before, "\(native.name) changes the picture")
            XCTAssertNotEqual(render(native, at: 0.4), render(native, at: 1.3), "\(native.name) moves")
        }
    }

    func testTheEarthquakeShakesFasterWithASmallerPeriod() throws {
        assertChanges(try find("Earthquake", in: motion), ["Speed": .number(0.5)])
        // A period below the slowest the control allows is held at it.
        let quake = try find("Earthquake", in: motion)
        XCTAssertEqual(render(quake, ["Speed": .number(0)]), render(quake, ["Speed": .number(0.15)]))
    }

    func testEveryOldMovieControlDoesSomething() throws {
        let film = try find("Old movie", in: motion)
        for changes in [
            ["Grain_Frequency": EffectValue.number(0.5)], ["Grain": .number(100)], ["Vertical_Lines": .number(0)],
            ["Min_EV_Distortion": .number(-2)], ["Max_EV_Distortion": .number(3)], ["Sepia_Intensity": .number(0)],
        ] { assertChanges(film, changes) }
    }

    func testFilmScratchesStayForAFewFramesThenJump() throws {
        let film = try find("Old movie", in: motion)
        let lines = ["Grain": EffectValue.number(0), "Min_EV_Distortion": .number(0), "Max_EV_Distortion": .number(0)]
        // Two instants in the same few frames show the same scratches, a later one other scratches.
        XCTAssertEqual(render(film, lines, at: 0.0), render(film, lines, at: 0.05))
        XCTAssertNotEqual(render(film, lines, at: 0.0), render(film, lines, at: 1.0))
    }

    // MARK: Freeze frame

    func testFreezeFrameHoldsTheFrameItWasSwitchedOnAt() {
        let effect = FreezeFrameEffect(canvas: canvas, pixels: access)
        let other = picture.applyingFilter("CIColorInvert")
        XCTAssertEqual(FreezeFrameEffect.parameters.map(\.key), ["Freeze"])
        // Off, it passes the picture straight through.
        effect.setValues([:])
        XCTAssertEqual(bytes(effect.apply(to: picture, time: 0)), bytes(picture))
        effect.setValues([FreezeFrameEffect.freezeKey: .boolean(true)])
        let held = effect.apply(to: picture, time: 0)
        XCTAssertEqual(held.extent, bounds)
        XCTAssertEqual(bytes(held), bytes(picture), "the right way up")
        XCTAssertEqual(bytes(effect.apply(to: other, time: 1)), bytes(picture), "held while the picture changes")
        // Switched off it lets the live picture through again, and a new freeze takes a new frame.
        effect.setValues([FreezeFrameEffect.freezeKey: .boolean(false)])
        XCTAssertEqual(bytes(effect.apply(to: other, time: 2)), bytes(other))
        effect.setValues([FreezeFrameEffect.freezeKey: .boolean(true)])
        XCTAssertEqual(bytes(effect.apply(to: other, time: 3)), bytes(other))
        XCTAssertEqual(
            NativeEffect.freezeFrame(pixels: access).make(canvas).apply(to: picture, time: 0).extent, bounds
        )
    }

    // MARK: Letter box

    func testTheLetterBoxCoversTheTopAndBottomByThePercentInTheColour() {
        let letterBox = NativeEffect.letterBox
        XCTAssertEqual(letterBox.name, "LetterBox")
        XCTAssertEqual(letterBox.kind, .overlay)
        let covered = render(letterBox)
        // Twenty percent of 180 points is 18 each side: the rows are counted from the top.
        func pixel(_ x: Int, _ y: Int, in all: [UInt8]) -> [UInt8] { Array(all[(y * 320 + x) * 4..<(y * 320 + x) * 4 + 4]) }
        XCTAssertEqual(pixel(160, 2, in: covered), [0, 0, 0, 255])
        XCTAssertEqual(pixel(160, 177, in: covered), [0, 0, 0, 255])
        XCTAssertNotEqual(pixel(160, 30, in: covered), [0, 0, 0, 255])
        XCTAssertEqual(render(letterBox, ["Percent": .number(0)]), bytes(picture))
        assertChanges(letterBox, ["Percent": .number(60)])
        assertChanges(letterBox, ["Color": .color(red: 1, green: 0, blue: 0, alpha: 1)])
        XCTAssertEqual(
            render(letterBox, ["Percent": .number(500)]), render(letterBox, ["Percent": .number(100)]),
            "the percent stops at all of the picture"
        )
    }

    func testThePillarBoxStillCoversTheSides() {
        let covered = render(.pillarBox)
        XCTAssertEqual(Array(covered[(90 * 320 + 2) * 4..<(90 * 320 + 2) * 4 + 4]), [0, 0, 0, 255])
    }

    // MARK: Sky

    private var sky: [NativeEffect] { NativeEffect.skyEffects }

    func testSnowFallsOverThePictureAndKeepsMoving() throws {
        let snow = try find("Snowfall", in: sky)
        XCTAssertEqual(snow.kind, .overlay)
        XCTAssertNotEqual(render(snow), bytes(picture))
        XCTAssertNotEqual(render(snow, at: 0.4), render(snow, at: 1.4))
        assertChanges(snow, ["Speed": .number(50)])
        assertChanges(snow, ["Num_Flakes": .number(1)])
    }

    func testTheSearchlightsSweepAndCanMakeTheBatSignal() throws {
        let lights = try find("Searchlights", in: sky)
        XCTAssertEqual(lights.kind, .overlay)
        XCTAssertNotEqual(render(lights), bytes(picture))
        XCTAssertNotEqual(render(lights, at: 0.4), render(lights, at: 1.4))
        assertChanges(lights, ["Batman": .boolean(true)])
        // With the bat signal the lamps hold their aim, so only the glow moves nothing.
        XCTAssertEqual(
            render(lights, ["Batman": .boolean(true)], at: 0.4), render(lights, ["Batman": .boolean(true)], at: 1.4)
        )
    }

    // MARK: Text

    private var texts: [NativeEffect] { NativeEffect.textEffects }

    func testEveryTextEffectCanBeDraggedResizedAndTurned() {
        XCTAssertEqual(texts.map(\.name), ["Text", "Spinning Text", "Scrolling Text", "Credits Roll"])
        for native in texts {
            XCTAssertEqual(native.kind, .overlay)
            func control(_ name: String) -> EffectParameter? {
                native.parameters.first { $0.displayName == name && $0.kind == .number }
            }
            for name in ["X Position", "Y Position", "Size", "Rotation"] {
                XCTAssertNotNil(control(name), "\(native.name) has \(name)")
            }
            XCTAssertTrue(native.parameters.contains { $0.isFont }, "\(native.name) has a font")
        }
    }

    func testEveryTextEffectDrawsOverThePictureTheSizeOfTheCanvas() {
        for native in texts { XCTAssertNotEqual(render(native, at: 1.2), bytes(picture), native.name) }
    }

    func testEveryControlOfTheTextEffectsDoesSomething() throws {
        let red = EffectValue.color(red: 1, green: 0, blue: 0, alpha: 1)
        let opaqueBlack = EffectValue.color(red: 0, green: 0, blue: 0, alpha: 1)
        let common: [[String: EffectValue]] = [
            ["X_Position": .number(-0.5)], ["Y_Position": .number(0.5)], ["Size": .number(0.2)],
            ["Rotation": .number(45)], ["Font_Name": .string("Courier")],
        ]
        let particular: [String: [[String: EffectValue]]] = [
            "Text": [["String": .string("Hi")], ["Color": red], ["Shadow": opaqueBlack], ["Background": opaqueBlack]],
            "Spinning Text": [
                ["inputString_proxy_1": .string("Hi")], ["inputColor_proxy_1": red], ["Shadow": opaqueBlack],
                ["Background": opaqueBlack], ["Speed": .number(1)],
            ],
            "Scrolling Text": [
                ["String": .string("Hi")], ["inputColor_proxy_1": red], ["Shadow": opaqueBlack],
                ["Speed": .number(5)], ["Y_Position_1": .number(0.5)],
            ],
            "Credits Roll": [
                ["Text": .string("One\nTwo")], ["Text_Color": red], ["Shadow_Color": opaqueBlack],
                ["Roll_Time": .number(0.5)], ["Transition_Mode": .number(2)],
            ],
        ]
        for native in texts {
            // Scrolling text has its own key for its height.
            let moved = native.name == "Scrolling Text"
                ? common.map { $0 == ["Y_Position": .number(0.5)] ? ["Y_Position_1": .number(0.5)] : $0 }
                : common
            for changes in moved + (particular[native.name] ?? []) {
                XCTAssertNotEqual(
                    render(native, at: 1.7), render(native, changes, at: 1.7), "\(native.name) \(changes.keys.sorted())"
                )
            }
        }
    }

    func testTextThatIsStillIsPaintedOnceAndKeptUntilAControlChanges() {
        let still = NativeEffect.textEffects[0].make(canvas)
        still.setValues([:])
        XCTAssertEqual(bytes(still.apply(to: picture, time: 0)), bytes(still.apply(to: picture, time: 9)))
        still.setValues(["String": .string("Changed")])
        XCTAssertNotEqual(bytes(still.apply(to: picture, time: 0)), bytes(picture))
    }

    func testTextWithNothingInItDrawsNothing() {
        XCTAssertEqual(render(texts[0], ["String": .string("")]), bytes(picture))
        XCTAssertEqual(render(texts[3], ["Text": .string("")], at: 2), bytes(picture))
    }

    func testAnOverlayThatCannotBePaintedLeavesThePictureAlone() {
        let effect = DrawnOverlay(canvas: .zero, animated: false) { _, _, _, _ in }
        XCTAssertEqual(effect.apply(to: picture, time: 0).extent, bounds)
    }

    func testRotatingTextTurnsRoundAndBackAgain() throws {
        let rotating = try find("Spinning Text", in: texts)
        // A quarter turn along it is edge on and a half turn is seen from behind.
        XCTAssertNotEqual(render(rotating, at: 0), render(rotating, at: 1))
        XCTAssertNotEqual(render(rotating, at: 2), render(rotating, at: 0))
    }

    func testScrollingTextCrossesThePictureAndCanBePaused() throws {
        let scrolling = try find("Scrolling Text", in: texts)
        let made = scrolling.make(canvas)
        made.setValues(startingValues(of: scrolling))
        let first = bytes(made.apply(to: picture, time: 0))
        let later = bytes(made.apply(to: picture, time: 1.5))
        XCTAssertNotEqual(first, later)
        made.setValues(startingValues(of: scrolling).merging(["Pause": .boolean(true)]) { _, new in new })
        XCTAssertEqual(bytes(made.apply(to: picture, time: 2.5)), later, "held where it was")
        // The time going backwards moves it no further.
        made.setValues(startingValues(of: scrolling))
        XCTAssertEqual(bytes(made.apply(to: picture, time: 0.5)), later)
    }

    func testRollingTextBringsItsLinesInOneAfterAnother() throws {
        let rolling = try find("Credits Roll", in: texts)
        XCTAssertEqual(render(rolling, at: 0), bytes(picture), "nothing has arrived yet")
        XCTAssertNotEqual(render(rolling, at: 0.6), render(rolling, at: 1.6))
        XCTAssertNotEqual(render(rolling, at: 1.6), render(rolling, at: 4))
        // A mode the control does not know is the fade.
        XCTAssertEqual(render(rolling, ["Transition_Mode": .number(9)], at: 0.6), render(rolling, ["Transition_Mode": .number(0)], at: 0.6))
        // Every way of arriving looks different part way.
        let arrivals = (0...3).map { render(rolling, ["Transition_Mode": .number(Double($0))], at: 0.5) }
        XCTAssertEqual(Set(arrivals).count, 4)
    }
}
