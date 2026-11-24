import CamTwistCore
import CamTwistRendering
import Foundation

// What the app hands the assembly, grouped by area. Adding a collaborator
// touches one of these and the one small function that uses it.

/// What draws the picture and shows it on this Mac.
public struct PictureParts {
    let renderer: ProgramRendering
    let drawing: DrawingSizing
    let pictureSizes: SourcePictureSizing
    let overlayMeasurer: OverlayMeasuring
    let programMonitor: PreviewMirroring
    let fullScreenOutput: FullScreenPresenting
    let sceneThumbnails: SceneThumbnailCapturing

    public init(
        renderer: ProgramRendering,
        drawing: DrawingSizing,
        pictureSizes: SourcePictureSizing,
        overlayMeasurer: OverlayMeasuring,
        programMonitor: PreviewMirroring,
        fullScreenOutput: FullScreenPresenting,
        sceneThumbnails: SceneThumbnailCapturing
    ) {
        self.renderer = renderer
        self.drawing = drawing
        self.pictureSizes = pictureSizes
        self.overlayMeasurer = overlayMeasurer
        self.programMonitor = programMonitor
        self.fullScreenOutput = fullScreenOutput
        self.sceneThumbnails = sceneThumbnails
    }
}

/// What there is to make a scene from: devices, pictures and effects.
public struct SourceParts {
    let effectLibrary: EffectLibrary
    let sourceChoices: SourceChoiceListing
    let thumbnailer: EffectThumbnailing
    let pictureCatalog: PictureCatalog
    let picturesDirectory: URL
    let fileChecker: FileChecking
    let passwords: PasswordKeeping

    public init(
        effectLibrary: EffectLibrary,
        sourceChoices: SourceChoiceListing,
        thumbnailer: EffectThumbnailing,
        pictureCatalog: PictureCatalog,
        picturesDirectory: URL,
        fileChecker: FileChecking,
        passwords: PasswordKeeping
    ) {
        self.effectLibrary = effectLibrary
        self.sourceChoices = sourceChoices
        self.thumbnailer = thumbnailer
        self.pictureCatalog = pictureCatalog
        self.picturesDirectory = picturesDirectory
        self.fileChecker = fileChecker
        self.passwords = passwords
    }
}

/// Where the picture goes: the virtual camera, the streams and the players.
public struct OutputParts {
    let installer: CameraInstalling
    let cameraConnection: CameraConnectionReporting
    let processes: ProcessLocating
    let webStream: WebStreamSwitching
    let webMovie: WebStreamSwitching
    let rtmp: RTMPSwitching
    let airPlay: AirPlaySwitching
    let cast: CastSwitching
    let addresses: NetworkAddressListing

    public init(
        installer: CameraInstalling,
        cameraConnection: CameraConnectionReporting,
        processes: ProcessLocating,
        webStream: WebStreamSwitching,
        webMovie: WebStreamSwitching,
        rtmp: RTMPSwitching,
        airPlay: AirPlaySwitching,
        cast: CastSwitching,
        addresses: NetworkAddressListing
    ) {
        self.installer = installer
        self.cameraConnection = cameraConnection
        self.processes = processes
        self.webStream = webStream
        self.webMovie = webMovie
        self.rtmp = rtmp
        self.airPlay = airPlay
        self.cast = cast
        self.addresses = addresses
    }
}

/// The mix of what is heard, and the virtual microphone it is played to.
public struct SoundParts {
    let sound: SoundCapturing
    let microphone: MicrophoneSwitching
    let microphoneInstaller: MicrophoneInstalling

    public init(sound: SoundCapturing, microphone: MicrophoneSwitching, microphoneInstaller: MicrophoneInstalling) {
        self.sound = sound
        self.microphone = microphone
        self.microphoneInstaller = microphoneInstaller
    }
}

/// What keeps the picture: the recorder and the snapshot writer.
public struct CaptureParts {
    let recorder: RecordingSwitching
    let snapshots: SnapshotWriting
    let folders: DefaultFolders

    public init(recorder: RecordingSwitching, snapshots: SnapshotWriting, folders: DefaultFolders) {
        self.recorder = recorder
        self.snapshots = snapshots
        self.folders = folders
    }
}

/// What the system offers: storage, windows, files and timing.
public struct SystemParts {
    let keyValueStore: KeyValueStore
    let windows: WindowKeeping
    let filing: SetupFiling
    let files: FileRevealing
    let permissions: CameraPermissionRequesting
    let scheduler: Scheduling
    let timers: OneShotScheduling
    let refreshInterval: TimeInterval
    let queue: WorkQueueing

    public init(
        keyValueStore: KeyValueStore,
        windows: WindowKeeping,
        filing: SetupFiling,
        files: FileRevealing,
        permissions: CameraPermissionRequesting,
        scheduler: Scheduling,
        timers: OneShotScheduling,
        refreshInterval: TimeInterval,
        queue: WorkQueueing
    ) {
        self.keyValueStore = keyValueStore
        self.windows = windows
        self.filing = filing
        self.files = files
        self.permissions = permissions
        self.scheduler = scheduler
        self.timers = timers
        self.refreshInterval = refreshInterval
        self.queue = queue
    }
}

/// The ways of driving the app other than the window: MIDI keys, keyboard
/// shortcuts and scripts.
public struct ControlParts {
    let midi: MIDINoteListening
    let shortcuts: ShortcutListening
    let scripts: ScriptRunning

    public init(midi: MIDINoteListening, shortcuts: ShortcutListening, scripts: ScriptRunning) {
        self.midi = midi
        self.shortcuts = shortcuts
        self.scripts = scripts
    }
}

/// Everything the app hands in, by area.
public struct AppParts {
    let picture: PictureParts
    let sources: SourceParts
    let outputs: OutputParts
    let sound: SoundParts
    let capture: CaptureParts
    let control: ControlParts
    let system: SystemParts

    public init(
        picture: PictureParts,
        sources: SourceParts,
        outputs: OutputParts,
        sound: SoundParts,
        capture: CaptureParts,
        control: ControlParts,
        system: SystemParts
    ) {
        self.picture = picture
        self.sources = sources
        self.outputs = outputs
        self.sound = sound
        self.capture = capture
        self.control = control
        self.system = system
    }
}
