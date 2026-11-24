import CamTwistCore
import CamTwistRendering
import Foundation

/// Puts the model together from the system services it is given: the one
/// place that knows which type does each of the model's jobs. Each part of
/// the model has a small function of its own, and `model` composes them.
@MainActor
public enum AppModelAssembly {
    public static func model(_ parts: AppParts) -> AppModel {
        let effectParameters = EffectParameters(library: parts.sources.effectLibrary)
        let saved = SavedState(keyValueStore: parts.system.keyValueStore)
        // Every launch is a fresh start: only what stays with this Mac is brought back.
        let preferences = saved.load().applied(to: AppPreferences())
        let subModels = AppModelSubModels(
            choices: choices(parts.sources, system: parts.system, effectParameters: effectParameters),
            outputs: outputs(parts.outputs, sound: parts.sound, preferences: preferences, queue: parts.system.queue),
            gallery: SceneGallery(
                capturer: parts.picture.sceneThumbnails, queue: parts.system.queue, turns: SceneThumbnailTurns()
            ),
            capture: capture(parts.capture, picture: parts.picture, system: parts.system, preferences: preferences),
            fullScreen: fullScreen(parts.picture),
            remoteScreens: RemoteScreenPasswords(passwords: parts.sources.passwords)
        )
        let live = liveSettings(parts, recording: subModels.capture)
        return AppModel(
            parts: subModels,
            preferences: preferences,
            renderer: parts.picture.renderer,
            refreshTriggers: RefreshTriggers(
                permissions: parts.system.permissions, scheduler: parts.system.scheduler,
                interval: parts.system.refreshInterval, queue: parts.system.queue
            ),
            queue: parts.system.queue,
            helperMaker: StateHelperMaker(
                parts: parts, subModels: subModels, effectParameters: effectParameters, saved: saved, live: live
            )
        )
    }

    // MARK: The parts with jobs of their own

    static func choices(
        _ sources: SourceParts, system: SystemParts, effectParameters: EffectParameters
    ) -> ChoicesModel {
        let thumbnailer = sources.thumbnailer
        let fileChecker = sources.fileChecker
        let queue = system.queue
        return ChoicesModel(
            catalog: ChoiceCatalog(
                devices: sources.sourceChoices,
                pictures: sources.pictureCatalog,
                picturesDirectories: [sources.picturesDirectory],
                effectLibrary: sources.effectLibrary
            ),
            menu: EffectMenu(),
            effectParameters: effectParameters,
            makeMissingSources: {
                MissingSources(cameras: $0.cameras, screens: $0.screens, microphones: $0.microphones, files: fileChecker)
            },
            files: system.files,
            picturesDirectory: sources.picturesDirectory,
            effectsDirectory: sources.effectLibrary.directory,
            makeThumbnailLoader: { choices in
                ThumbnailLoader(thumbnailer: thumbnailer, queue: queue) { [weak choices] name, image in
                    choices?.thumbnailReady(image, forEffectNamed: name)
                }
            }
        )
    }

    static func outputs(
        _ outputs: OutputParts, sound: SoundParts, preferences: AppPreferences, queue: WorkQueueing
    ) -> OutputsModel {
        let streams = StreamsModel(
            preferences: preferences, webStream: outputs.webStream, webMovie: outputs.webMovie, rtmp: outputs.rtmp,
            links: WebStreamLinkLister(), addresses: outputs.addresses
        )
        return OutputsModel(
            camera: CameraOutputModel(
                connection: outputs.cameraConnection, use: CameraUse(processes: outputs.processes),
                installer: outputs.installer
            ),
            microphone: MicrophoneOutputModel(
                setup: MicrophoneSetup(installer: sound.microphoneInstaller, output: sound.microphone), queue: queue
            ),
            streams: streams,
            devices: DevicesModel(
                preferences: preferences, airPlay: outputs.airPlay, cast: outputs.cast, stream: streams
            )
        )
    }

    static func capture(
        _ capture: CaptureParts, picture: PictureParts, system: SystemParts, preferences: AppPreferences
    ) -> CaptureModel {
        CaptureModel(
            preferences: preferences,
            recorder: capture.recorder,
            snapshotTaker: SnapshotTaker(
                frames: picture.renderer, writer: capture.snapshots, folders: capture.folders, files: system.files
            ),
            files: system.files
        )
    }

    static func fullScreen(_ picture: PictureParts) -> FullScreenModel {
        FullScreenModel(
            covering: FullScreenController(output: picture.fullScreenOutput), output: picture.fullScreenOutput
        )
    }

    // MARK: What follows the model's state

    static func liveSettings(_ parts: AppParts, recording: RecordingReporting) -> LiveSettings {
        LiveSettings(
            applier: PreferenceApplier(
                monitor: parts.picture.programMonitor, windows: parts.system.windows,
                webStream: parts.outputs.webStream, webMovie: parts.outputs.webMovie,
                camera: parts.outputs.cameraConnection, rtmp: parts.outputs.rtmp, sound: parts.sound.sound,
                microphone: parts.sound.microphone, drawing: parts.picture.drawing,
                drawingSizes: DrawingSizeRule()
            ),
            sound: parts.sound.sound,
            sceneSound: SceneSoundReader(),
            recording: recording
        )
    }
}
