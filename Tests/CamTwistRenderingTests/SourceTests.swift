import AppKit
import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

private func pixel(of image: CIImage, x: CGFloat, y: CGFloat) -> [UInt8] {
    var pixel = [UInt8](repeating: 0, count: 4)
    CIContext().render(
        image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
        format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
    )
    return pixel
}

/// Writes small solid colour images into a temporary folder.
private final class ImageFolder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    init() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func write(_ name: String, color: NSColor) throws -> String {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        let data = try XCTUnwrap(
            image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        )
        let path = url.appendingPathComponent(name).path
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }
}

final class SlideShowSourceTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 0)

    func testFoldersExpandToTheirImagesInNameOrder() throws {
        let folder = try ImageFolder()
        try folder.write("b.png", color: .blue)
        try folder.write("a.png", color: .red)
        try Data().write(to: folder.url.appendingPathComponent("notes.txt"))
        let single = try folder.write("c.png", color: .green)

        let images = SlideShowSource.expand([folder.url.path, single, "/no/such/file.png", folder.url.path + "/notes.txt"], in: DiskSlideFolders())

        XCTAssertEqual(images.map { ($0 as NSString).lastPathComponent }, ["a.png", "b.png", "c.png", "c.png"])
    }

    func testSlidesAdvanceWithTheClockAndHoldWhilePaused() throws {
        let folder = try ImageFolder()
        try folder.write("a.png", color: .red)
        try folder.write("b.png", color: .blue)
        var settings = SlideShowSettings(paths: [folder.url.path], delay: 5)
        let source = makeSlideShowSource(settings: settings) { [unowned self] in self.clock }
        source.start()

        XCTAssertGreaterThan(pixel(of: try XCTUnwrap(source.latestFrame), x: 4, y: 4)[0], 200)
        clock = clock.addingTimeInterval(6)
        XCTAssertGreaterThan(pixel(of: try XCTUnwrap(source.latestFrame), x: 4, y: 4)[2], 200)

        settings.isPaused = true
        XCTAssertTrue(source.update(to: .slideShow(settings)))
        clock = clock.addingTimeInterval(100)
        XCTAssertGreaterThan(pixel(of: try XCTUnwrap(source.latestFrame), x: 4, y: 4)[2], 200, "paused on the blue slide")

        settings.isPaused = false
        XCTAssertTrue(source.update(to: .slideShow(settings)))
        clock = clock.addingTimeInterval(5)
        XCTAssertGreaterThan(pixel(of: try XCTUnwrap(source.latestFrame), x: 4, y: 4)[0], 200)

        settings.paths = []
        XCTAssertTrue(source.update(to: .slideShow(settings)))
        XCTAssertNil(source.latestFrame)
        XCTAssertFalse(source.update(to: .colorBars))
        source.stop()
    }

    func testStartingPausedStaysOnTheFirstSlide() throws {
        let folder = try ImageFolder()
        try folder.write("a.png", color: .red)
        try folder.write("b.png", color: .blue)
        let source = makeSlideShowSource(
            settings: SlideShowSettings(paths: [folder.url.path], delay: 1, isPaused: true)
        ) { [unowned self] in self.clock }
        source.start()
        clock = clock.addingTimeInterval(30)
        XCTAssertGreaterThan(pixel(of: try XCTUnwrap(source.latestFrame), x: 4, y: 4)[0], 200)
    }

    func testProviderMakesOnlySlideShows() {
        let provider = SlideShowSourceProvider(folders: DiskSlideFolders(), now: Date.init)
        XCTAssertNotNil(provider.makeSource(for: .slideShow(SlideShowSettings())))
        XCTAssertNil(provider.makeSource(for: .colorBars))
    }
}

