import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

/// Records who joins and leaves, and says the same words to everyone.
private final class FakeCaptions: CaptionsListening {
    var heard = HeardSpeech.nothing
    private(set) var joined: [HeardSources] = []
    private(set) var left: [HeardSources] = []

    func join(_ sources: HeardSources) { joined.append(sources) }
    func leave(_ sources: HeardSources) { left.append(sources) }
    func heard(from sources: HeardSources) -> HeardSpeech { heard }
}

final class LiveCaptionsEffectTests: XCTestCase {
    private let canvas = CGSize(width: 320, height: 180)
    private let access = makePixelAccess()
    private var bounds: CGRect { CGRect(origin: .zero, size: canvas) }
    private let picture = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180))
    private let clock = Date(timeIntervalSinceReferenceDate: 1000)
    private let camera = UUID()
    private lazy var microphone = HeardSources(levels: [camera: 1])

    /// How many nearly white pixels there are in a band of rows, counted from the bottom.
    private func whiteCount(_ image: CIImage, rows: ClosedRange<Int>) -> Int {
        let bytes = access.rgba(of: image.cropped(to: bounds), width: 320, height: 180)
        var count = 0
        for y in rows {
            let row = 179 - y
            for x in 0..<320 {
                let at = (row * 320 + x) * 4
                if bytes[at] > 200, bytes[at + 1] > 200, bytes[at + 2] > 200 { count += 1 }
            }
        }
        return count
    }

    private func captions(
        _ listener: FakeCaptions, saying words: String, secondsAgo: TimeInterval, values: [String: EffectValue] = [:]
    ) -> (LiveCaptionsEffect, CIImage) {
        listener.heard = HeardSpeech(words: words, when: clock.addingTimeInterval(-secondsAgo))
        let effect = LiveCaptionsEffect(canvas: canvas, listener: listener, now: { self.clock })
        effect.setValues(values)
        effect.hear(microphone)
        return (effect, effect.apply(to: picture, time: 0))
    }

    func testWordsJustSaidAreWrittenAlongTheBottomInWhite() {
        let listener = FakeCaptions()
        let (_, image) = captions(listener, saying: "Hello there", secondsAgo: 1)
        XCTAssertEqual(image.extent, bounds)
        // The bottom line sits 18 up a picture 180 tall.
        XCTAssertGreaterThan(whiteCount(image, rows: 10...26), 0, "white words near the bottom")
        XCTAssertEqual(whiteCount(image, rows: 60...179), 0, "and nothing higher up")
        XCTAssertEqual(listener.joined, [microphone], "the first frame starts the listening")
    }

    func testTheWordsClearOnceTheTalkingHasStoppedAWhile() {
        let (_, quiet) = captions(FakeCaptions(), saying: "Hello there", secondsAgo: 5)
        XCTAssertEqual(quiet, picture, "four seconds, then gone")
        let (_, longer) = captions(
            FakeCaptions(), saying: "Hello there", secondsAgo: 5, values: [LiveCaptionsEffect.lingerKey: .number(8)]
        )
        XCTAssertNotEqual(longer, picture, "unless they are kept up for longer")
        let (_, nothing) = captions(FakeCaptions(), saying: "", secondsAgo: 0)
        XCTAssertEqual(nothing, picture, "nothing said, nothing written")
    }

    func testOnlyTheLastLinesShowAndOlderOnesStackAbove() {
        let long = Array(repeating: "and so on", count: 40).joined(separator: " ")
        let (_, two) = captions(FakeCaptions(), saying: long, secondsAgo: 0)
        XCTAssertGreaterThan(whiteCount(two, rows: 28...40), 0, "a second line above the first")
        XCTAssertEqual(whiteCount(two, rows: 44...179), 0, "and no third")
        let (_, one) = captions(FakeCaptions(), saying: long, secondsAgo: 0, values: [LiveCaptionsEffect.linesKey: .number(1)])
        XCTAssertEqual(whiteCount(one, rows: 28...179), 0, "one line when asked for one")
        let (_, red) = captions(
            FakeCaptions(), saying: "Hello", secondsAgo: 0,
            values: [LiveCaptionsEffect.colorKey: .color(red: 1, green: 0, blue: 0, alpha: 1)]
        )
        XCTAssertEqual(whiteCount(red, rows: 0...179), 0, "in the colour chosen")
    }

    func testAPreviewShowsSampleWordsWithoutListening() {
        let listener = FakeCaptions()
        let effect = LiveCaptionsEffect(canvas: canvas, listener: listener, now: { self.clock })
        effect.showSample()
        effect.hear(microphone)
        XCTAssertGreaterThan(whiteCount(effect.apply(to: picture, time: 0), rows: 10...26), 0)
        XCTAssertTrue(listener.joined.isEmpty)
    }

    func testTheListeningFollowsTheSourcesAboveAndEndsWithTheEffect() {
        let listener = FakeCaptions()
        listener.heard = HeardSpeech(words: "Hello", when: clock)
        var effect: LiveCaptionsEffect? = LiveCaptionsEffect(canvas: canvas, listener: listener, now: { self.clock })
        XCTAssertTrue(effect?.apply(to: picture, time: 0) === picture, "nothing above it, nothing to hear")
        XCTAssertTrue(listener.joined.isEmpty)

        effect?.hear(microphone)
        _ = effect?.apply(to: picture, time: 0)
        _ = effect?.apply(to: picture, time: 1)
        XCTAssertEqual(listener.joined, [microphone], "joined once")

        let quieter = HeardSources(levels: [camera: 0.5])
        effect?.hear(quieter)
        _ = effect?.apply(to: picture, time: 2)
        XCTAssertEqual(listener.left, [microphone])
        XCTAssertEqual(listener.joined, [microphone, quieter])

        effect?.hear(.none)
        XCTAssertTrue(effect?.apply(to: picture, time: 3) === picture, "its source taken away")
        XCTAssertEqual(listener.left, [microphone, quieter])

        effect?.hear(microphone)
        _ = effect?.apply(to: picture, time: 4)
        effect = nil
        XCTAssertEqual(listener.left, [microphone, quieter, microphone], "gone, it stops listening")
        _ = LiveCaptionsEffect(canvas: canvas, listener: listener, now: { self.clock })
        XCTAssertEqual(listener.left.count, 3, "one that never showed never listened")
    }

    func testTextIsBrokenIntoLinesThatFit() {
        let lines = LiveCaptionsEffect.lines(
            of: "one two three four five six", fontName: LiveCaptionsEffect.startFont, fontSize: 20, width: 120
        )
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertEqual(lines.joined(separator: " "), "one two three four five six")
        XCTAssertEqual(LiveCaptionsEffect.lines(of: "ab", fontName: "Helvetica", fontSize: 20, width: 0), ["a", "b"])
        XCTAssertEqual(LiveCaptionsEffect.lines(of: "", fontName: "Helvetica", fontSize: 20, width: 100), [])
    }

    func testTheCaptionsSettingsStartInOpenSansWhiteWithNoShadow() {
        let parameters = Dictionary(uniqueKeysWithValues: LiveCaptionsEffect.parameters.map { ($0.key, $0) })
        XCTAssertEqual(parameters[LiveCaptionsEffect.fontKey]?.defaultValue, .string("OpenSans-SemiBold"))
        XCTAssertEqual(parameters[LiveCaptionsEffect.colorKey]?.defaultValue, .color(red: 1, green: 1, blue: 1, alpha: 1))
        XCTAssertEqual(parameters[LiveCaptionsEffect.shadowKey]?.defaultValue, .color(red: 0, green: 0, blue: 0, alpha: 0))
        XCTAssertEqual(LiveCaptionsEffect.parameters.map(\.key), [
            "Font_Name", "Color", "Shadow", "Background", "Size", "Y_Position", "Lines", "Linger",
        ])
    }

    func testTheLibraryMakesCaptionsThatListenThroughTheSharedListener() {
        let listener = FakeCaptions()
        let made = NativeEffect.liveCaptions(listener: listener, now: { self.clock })
        XCTAssertEqual(made.name, "Live Captions")
        let effect = made.make(canvas)
        (effect as? HearsSourcesAbove)?.hear(microphone)
        _ = effect.apply(to: picture, time: 0)
        XCTAssertEqual(listener.joined, [microphone])
    }

    func testAPictureWithNoSizeHasNothingToWriteOn() {
        let listener = FakeCaptions()
        listener.heard = HeardSpeech(words: "Hello", when: clock)
        let effect = LiveCaptionsEffect(canvas: .zero, listener: listener, now: { self.clock })
        effect.hear(microphone)
        XCTAssertTrue(effect.apply(to: picture, time: 0) === picture)
    }
}
