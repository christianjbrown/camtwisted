import CamTwistCore
import CoreImage
import CoreVideo
import XCTest
@testable import CamTwistRendering

/// Reads single pixels out of rendered pictures.
private struct PixelReader {
    private let context = CIContext()
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let channels = 4

    func pixel(of image: CIImage, x: CGFloat, y: CGFloat) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: Self.channels)
        context.render(
            image,
            toBitmap: &pixel,
            rowBytes: Self.channels,
            bounds: CGRect(x: x, y: y, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        return pixel
    }

    /// A pixel of a BGRA pixel buffer, returned as red, green, blue.
    func pixel(of buffer: CVPixelBuffer, x: Int, y: Int) -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * Self.channels
        return [base[offset + 2], base[offset + 1], base[offset]]
    }
}

private func solid(_ color: CIColor, width: CGFloat, height: CGFloat) -> CIImage {
    CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
}

private let red: [UInt8] = [255, 0, 0, 255]
private let blue: [UInt8] = [0, 0, 255, 255]
private let black: [UInt8] = [0, 0, 0, 255]

private final class InvertingEffect: ImageEffect {
    private(set) var values: [String: EffectValue] = [:]

    func setValues(_ values: [String: EffectValue]) { self.values = values }

    func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        image.applyingFilter("CIColorInvert")
    }
}

private func scene(_ contents: ChainItem.Content...) -> SceneConfiguration {
    SceneConfiguration(items: contents.map { ChainItem(content: $0) })
}

final class CompositorTests: XCTestCase {
    private let compositor = Compositor(canvas: CGSize(width: 200, height: 100))
    private let reader = PixelReader()

    func testNothingIsBlack() {
        let frame = compositor.compose([], time: 0)
        XCTAssertEqual(frame.extent, CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertEqual(reader.pixel(of: frame, x: 100, y: 50), black)
        XCTAssertEqual(reader.pixel(of: compositor.compose([.picture(nil, placement: nil)], time: 0), x: 9, y: 9), black)
    }

    func testAPictureFillsTheCanvas() {
        let frame = compositor.compose([.picture(solid(.red, width: 50, height: 50), placement: nil)], time: 0)
        XCTAssertEqual(frame.extent, CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertEqual(reader.pixel(of: frame, x: 1, y: 1), red)
        XCTAssertEqual(reader.pixel(of: frame, x: 198, y: 98), red)
    }

    func testAPlacedPictureSitsInItsCorner() {
        let settings = PictureInPictureSettings(corner: .topLeft, scale: 0.5, margin: 0.05, canvasAspect: 2)
        let frame = compositor.compose([
            .picture(solid(.red, width: 200, height: 100), placement: nil),
            .picture(solid(.blue, width: 20, height: 10), placement: settings),
        ], time: 0)
        // Small picture: 100 wide, 50 tall, 10 in from the top left.
        XCTAssertEqual(reader.pixel(of: frame, x: 60, y: 65), blue)
        XCTAssertEqual(reader.pixel(of: frame, x: 5, y: 95), red)
        XCTAssertEqual(reader.pixel(of: frame, x: 150, y: 20), red)
    }

    func testAPlacedPictureCanBeTurned() {
        // A wide blue bar in the middle, turned a quarter, becomes a tall one.
        let settings = PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5), scale: 0.4, rotation: 90)
        let frame = compositor.compose([
            .picture(solid(.red, width: 200, height: 100), placement: nil),
            .picture(solid(.blue, width: 80, height: 20), placement: settings),
        ], time: 0)

        XCTAssertEqual(reader.pixel(of: frame, x: 100, y: 80), blue, "above the middle is now covered")
        XCTAssertEqual(reader.pixel(of: frame, x: 130, y: 50), red, "and the bar's old ends are not")
    }

    func testAnEffectChangesOnlyWhatCameBeforeIt() {
        let corner = PictureInPictureSettings(corner: .bottomLeft, scale: 0.5, margin: 0, canvasAspect: 2)
        let frame = compositor.compose([
            .picture(solid(.red, width: 200, height: 100), placement: nil),
            .effect(InvertingEffect()),
            .picture(solid(.blue, width: 20, height: 10), placement: corner),
        ], time: 0)
        XCTAssertEqual(reader.pixel(of: frame, x: 150, y: 80), [0, 255, 255, 255])
        XCTAssertEqual(reader.pixel(of: frame, x: 10, y: 10), blue)
    }