final class TelestratorSourceTests: XCTestCase {
    private let canvas = CGSize(width: 200, height: 100)
    private let line = DrawingStroke(
        points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)],
        color: RGBColor(red: 1, green: 0, blue: 0), width: 0.05
    )

    func testStrokesAreDrawnOnAClearBackground() throws {
        let source = TelestratorSource(settings: TelestratorSettings(strokes: [line]), canvas: canvas)
        source.start()
        let image = try XCTUnwrap(source.latestFrame)

        XCTAssertEqual(pixel(of: image, x: 100, y: 50), [255, 0, 0, 255])
        XCTAssertEqual(pixel(of: image, x: 100, y: 5)[3], 0)
        source.stop()
    }

    func testNewStrokesAppearAndASingleTapLeavesADot() throws {
        let source = TelestratorSource(settings: TelestratorSettings(), canvas: canvas)
        XCTAssertEqual(pixel(of: try XCTUnwrap(source.latestFrame), x: 100, y: 50)[3], 0)

        let dot = DrawingStroke(points: [CGPoint(x: 0.5, y: 0.5)], color: RGBColor(red: 0, green: 0, blue: 1), width: 0.1)
        let empty = DrawingStroke(points: [], color: RGBColor(red: 0, green: 1, blue: 0), width: 0.1)
        XCTAssertTrue(source.update(to: .telestrator(TelestratorSettings(strokes: [empty, dot]))))
        XCTAssertEqual(pixel(of: try XCTUnwrap(source.latestFrame), x: 100, y: 50), [0, 0, 255, 255])

        XCTAssertTrue(source.update(to: .telestrator(TelestratorSettings(strokes: [empty, dot], penWidth: 0.02))))
        XCTAssertFalse(source.update(to: .colorBars))
    }

    func testProviderMakesOnlyTelestrators() {
        let provider = TelestratorSourceProvider()
        XCTAssertNotNil(provider.makeSource(for: .telestrator(TelestratorSettings())))
        XCTAssertNil(provider.makeSource(for: .colorBars))
    }
}

final class WebsiteSourceTests: XCTestCase {
    func testAddressesBecomeURLs() {
        XCTAssertEqual(WebsiteSource.url(from: "example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(WebsiteSource.url(from: " http://example.com/a ")?.absoluteString, "http://example.com/a")
        XCTAssertEqual(WebsiteSource.url(from: "/tmp/page.html")?.isFileURL, true)
        XCTAssertNil(WebsiteSource.url(from: "   "))
    }

    func testProviderMakesOnlyWebsites() {
        let provider = makeWebsiteProvider()
        let source = provider.makeSource(for: .website(url: "example.com"))
        XCTAssertNotNil(source)
        XCTAssertEqual(source?.update(to: .website(url: "example.com")), true)
        XCTAssertEqual(source?.update(to: .website(url: "other.example")), false)
        XCTAssertNil(provider.makeSource(for: .colorBars))
    }
}

final class MovieFolderListingTests: XCTestCase {
    func testListsOnlyMoviesInNameOrder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["b.mov", "a.mp4", "notes.txt"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }

        let movies = FileManagerMovieFolderListing().movies(in: folder.path)

        XCTAssertEqual(movies.map { ($0 as NSString).lastPathComponent }, ["a.mp4", "b.mov"])
        XCTAssertEqual(FileManagerMovieFolderListing().movies(in: "/no/such/folder"), [])
    }

    func testProvidersMakeOnlyTheirOwnKind() {
        XCTAssertNotNil(movieProvider().makeSource(for: .movie(MovieSettings())))
        XCTAssertNil(movieProvider().makeSource(for: .colorBars))
        XCTAssertNil(CameraSourceProvider(queues: DispatchQueues()).makeSource(for: .colorBars))
        XCTAssertNotNil(DisplaySourceProvider(queues: DispatchQueues()).makeSource(for: .display(DisplaySettings(displayID: 1))))
        XCTAssertNil(DisplaySourceProvider(queues: DispatchQueues()).makeSource(for: .colorBars))
        XCTAssertNotNil(WindowSourceProvider(retryDelay: Pacing.usual.screenRetryDelay, ownProcessIdentifier: ownProcess, sleep: RenderingSystem.sleeper, queues: DispatchQueues()).makeSource(for: .window(WindowSettings(titlePattern: "x"))))
        XCTAssertNil(WindowSourceProvider(retryDelay: Pacing.usual.screenRetryDelay, ownProcessIdentifier: ownProcess, sleep: RenderingSystem.sleeper, queues: DispatchQueues()).makeSource(for: .colorBars))
    }
}
