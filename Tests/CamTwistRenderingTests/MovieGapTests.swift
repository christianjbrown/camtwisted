import AVFoundation
import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

final class MovieSourceEdgeTests: XCTestCase {
    private static let timeout: TimeInterval = 15
    private static let pollInterval: TimeInterval = 0.05
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func spin(until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(Self.timeout)
        while Date() < deadline, !done() { spin(Self.pollInterval) }
    }

    private func clip(_ name: String) throws -> String {
        let url = folder.appendingPathComponent(name)
        try TestMovie.write(to: url, red: 0, green: 0, blue: 0)
        return url.path
    }

    func testAnUnrelatedItemEndingDoesNotMoveThePlaylist() throws {
        let first = try clip("a.mov")
        let source = makeMovieSource(settings: MovieSettings(
            files: [first, try clip("b.mov")], playMode: .playAllAndStop, isMuted: true
        ))
        source.start()
        defer { source.stop() }
        spin { source.currentTrackFile != nil }

        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: NSObject())
        spin(0.2)

        XCTAssertEqual(source.currentTrackFile, first)
    }

    func testTheHotFolderIsCheckedOnATimerAndTheSamePlaylistIsLeftAlone() throws {
        let first = try clip("a.mov")
        let source = makeMovieSource(
            settings: MovieSettings(hotFolder: folder.path, playMode: .playOneAndRepeat, isMuted: true),
            hotFolderInterval: 0.05
        )
        source.start()
        defer { source.stop() }
        spin { source.currentTrackFile == first }

        _ = try clip("b.mov")
        spin(0.3)

        XCTAssertEqual(source.currentTrackFile, first, "the clip that was playing carries on")
    }

    func testAPlaylistThatGrowsKeepsPlayingTheCurrentClip() throws {
        let first = try clip("a.mov")
        var settings = MovieSettings(files: [first], playMode: .playOneAndRepeat, isMuted: true)
        let source = makeMovieSource(settings: settings)
        source.start()
        defer { source.stop() }
        spin { source.currentTrackFile == first }

        settings.files.append(try clip("b.mov"))
        XCTAssertTrue(source.update(to: .movie(settings)))
        spin(0.2)
        XCTAssertTrue(source.update(to: .movie(settings)))
        spin(0.2)

        XCTAssertEqual(source.currentTrackFile, first)
    }

    func testShufflingPlaysTheClipTheRandomSourceChooses() throws {
        let files = [try clip("a.mov"), try clip("b.mov"), try clip("c.mov")]
        let chosen = files.count - 1
        var asked: [Range<Int>] = []
        let player = AVPlayer()
        let source = makeMovieSource(
            settings: MovieSettings(files: files, playMode: .shuffle, isMuted: true),
            player: player,
            randomIndex: { asked.append($0); return chosen }
        )
        source.start()
        defer { source.stop() }
        spin { source.currentTrackFile == files.first }

        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
        spin { source.currentTrackFile == files[chosen] }

        XCTAssertEqual(source.currentTrackFile, files[chosen])
        XCTAssertEqual(asked, [0..<files.count])
    }

    func testAClipThatEndsWhenNothingIsLeftStopsAndHidesTheSource() throws {
        let source = makeMovieSource(settings: MovieSettings(
            files: [try clip("a.mov")], playMode: .playOneAndStop, hidesWhenStopped: true, isMuted: true
        ))
        source.start()
        defer { source.stop() }
        spin { source.latestFrame != nil }
        XCTAssertNotNil(source.latestFrame)

        spin { source.latestFrame == nil }

        XCTAssertNil(source.latestFrame)
    }

    func testACaptionOfBlankSpaceLeavesTheFrameAlone() throws {
        let path = try clip("a.mov")
        let source = makeMovieSource(settings: MovieSettings(
            files: [path], playMode: .playOneAndRepeat, isMuted: true, captions: [path: " "]
        ))
        source.start()
        defer { source.stop() }
        spin { source.latestFrame != nil }

        XCTAssertNotNil(source.latestFrame)
    }
}

private extension MovieSourceEdgeTests {
    func spin(until done: () -> Bool, for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }
}

final class WebsiteSourceEdgeTests: XCTestCase {
    func testStartingTwiceAndLoadingAnAddressOnTheNetworkAreFine() {
        let canvas = CGSize(width: 64, height: 36)
        let camera = makeWebPageCamera(url: URL(string: "http://127.0.0.1:9/")!, canvas: canvas, isTransparent: true)

        camera.start()
        camera.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        camera.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertNil(camera.latestFrame)
    }
}