    func testALaterFullPictureCoversAnEarlierOne() {
        let frame = compositor.compose([
            .picture(solid(.red, width: 200, height: 100), placement: nil),
            .picture(solid(.blue, width: 200, height: 100), placement: nil),
        ], time: 0)
        XCTAssertEqual(reader.pixel(of: frame, x: 100, y: 50), blue)
    }
}

final class TestBarsSourceTests: XCTestCase {
    func testBarsCoverTheCanvasInOrder() throws {
        let source = TestBarsSource(canvas: CGSize(width: 700, height: 100))
        source.start()
        source.stop()
        let image = try XCTUnwrap(source.latestFrame)
        let reader = PixelReader()

        XCTAssertEqual(image.extent, CGRect(x: 0, y: 0, width: 700, height: 100))
        let first = reader.pixel(of: image, x: 50, y: 50)
        let last = reader.pixel(of: image, x: 650, y: 50)
        XCTAssertEqual(first[0], first[1])
        XCTAssertEqual(first[1], first[2])
        XCTAssertGreaterThan(first[0], 150)
        XCTAssertEqual(Array(last[0...1]), [0, 0])
        XCTAssertGreaterThan(last[2], 150)
        XCTAssertTrue(source.update(to: .colorBars))
        XCTAssertFalse(source.update(to: .website(url: "example.com")))
    }

    func testProviderMakesOnlyTheBars() {
        let provider = ColorBarsSourceProvider()
        XCTAssertNotNil(provider.makeSource(for: .colorBars))
        XCTAssertNil(provider.makeSource(for: .camera(deviceID: "1")))
    }
}

private final class CountingSource: FrameSource {
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var updates: [SourceSpec] = []
    let acceptsUpdates: Bool
    let latestFrame: CIImage? = solid(.blue, width: 10, height: 10)

    init(acceptsUpdates: Bool) {
        self.acceptsUpdates = acceptsUpdates
    }

    func start() { starts += 1 }
    func stop() { stops += 1 }

    func update(to spec: SourceSpec) -> Bool {
        updates.append(spec)
        return acceptsUpdates
    }
}

/// Makes counting sources for website specs only.
private final class StubProvider: SourceProvider {
    var acceptsUpdates = true
    private(set) var made: [CountingSource] = []

    func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .website = spec else { return nil }
        let source = CountingSource(acceptsUpdates: acceptsUpdates)
        made.append(source)
        return source
    }
}

final class SourceRegistryTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()
    private let pageA = SourceSpec.website(url: "a.example")
    private let pageB = SourceSpec.website(url: "b.example")

    func testStartsWhatIsNeededAndStopsWhatIsNot() {
        let provider = StubProvider()
        let registry = SourceRegistry(providers: [ColorBarsSourceProvider(), provider])

        registry.setSourcesInUse([first: pageA])
        registry.setSourcesInUse([first: pageA, second: pageB])
        XCTAssertEqual(provider.made.map(\.starts), [1, 1])
        XCTAssertNotNil(registry.latestFrame(for: first))
        XCTAssertNotNil(registry.source(for: second))

        registry.setSourcesInUse([second: pageB])
        XCTAssertEqual(provider.made.map(\.stops), [1, 0])
        XCTAssertNil(registry.latestFrame(for: first))
        XCTAssertNotNil(registry.latestFrame(for: second))
    }

    func testChangedSettingsReachARunningSource() {
        let provider = StubProvider()
        let registry = SourceRegistry(providers: [provider])
        registry.setSourcesInUse([first: pageA])
        registry.setSourcesInUse([first: pageB])
        registry.setSourcesInUse([first: pageB])

        XCTAssertEqual(provider.made.count, 1)
        XCTAssertEqual(provider.made[0].updates, [pageB])
        XCTAssertEqual(provider.made[0].stops, 0)
    }

    func testASourceThatCannotAdoptTheChangeIsReplaced() {
        let provider = StubProvider()
        provider.acceptsUpdates = false
        let registry = SourceRegistry(providers: [provider])
        registry.setSourcesInUse([first: pageA])
        registry.setSourcesInUse([first: pageB])

        XCTAssertEqual(provider.made.count, 2)
        XCTAssertEqual(provider.made[0].stops, 1)
        XCTAssertEqual(provider.made[1].starts, 1)
    }

    func testAnUnknownKindIsIgnored() {
        let registry = SourceRegistry(providers: [StubProvider()])
        registry.setSourcesInUse([first: .colorBars])
        XCTAssertNil(registry.latestFrame(for: first))
    }
}

