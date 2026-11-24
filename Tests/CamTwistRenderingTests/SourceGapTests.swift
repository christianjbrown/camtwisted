import AVFoundation
import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

final class SlideShowEdgeTests: XCTestCase {
    func testASlideShowWithNoImagesShowsNothing() {
        let source = makeSlideShowSource(settings: SlideShowSettings(paths: []))
        source.start()
        defer { source.stop() }

        XCTAssertNil(source.latestFrame, "no images, nothing to show")
    }

    func testAFolderThatCannotBeReadHasNoImages() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: folder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }

        XCTAssertEqual(SlideShowSource.expand([folder.path], in: DiskSlideFolders()), [])
    }
}

final class RenderLoopEdgeTests: XCTestCase {
    private final class NoBuffers: PixelBufferProviding {
        func makeBuffer() -> CVPixelBuffer? { nil }
    }

    private final class CountingSink: FrameSink {
        private(set) var count = 0
        func send(_ pixelBuffer: CVPixelBuffer) { count += 1 }
    }

    private struct Factory: ImageEffectFactory, TransitionFactory {
        func makeEffect(named name: String, canvas: CGSize) -> ImageEffect? { nil }
        func makeTransition(named name: String, canvas: CGSize) -> TransitionEffect? { nil }
    }

    func testTheSameSourceInSeveralScenesIsKeptOnce() {
        let registry = SourceRegistry(providers: [ColorBarsSourceProvider()])
        let factory = Factory()
        let loop = makeRenderLoop(
            sources: registry, effectFactory: factory, transitionFactory: factory, programSinks: []
        )
        let scene = SceneConfiguration(items: [ChainItem(content: .source(.colorBars))])

        loop.setProgram(scene)
        loop.setPreview(scene)
        loop.startTransition(to: scene, named: "Dissolve", duration: 1)

        XCTAssertNil(loop.latestProgramFrame)
    }

    func testNothingIsSentWhenNoFrameCanBeHad() {
        let sink = CountingSink()
        let factory = Factory()
        let loop = makeRenderLoop(
            sources: SourceRegistry(providers: [ColorBarsSourceProvider()]),
            effectFactory: factory, transitionFactory: factory, programSinks: [sink],
            pixelBuffers: NoBuffers()
        )
        loop.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(sink.count, 0)
        XCTAssertNil(loop.latestProgramFrame)
    }

    func testAPoolThatCannotBeMadeGivesNoFrames() {
        XCTAssertNil(PixelBufferPool(width: 0, height: 0).makeBuffer())
        XCTAssertNotNil(PixelBufferPool(width: 16, height: 16).makeBuffer())
    }
}
