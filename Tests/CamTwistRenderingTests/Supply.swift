import AVFoundation
import CamTwistCore
import CoreGraphics
import Foundation
@testable import CamTwistRendering

// What the app's composition root supplies, for the tests that build the
// types it builds. Each takes only what a test varies.

func makeRenderLoop(
    sources: SourceSupplying,
    effectFactory: ImageEffectFactory,
    transitionFactory: TransitionFactory,
    fallbackTransition: TransitionEffect = DissolveTransition(),
    programSinks: [FrameSink],
    contractSinks: [FrameSink] = [],
    previewSinks: [FrameSink] = [],
    pixelBuffers: PixelBufferProviding = PixelBufferPool(width: CameraContract.width, height: CameraContract.height),
    clock: @escaping () -> Date = Date.init,
    onMain: @escaping MainHop = RenderingSystem.mainHop
) -> RenderLoop {
    RenderLoop(
        sources: sources,
        makeRenderer: {
            SceneRenderer(
                sources: sources, effectFactory: effectFactory, canvas: CameraContract.size, supplies: .system()
            )
        },
        transitionFactory: transitionFactory,
        fallbackTransition: fallbackTransition, programSinks: programSinks, contractSinks: contractSinks,
        previewSinks: previewSinks, pixelBuffers: pixelBuffers,
        makeDetailBuffers: { PixelBufferPool(width: $0, height: $1) }, clock: clock,
        context: RenderingSystem.makeContext(),
        queue: DispatchQueue(label: RenderLoop.queueLabel, qos: .userInteractive), onMain: onMain
    )
}

func makeMovieSource(
    settings: MovieSettings,
    folderListing: MovieFolderListing = FileManagerMovieFolderListing(),
    timers: RepeatingTimers = RunLoopTimers(),
    hotFolderInterval: TimeInterval = Pacing.usual.hotFolderInterval,
    player: AVPlayer = RenderingSystem.makePlayer(),
    randomIndex: @escaping IndexPicker = RenderingSystem.indexPicker
) -> MovieSource {
    MovieSource(
        settings: settings, folderListing: folderListing, timers: timers, notifications: NotificationCenter.default,
        player: player, onMain: RenderingSystem.mainHop, randomIndex: randomIndex, hotFolderInterval: hotFolderInterval
    )
}

func makeWebsiteSource(
    address: String, snapshotsPerSecond: TimeInterval = Pacing.usual.websiteSnapshotsPerSecond,
    canvas: CGSize = CameraContract.size
) -> WebsiteSource {
    WebsiteSource(
        address: address, snapshotsPerSecond: snapshotsPerSecond, timers: RunLoopTimers(),
        onMain: RenderingSystem.mainHop, makeHost: RenderingSystem.makeWebPageHost, canvas: canvas
    )
}

func makeHTMLEffectLibrary(directory: URL) -> HTMLEffectLibrary {
    HTMLEffectLibrary(
        directory: directory, snapshotsPerSecond: Pacing.usual.websiteSnapshotsPerSecond, timers: RunLoopTimers(),
        listing: FileManagerDirectoryListing(), onMain: RenderingSystem.mainHop,
        makeHost: RenderingSystem.makeWebPageHost
    )
}

func makeHTMLEffect(file: URL, canvas: CGSize) -> HTMLEffect {
    HTMLEffect(
        file: file, canvas: canvas, snapshotsPerSecond: Pacing.usual.websiteSnapshotsPerSecond, timers: RunLoopTimers(),
        onMain: RenderingSystem.mainHop, makeHost: RenderingSystem.makeWebPageHost
    )
}

func makeSlideShowSource(settings: SlideShowSettings, now: @escaping () -> Date = Date.init) -> SlideShowSource {
    SlideShowSource(settings: settings, folders: DiskSlideFolders(), now: now)
}

func movieProvider(timers: RepeatingTimers = RunLoopTimers()) -> MovieSourceProvider {
    MovieSourceProvider(
        folderListing: FileManagerMovieFolderListing(), timers: timers, notifications: NotificationCenter.default,
        hotFolderInterval: Pacing.usual.hotFolderInterval, makePlayer: RenderingSystem.makePlayer,
        onMain: RenderingSystem.mainHop, randomIndex: RenderingSystem.indexPicker
    )
}

func makeWebsiteProvider() -> WebsiteSourceProvider {
    WebsiteSourceProvider(
        snapshotsPerSecond: Pacing.usual.websiteSnapshotsPerSecond, timers: RunLoopTimers(),
        onMain: RenderingSystem.mainHop, makeHost: RenderingSystem.makeWebPageHost
    )
}

func makeWebPageCamera(
    url: URL, canvas: CGSize, isTransparent: Bool, snapshotsPerSecond: TimeInterval = Pacing.usual.websiteSnapshotsPerSecond,
    timers: RepeatingTimers = RunLoopTimers()
) -> WebPageCamera {
    WebPageCamera(
        url: url, canvas: canvas, isTransparent: isTransparent, snapshotsPerSecond: snapshotsPerSecond, timers: timers,
        onMain: RenderingSystem.mainHop, makeHost: RenderingSystem.makeWebPageHost
    )
}

func makeEngineSoundMixer(sinks: [SoundSink]) -> EngineSoundMixer {
    EngineSoundMixer(
        sinks: sinks, tapFrames: Pacing.usual.soundTapFrames,
        queue: DispatchQueue(label: EngineSoundMixer.queueLabel), makeNode: RenderingSystem.makePlayerNode
    )
}

/// The identifier of the process the tests run in, standing for the app's own.
let ownProcess = ProcessInfo.processInfo.processIdentifier

func makePixelAccess() -> CoreImagePixelAccess {
    CoreImagePixelAccess(context: RenderingSystem.makeContext())
}