private final class CapturingSink: FrameSink {
    private let lock = NSLock()
    private var buffers: [CVPixelBuffer] = []
    let received = XCTestExpectation(description: "frames arrive")

    init(expecting count: Int) {
        received.expectedFulfillmentCount = count
        received.assertForOverFulfill = false
    }

    func send(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        buffers.append(pixelBuffer)
        lock.unlock()
        received.fulfill()
    }

    var last: CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return buffers.last
    }
}

private final class StubEffectFactory: ImageEffectFactory, TransitionFactory {
    private(set) var requested: [String] = []
    private(set) var transitionsRequested: [String] = []
    let effect = InvertingEffect()

    func makeEffect(named name: String, canvas: CGSize) -> ImageEffect? {
        requested.append(name)
        return name == "Invert" ? effect : nil
    }

    func makeTransition(named name: String, canvas: CGSize) -> TransitionEffect? {
        transitionsRequested.append(name)
        return nil
    }
}

final class SceneRendererTests: XCTestCase {
    func testRendersSourcesAndEffectsAndSkipsDisabledSteps() {
        let registry = SourceRegistry(providers: [ColorBarsSourceProvider()])
        let factory = StubEffectFactory()
        let renderer = SceneRenderer(sources: registry, effectFactory: factory, canvas: CameraContract.size, supplies: .system())
        var bars = scene(
            .source(.colorBars),
            .effect(name: "Invert", values: ["Amount": .number(1)]),
            .effect(name: "Missing", values: [:])
        )
        registry.setSourcesInUse(bars.sourcesInUse)
        let reader = PixelReader()
        let x = CameraContract.size.width - 20

        let inverted = reader.pixel(of: renderer.render(bars, time: 0), x: x, y: 100)
        XCTAssertGreaterThan(inverted[0], 240, "the blue bar inverts to yellow")
        XCTAssertEqual(factory.effect.values, ["Amount": .number(1)])

        bars.update(id: bars.items[1].id) { $0.isEnabled = false }
        let plain = reader.pixel(of: renderer.render(bars, time: 0), x: x, y: 100)
        XCTAssertEqual(Array(plain[0...1]), [0, 0])
        XCTAssertEqual(factory.requested.filter { $0 == "Invert" }.count, 1, "the effect object is kept")
    }
}

final class BranchRenderingTests: XCTestCase {
    private let reader = PixelReader()

    func testABranchChangesOnlyItsOwnSource() {
        let registry = SourceRegistry(providers: [ColorBarsSourceProvider()])
        let factory = StubEffectFactory()
        let renderer = SceneRenderer(sources: registry, effectFactory: factory, canvas: CameraContract.size, supplies: .system())
        // Bars full screen, with a second set of bars in the top left corner
        // whose branch inverts them.
        let small = ChainItem(
            content: .source(.colorBars),
            pictureInPicture: PictureInPictureSettings(center: CGPoint(x: 0.25, y: 0.75), scale: 0.5),
            branch: [
                ChainItem(content: .effect(name: "Invert", values: [:])),
                ChainItem(content: .script(source: "beep")),
                ChainItem(isEnabled: false, content: .effect(name: "Invert", values: [:])),
            ]
        )
        let scene = SceneConfiguration(items: [ChainItem(content: .source(.colorBars)), small])
        registry.setSourcesInUse(scene.sourcesInUse)

        let frame = renderer.render(scene, time: 0)
        let width = CameraContract.size.width
        let height = CameraContract.size.height

        // The last bar is blue. In the main picture it stays blue.
        let main = reader.pixel(of: frame, x: width - 20, y: 40)
        XCTAssertEqual(Array(main[0...1]), [0, 0])
        XCTAssertGreaterThan(main[2], 150)
        // The small picture's last bar sits just left of the middle, up top,
        // and is inverted to yellow.
        let branch = reader.pixel(of: frame, x: width / 2 - 20, y: height - 40)
        XCTAssertGreaterThan(branch[0], 240)
        XCTAssertGreaterThan(branch[1], 240)
        XCTAssertEqual(factory.requested.filter { $0 == "Invert" }.count, 1, "one effect object, for the step that is on")
    }

