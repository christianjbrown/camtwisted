import AVFoundation
import CamTwistControl
import CamTwistCore
import CamTwistRendering
import CoreImage
import Foundation

/// The composition root: every concrete type is chosen here and nowhere
/// else. It is split by area, one file each for the sources, the effects,
/// the outputs and the sound, and this part puts them together.
@MainActor
enum AppAssembly {
    /// What every area is built with: the tunables, and the system's
    /// queues, clocks and timers.
    struct Basics {
        let configuration: AppConfiguration
        let queues: QueueMaking
        let clocks: Clocks
        let timers: RunLoopTimers
        /// The queue the model's own work is handed to.
        let work: WorkQueueing

        var pacing: Pacing { configuration.tunables.pacing }

        init(configuration: AppConfiguration) {
            self.configuration = configuration
            queues = DispatchQueues()
            clocks = .system
            timers = RunLoopTimers()
            work = DispatchWorkQueue()
        }
    }

    /// Size of the pictures in the effect picker, in the camera's shape.
    private static let thumbnailSize = CGSize(width: 320, height: 180)

    static func model(
        configuration: AppConfiguration, monitors: PreviewMonitors, airPlay: AirPlayOutput, cast: CastOutput
    ) -> AppModel {
        let basics = Basics(configuration: configuration)
        let sources = SourceSet(basics)
        let registry = sources.registry
        // One place every source's sound is heard from, by the mix and by captions alike.
        let taps = SoundTaps { registry.source(for: $0) as? SoundSource }
        let effects = EffectSet(basics, taps: taps)
        let outputs = OutputSet(basics)
        let renderLoop = renderLoop(basics, sources: sources, effects: effects, outputs: outputs, monitors: monitors)
        return AppModelAssembly.model(AppParts(
            picture: PictureParts(
                renderer: renderLoop,
                drawing: renderLoop,
                pictureSizes: sources.registry,
                overlayMeasurer: OverlayMeasurer(
                    factory: effects.library, pixels: effects.supplies.pixels, canvas: CameraContract.size
                ),
                programMonitor: monitors.program,
                fullScreenOutput: FullScreenOutput(monitor: outputs.fullScreenMonitor),
                sceneThumbnails: SceneThumbnailCapture(renderLoop: renderLoop, context: CIContext())
            ),
            sources: sources.parts(
                basics, effects: effects,
                thumbnailer: EffectThumbnailer(
                    factory: effects.library, transitions: effects.transitions, size: thumbnailSize,
                    framesPerSecond: basics.pacing.thumbnailFramesPerSecond
                )
            ),
            outputs: outputs.parts(airPlay: airPlay, cast: cast),
            sound: soundParts(basics, taps: taps, outputs: outputs),
            capture: outputs.captureParts(basics),
            control: ControlParts(
                midi: MIDIListener(main: .main), shortcuts: HotKeyListener(), scripts: AppleScriptRunner()
            ),
            system: SystemParts(
                keyValueStore: UserDefaults.standard,
                windows: AppKitWindowKeeper(),
                filing: DiskSetupFiling(),
                files: WorkspaceFiles(),
                permissions: CaptureCameraPermission(),
                scheduler: TimerScheduler(),
                timers: TimerScheduler(),
                refreshInterval: configuration.tunables.refreshInterval,
                queue: basics.work
            )
        ))
    }

    /// The loop that draws the picture and sends it everywhere it goes.
    private static func renderLoop(
        _ basics: Basics, sources: SourceSet, effects: EffectSet, outputs: OutputSet, monitors: PreviewMonitors
    ) -> RenderLoop {
        let registry = sources.registry
        let library = effects.library
        let supplies = effects.supplies
        return RenderLoop(
            sources: registry,
            makeRenderer: {
                SceneRenderer(sources: registry, effectFactory: library, canvas: CameraContract.size, supplies: supplies)
            },
            transitionFactory: effects.transitions,
            fallbackTransition: DissolveTransition(),
            programSinks: [monitors.program, monitors.studioProgram] + outputs.programSinks,
            // The camera extension offers one size, so the camera is always sent that.
            contractSinks: [outputs.cameraSink],
            previewSinks: [monitors.preview, monitors.studioPreview],
            pixelBuffers: PixelBufferPool(width: CameraContract.width, height: CameraContract.height),
            makeDetailBuffers: { PixelBufferPool(width: $0, height: $1) },
            clock: basics.clocks.today,
            context: RenderingSystem.makeContext(),
            queue: basics.queues.makeQueue(label: RenderLoop.queueLabel, qos: .userInteractive),
            onMain: RenderingSystem.mainHop,
            thumbnailWarmUp: basics.pacing.thumbnailWarmUp
        )
    }
}
