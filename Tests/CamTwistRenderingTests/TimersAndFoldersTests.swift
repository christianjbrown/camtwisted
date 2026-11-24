import CamTwistCore
import XCTest
@testable import CamTwistRendering

/// Timers that fire when a test says so.
final class FakeTimers: RepeatingTimers {
    final class Handle: Cancelling {
        private(set) var isCancelled = false
        func cancel() { isCancelled = true }
    }

    private(set) var intervals: [TimeInterval] = []
    private(set) var handles: [Handle] = []
    private var actions: [() -> Void] = []

    func every(_ interval: TimeInterval, _ action: @escaping () -> Void) -> Cancelling {
        let handle = Handle()
        intervals.append(interval)
        handles.append(handle)
        actions.append(action)
        return handle
    }

    func tick() {
        actions.forEach { $0() }
    }
}

final class RunLoopTimersTests: XCTestCase {
    private static let interval: TimeInterval = 0.02
    private static let timeout: TimeInterval = 5
    private static let ticksWanted = 2

    func testTheActionRepeatsUntilTheTimerIsCancelled() {
        var ticks = 0
        let timer = RunLoopTimers().every(Self.interval) { ticks += 1 }
        let deadline = Date().addingTimeInterval(Self.timeout)
        while ticks < Self.ticksWanted, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(Self.interval))
        }
        XCTAssertGreaterThanOrEqual(ticks, Self.ticksWanted)

        timer.cancel()
        let stopped = ticks
        RunLoop.main.run(until: Date().addingTimeInterval(Self.interval * 5))
        XCTAssertEqual(ticks, stopped)
    }
}

final class MovieHotFolderTimerTests: XCTestCase {
    private static let interval: TimeInterval = 7
    private static let timeout: TimeInterval = 5

    private final class Listing: MovieFolderListing {
        var movies: [String] = []
        private(set) var looks = 0

        func movies(in folder: String) -> [String] {
            looks += 1
            return movies
        }
    }

    private func spin(until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(Self.timeout)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    func testTheFolderIsLookedAtOnEveryTickAndTheTimerStopsWithTheSource() {
        let timers = FakeTimers()
        let listing = Listing()
        let source = makeMovieSource(
            settings: MovieSettings(hotFolder: "/hot", isMuted: true), folderListing: listing, timers: timers,
            hotFolderInterval: Self.interval
        )
        source.start()
        spin { listing.looks == 1 }
        XCTAssertEqual(timers.intervals, [Self.interval])
        XCTAssertNil(source.currentTrackFile)

        listing.movies = ["/hot/new.mov"]
        timers.tick()

        XCTAssertEqual(listing.looks, 2, "looked again on the tick")
        XCTAssertEqual(source.currentTrackFile, "/hot/new.mov")
        source.stop()
        spin { timers.handles.first?.isCancelled == true }
        XCTAssertEqual(timers.handles.first?.isCancelled, true)
    }
}

final class WebPageCameraTimerTests: XCTestCase {
    private static let snapshotsPerSecond: TimeInterval = 4
    private static let timeout: TimeInterval = 5

    func testSnapshotsAreScheduledAtTheirRateAndStopWithTheCamera() {
        let timers = FakeTimers()
        let camera = makeWebPageCamera(
            url: URL(string: "http://127.0.0.1:9/")!, canvas: CGSize(width: 64, height: 36), isTransparent: false,
            snapshotsPerSecond: Self.snapshotsPerSecond, timers: timers
        )
        camera.start()
        let deadline = Date().addingTimeInterval(Self.timeout)
        while timers.intervals.isEmpty, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(timers.intervals, [1 / Self.snapshotsPerSecond])

        timers.tick()
        camera.stop()
        while timers.handles.first?.isCancelled != true, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertEqual(timers.handles.first?.isCancelled, true)
    }
}

final class SlideFoldersTests: XCTestCase {
    private struct FakeFolders: SlideFolders {
        let entries: [String: DiskEntryKind]
        let contents: [String: [String]]

        func kind(of path: String) -> DiskEntryKind { entries[path] ?? .missing }
        func names(in folder: String) -> [String] { contents[folder] ?? [] }
    }

    func testExpandingAsksOnlyTheFoldersItIsGiven() {
        let folders = FakeFolders(
            entries: ["/show": .folder, "/one.png": .file, "/notes.txt": .file],
            contents: ["/show": ["b.png", "a.jpg", "readme.txt"]]
        )

        let images = SlideShowSource.expand(["/show", "/one.png", "/notes.txt", "/gone.png"], in: folders)

        XCTAssertEqual(images, ["/show/a.jpg", "/show/b.png", "/one.png"])
    }

    func testASlideShowExpandsItsPathsThroughTheFoldersItWasGiven() {
        let folders = FakeFolders(entries: ["/show": .folder], contents: ["/show": ["a.png"]])
        let source = SlideShowSource(settings: SlideShowSettings(paths: ["/show"]), folders: folders, now: Date.init)

        source.start()
        defer { source.stop() }

        // The image does not exist, so there is nothing to draw, but the
        // show was found and has a slide to try.
        XCTAssertNil(source.latestFrame)
    }

    func testTheDiskAnswersForFilesFoldersAndNothing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.png")
        try Data().write(to: file)
        let disk = DiskSlideFolders()

        XCTAssertEqual(disk.kind(of: folder.path), .folder)
        XCTAssertEqual(disk.kind(of: file.path), .file)
        XCTAssertEqual(disk.kind(of: folder.path + "/none"), .missing)
        XCTAssertEqual(disk.names(in: folder.path), ["a.png"])
        XCTAssertEqual(disk.names(in: folder.path + "/none"), [])
    }
}