    func testASourceWithClearPartsKeepsThemClearWithABranch() {
        let registry = SourceRegistry(providers: [ColorBarsSourceProvider(), ShapeSourceProvider()])
        let renderer = SceneRenderer(
            sources: registry, effectFactory: StubEffectFactory(), canvas: CameraContract.size, supplies: .system()
        )
        let circle = ChainItem(
            content: .source(.shape(ShapeSettings(kind: .circle))),
            branch: [ChainItem(content: .script(source: "beep"))]
        )
        let scene = SceneConfiguration(items: [ChainItem(content: .source(.colorBars)), circle])
        registry.setSourcesInUse(scene.sourcesInUse)

        let frame = renderer.render(scene, time: 0)

        // Outside the circle, in the corner, the blue bar beneath still shows.
        let corner = reader.pixel(of: frame, x: CameraContract.size.width - 20, y: 20)
        XCTAssertEqual(Array(corner[0...1]), [0, 0])
        XCTAssertGreaterThan(corner[2], 150)
    }

    func testASourceInABranchIsLaidOverItsParent() {
        let registry = SourceRegistry(providers: [ColorBarsSourceProvider(), TestCardSourceProvider()])
        let renderer = SceneRenderer(
            sources: registry, effectFactory: StubEffectFactory(), canvas: CameraContract.size, supplies: .system()
        )
        let card = ChainItem(
            content: .source(.testCard),
            pictureInPicture: PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5), scale: 0.4)
        )
        let scene = SceneConfiguration(items: [ChainItem(content: .source(.colorBars), branch: [card])])
        registry.setSourcesInUse(scene.sourcesInUse)

        let frame = renderer.render(scene, time: 0)

        // The card's grey background shows in the middle; the bars around it.
        let middle = reader.pixel(of: frame, x: CameraContract.size.width * 0.34, y: CameraContract.size.height * 0.34)
        XCTAssertEqual(middle[0], middle[2], "the card's corner is neutral grey")
        let corner = reader.pixel(of: frame, x: CameraContract.size.width - 20, y: 20)
        XCTAssertGreaterThan(corner[2], 150, "the parent's own blue bar is still there")
    }
}

final class DissolveTransitionTests: XCTestCase {
    func testBlendsFromOnePictureToTheOther() {
        let transition = DissolveTransition()
        let reader = PixelReader()
        let from = solid(.red, width: 10, height: 10)
        let to = solid(.blue, width: 10, height: 10)

        XCTAssertEqual(reader.pixel(of: transition.blend(from: from, to: to, progress: 0, time: 0), x: 5, y: 5), red)
        XCTAssertEqual(reader.pixel(of: transition.blend(from: from, to: to, progress: 1, time: 0), x: 5, y: 5), blue)
        let middle = reader.pixel(of: transition.blend(from: from, to: to, progress: 0.5, time: 0), x: 5, y: 5)
        XCTAssertGreaterThan(middle[0], 50)
        XCTAssertGreaterThan(middle[2], 50)
    }
}

final class RenderLoopTests: XCTestCase {
    private static let framesToWaitFor = 3
    private static let timeout: TimeInterval = 5
    private let reader = PixelReader()

    private func lastBarPixel(_ buffer: CVPixelBuffer) -> [UInt8] {
        reader.pixel(of: buffer, x: CameraContract.width - 20, y: CameraContract.height / 2)
    }

    func testRendersTheProgramIntoCameraSizedFrames() throws {
        let sink = CapturingSink(expecting: Self.framesToWaitFor)
        let factory = StubEffectFactory()
        let loop = makeRenderLoop(
            sources: SourceRegistry(providers: [ColorBarsSourceProvider()]),
            effectFactory: factory, transitionFactory: factory, programSinks: [sink]
        )
        loop.setProgram(scene(.source(.colorBars), .effect(name: "Invert", values: [:])))
        loop.start()
        loop.start()

        wait(for: [sink.received], timeout: Self.timeout)

        let buffer = try XCTUnwrap(sink.last)
        XCTAssertEqual(CVPixelBufferGetWidth(buffer), CameraContract.width)
        XCTAssertEqual(CVPixelBufferGetHeight(buffer), CameraContract.height)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(buffer), kCVPixelFormatType_32BGRA)
        let pixel = lastBarPixel(buffer)
        XCTAssertGreaterThan(pixel[0], 240)
        XCTAssertGreaterThan(pixel[1], 240)
        XCTAssertLessThan(pixel[2], pixel[0])
        XCTAssertNotNil(loop.latestProgramFrame)
    }

    func testIn4KTheProgramIsDrawnLargerAndTheCameraStillGetsItsOwnSize() throws {
        let factory = StubEffectFactory()
        func sizes(_ size: DrawingSize, withCamera: Bool) throws -> (program: Int, camera: Int?) {
            let program = CapturingSink(expecting: Self.framesToWaitFor)
            let camera = CapturingSink(expecting: Self.framesToWaitFor)
            let loop = makeRenderLoop(
                sources: SourceRegistry(providers: [ColorBarsSourceProvider()]),
                effectFactory: factory, transitionFactory: factory, programSinks: [program],
                contractSinks: withCamera ? [camera] : []
            )
            loop.setDrawingSize(size)
            loop.setDrawingSize(size)
            loop.setProgram(scene(.source(.colorBars)))
            loop.start()
            wait(for: [program.received], timeout: Self.timeout)
            if withCamera {
                wait(for: [camera.received], timeout: Self.timeout)
            }
            let frame = try XCTUnwrap(program.last)
            // The bars reach the right hand edge at whatever size they are drawn.
            let edge = reader.pixel(of: frame, x: CVPixelBufferGetWidth(frame) - 20, y: CVPixelBufferGetHeight(frame) / 2)
            XCTAssertGreaterThan(Int(edge[0]) + Int(edge[1]) + Int(edge[2]), 0)
            XCTAssertEqual(loop.latestProgramFrame.map(CVPixelBufferGetWidth), CVPixelBufferGetWidth(frame))
            return (CVPixelBufferGetWidth(frame), camera.last.map(CVPixelBufferGetWidth))
        }
        let large = try sizes(.ultraHD, withCamera: true)
        XCTAssertEqual(large.program, 3840)
        XCTAssertEqual(large.camera, 1920, "the camera is sent its own size")
        XCTAssertEqual(try sizes(.ultraHD, withCamera: false).program, 3840)
        let usual = try sizes(.fullHD, withCamera: true)
        XCTAssertEqual(usual.program, 1920)
        XCTAssertEqual(usual.camera, 1920)
    }

    func testASceneThatIsNotOnAirHasItsPictureTakenOnceItsSourcesHaveStarted() throws {
        let program = CapturingSink(expecting: Self.framesToWaitFor)
        let factory = StubEffectFactory()
        let loop = makeRenderLoop(
            sources: SourceRegistry(providers: [ColorBarsSourceProvider()]),
            effectFactory: factory, transitionFactory: factory, programSinks: [program]
        )
        loop.setProgram(SceneConfiguration())
        loop.start()
        let taken = expectation(description: "the picture is taken")
        var picture: CVPixelBuffer?
        XCTAssertTrue(loop.captureThumbnail(of: scene(.source(.colorBars))) { buffer in
            picture = buffer
            taken.fulfill()
        })
        XCTAssertFalse(loop.captureThumbnail(of: SceneConfiguration()) { _ in }, "one at a time")
        wait(for: [taken], timeout: Self.timeout)
        let frame = try XCTUnwrap(picture)
        XCTAssertEqual(CVPixelBufferGetWidth(frame), CameraContract.width)
        // The bars are in the picture though they were never on air.
        let edge = reader.pixel(of: frame, x: 40, y: CameraContract.height / 2)
        XCTAssertGreaterThan(Int(edge[0]) + Int(edge[1]) + Int(edge[2]), 300)
        // The next can be of the scene on air itself, whose sources are wanted only once.
        let onAir = scene(.source(.colorBars))
        loop.setProgram(onAir)
        XCTAssertTrue(loop.captureThumbnail(of: onAir) { _ in }, "and then the next")
    }

    func testChoosingFullHDAgainGoesBackToTheUsualFrames() throws {
        let program = CapturingSink(expecting: Self.framesToWaitFor)
        let factory = StubEffectFactory()
        let loop = makeRenderLoop(
            sources: SourceRegistry(providers: [ColorBarsSourceProvider()]),
            effectFactory: factory, transitionFactory: factory, programSinks: [program]
        )
        loop.setDrawingSize(.ultraHD)
        loop.setDrawingSize(.fullHD)
        loop.setProgram(scene(.source(.colorBars)))
        loop.start()
        wait(for: [program.received], timeout: Self.timeout)
        XCTAssertEqual(program.last.map(CVPixelBufferGetWidth), 1920)
    }

    func testPreviewIsRenderedForItsOwnSinks() throws {
        let program = CapturingSink(expecting: Self.framesToWaitFor)
        let preview = CapturingSink(expecting: Self.framesToWaitFor)
        let factory = StubEffectFactory()
        let loop = makeRenderLoop(
            sources: SourceRegistry(providers: [ColorBarsSourceProvider()]),
            effectFactory: factory, transitionFactory: factory,
            programSinks: [program], previewSinks: [preview]
        )
        loop.setProgram(SceneConfiguration())
        loop.setPreview(scene(.source(.colorBars)))
        loop.start()

        wait(for: [program.received, preview.received], timeout: Self.timeout)

        XCTAssertEqual(lastBarPixel(try XCTUnwrap(program.last)), [0, 0, 0])
        XCTAssertGreaterThan(lastBarPixel(try XCTUnwrap(preview.last))[2], 150)
    }

    func testTransitionsAreTimedByTheInjectedClock() {
        let factory = StubEffectFactory()
        var seconds = 0.0
        let loop = makeRenderLoop(
            sources: SourceRegistry(providers: [ColorBarsSourceProvider()]),
            effectFactory: factory, transitionFactory: factory, programSinks: [CapturingSink(expecting: 1)],
            clock: { Date(timeIntervalSince1970: seconds) }
        )
        let finished = expectation(description: "transition finishes")
        loop.onTransitionFinished { _ in finished.fulfill() }
        loop.setProgram(SceneConfiguration())
        loop.startTransition(to: scene(.source(.colorBars)), named: "Slow", duration: 1000)
        seconds = 2000
        loop.start()

        wait(for: [finished], timeout: Self.timeout)
    }

    func testATransitionEndsOnItsTargetAndReportsIt() throws {
        let sink = CapturingSink(expecting: Self.framesToWaitFor)
        let factory = StubEffectFactory()
        let loop = makeRenderLoop(
            sources: SourceRegistry(providers: [ColorBarsSourceProvider()]),
            effectFactory: factory, transitionFactory: factory, programSinks: [sink]
        )
        let target = scene(.source(.colorBars))
        let finished = expectation(description: "transition finishes")
        var landed: SceneConfiguration?
        loop.onTransitionFinished { scene in
            landed = scene
            finished.fulfill()
        }
        loop.setProgram(SceneConfiguration())
        loop.start()
        loop.startTransition(to: target, named: "Unknown wipe", duration: 0.2)

        wait(for: [finished], timeout: Self.timeout)

        XCTAssertEqual(landed, target)
        XCTAssertEqual(factory.transitionsRequested, ["Unknown wipe"])
        let settled = CapturingSink(expecting: Self.framesToWaitFor)
        _ = settled
        wait(for: [sink.received], timeout: Self.timeout)
    }

    private final class CountingTransition: TransitionEffect {
        private let lock = NSLock()
        private var blends = 0

        var blendCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return blends
        }

        func blend(from: CIImage, to: CIImage, progress: Double, time: TimeInterval) -> CIImage {
            lock.lock()
            blends += 1
            lock.unlock()
            return to
        }
    }

    func testAnUnknownTransitionIsDrawnAsTheInjectedFallback() {
        let factory = StubEffectFactory()
        let fallback = CountingTransition()
        let loop = makeRenderLoop(
            sources: SourceRegistry(providers: [ColorBarsSourceProvider()]),
            effectFactory: factory, transitionFactory: factory, fallbackTransition: fallback,
            programSinks: [CapturingSink(expecting: 1)]
        )
        let finished = expectation(description: "transition finishes")
        loop.onTransitionFinished { _ in finished.fulfill() }
        loop.setProgram(SceneConfiguration())
        loop.startTransition(to: scene(.source(.colorBars)), named: "Unknown wipe", duration: 0)
        loop.start()

        wait(for: [finished], timeout: Self.timeout)

        XCTAssertGreaterThan(fallback.blendCount, 0)
    }

    func testAnInstantTransitionIsComplete() {
        let running = RunningTransition(
            target: SceneConfiguration(), effect: DissolveTransition(), startTime: 5, duration: 0
        )
        XCTAssertEqual(running.progress(at: 5), 1)
        let timed = RunningTransition(target: SceneConfiguration(), effect: DissolveTransition(), startTime: 5, duration: 2)
        XCTAssertEqual(timed.progress(at: 4), 0)
        XCTAssertEqual(timed.progress(at: 6), 0.5)
        XCTAssertEqual(timed.progress(at: 9), 1)
    }
}

/// Remembers what it last heard.
private final class ListeningEffect: ImageEffect, HearsSourcesAbove {
    private(set) var heard: HeardSources?

    func setValues(_ values: [String: EffectValue]) {}
    func apply(to image: CIImage, time: TimeInterval) -> CIImage { image }
    func hear(_ sources: HeardSources) { heard = sources }
}

private final class ListeningFactory: ImageEffectFactory {
    private(set) var made: [ListeningEffect] = []

    func makeEffect(named name: String, canvas: CGSize) -> ImageEffect? {
        let effect = ListeningEffect()
        made.append(effect)
        return effect
    }
}

final class SceneHearingTests: XCTestCase {
    private let factory = ListeningFactory()
    private lazy var renderer = SceneRenderer(
        sources: SourceRegistry(providers: []), effectFactory: factory, canvas: CameraContract.size, supplies: .system()
    )

    func testAnEffectHearsTheSourcesAboveItAtTheirLevels() {
        let microphone = ChainItem(content: .source(.microphone(deviceID: nil)), volume: 0.5)
        let muted = ChainItem(content: .source(.microphone(deviceID: "quiet")), volume: 0)
        let off = ChainItem(isEnabled: false, content: .source(.microphone(deviceID: "off")))
        let bars = ChainItem(content: .source(.colorBars))
        let below = ChainItem(content: .source(.microphone(deviceID: "below")))
        let scene = SceneConfiguration(items: [
            microphone, muted, off, bars,
            ChainItem(content: .effect(name: "Captions", values: [:])),
            below,
            ChainItem(content: .effect(name: "Captions", values: [:])),
        ])
        _ = renderer.render(scene, time: 0)
        XCTAssertEqual(factory.made.first?.heard, HeardSources(levels: [microphone.id: 0.5]))
        XCTAssertEqual(factory.made.last?.heard, HeardSources(levels: [microphone.id: 0.5, below.id: 1]))
    }

    func testAnEffectInABranchHearsTheSourceTheBranchBelongsTo() {
        let effect = ChainItem(content: .effect(name: "Captions", values: [:]))
        let microphone = ChainItem(content: .source(.microphone(deviceID: nil)), branch: [effect])
        let bars = ChainItem(content: .source(.colorBars), branch: [ChainItem(content: .effect(name: "Captions", values: [:]))])
        _ = renderer.render(SceneConfiguration(items: [microphone, bars]), time: 0)
        XCTAssertEqual(factory.made.first?.heard, HeardSources(levels: [microphone.id: 1]))
        XCTAssertEqual(factory.made.last?.heard, HeardSources.none, "a picture with no sound has none to hear")
    }
}
