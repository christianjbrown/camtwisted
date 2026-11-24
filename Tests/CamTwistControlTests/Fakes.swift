import CamTwistCore
import CamTwistRendering
import CoreGraphics
import CoreVideo
import Foundation
import XCTest
@testable import CamTwistControl

// Small hand-written stand-ins for everything the model reaches out to.

final class FakeRenderer: ProgramRendering {
    var latestProgramFrame: CVPixelBuffer?
    var programs: [SceneConfiguration] = []
    var previews: [SceneConfiguration?] = []
    var transitions: [(scene: SceneConfiguration, name: String, duration: TimeInterval)] = []
    var finishedHandler: ((SceneConfiguration) -> Void)?
    var startCount = 0

    func setProgram(_ scene: SceneConfiguration) { programs.append(scene) }
    func setPreview(_ scene: SceneConfiguration?) { previews.append(scene) }
    func startTransition(to scene: SceneConfiguration, named name: String, duration: TimeInterval) {
        transitions.append((scene, name, duration))
    }
    func onTransitionFinished(_ handler: @escaping (SceneConfiguration) -> Void) { finishedHandler = handler }
    func start() { startCount += 1 }

    /// Tells the model the last transition asked for has reached its target.
    func finishTransition() {
        if let last = transitions.last { finishedHandler?(last.scene) }
    }
}

final class FakeKeyValueStore: KeyValueStore {
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data?, forKey key: String) { values[key] = data }
}

final class FakeScripts: ScriptRunning {
    var sources: [String] = []
    func run(_ source: String) { sources.append(source) }
}

final class FakeSnapshotWriter: SnapshotWriting {
    var result: URL?
    var written: [URL] = []
    func write(_ pixelBuffer: CVPixelBuffer, to directory: URL) -> URL? {
        written.append(directory)
        return result
    }
}

final class FakeEffectThumbnailer: EffectThumbnailing {
    var images: [String: CGImage] = [:]
    var asked: [String] = []
    func thumbnail(forEffectNamed name: String) -> CGImage? {
        asked.append(name)
        return images[name]
    }

    var askedTransitions: [String] = []
    func thumbnail(forTransitionNamed name: String) -> CGImage? {
        askedTransitions.append(name)
        return images[name]
    }
}

@MainActor
final class FakeFullScreen: FullScreenPresenting {
    var onClose: (() -> Void)?
    var connected: Set<UInt32> = []
    var shown: [UInt32] = []
    var hideCount = 0
    func show(onDisplay displayID: UInt32) -> Bool {
        shown.append(displayID)
        return connected.contains(displayID)
    }
    func hide() { hideCount += 1 }
}

final class FakeInstaller: CameraInstalling {
    var state = CameraInstallState.unknown {
        didSet { onChange?() }
    }
    var installCount = 0
    var refreshCount = 0
    var onChange: (() -> Void)?
    var removeCount = 0
    func install() { installCount += 1 }
    func remove() { removeCount += 1 }
    func refresh() { refreshCount += 1 }
}

final class FakeCameraConnection: CameraConnectionReporting {
    var isConnected = false
    var isEnabled = true
    var watcherProcessIDs: [Int32] = []
}

@MainActor
final class FakeWindows: WindowKeeping {
    var calls: [Bool] = []
    func keepOnTop(_ keeps: Bool) { calls.append(keeps) }
    var contentSize: CGSize?
    var resizes: [CGSize] = []
    func resize(to size: CGSize) { resizes.append(size) }
    var resetCount = 0
    func resetSize() { resetCount += 1 }
}

final class FakeMonitor: PreviewMirroring {
    var isMirrored = false
}

final class FakeWebStream: WebStreamSwitching {
    var applied: [WebStreamSettings] = []
    var sound: [Bool] = []
    var status = WebStreamStatus.off
    var marked: [String] = []
    func apply(_ settings: WebStreamSettings, withSound: Bool) {
        applied.append(settings)
        sound.append(withSound)
    }

    func markScene(named name: String) { marked.append(name) }
}

final class FakeSound: SoundCapturing {
    var applied: [SoundSettings] = []
    var levels: [[UUID: Double]] = []
    func apply(_ settings: SoundSettings) { applied.append(settings) }
    func setSourceLevels(_ levels: [UUID: Double]) { self.levels.append(levels) }
}

final class FakeDrawing: DrawingSizing {
    var sizes: [DrawingSize] = []
    func setDrawingSize(_ size: DrawingSize) { sizes.append(size) }
}

final class FakeMicrophone: MicrophoneSwitching {
    var changes: [Bool] = []
    var isEnabled = false {
        didSet { changes.append(isEnabled) }
    }
}

final class FakeMicrophoneInstaller: MicrophoneInstalling {
    var isInstalled = false
    var installs: [(String?) -> Void] = []
    var removals: [(String?) -> Void] = []
    func install(_ completion: @escaping (String?) -> Void) { installs.append(completion) }
    func remove(_ completion: @escaping (String?) -> Void) { removals.append(completion) }
}

final class FakeRTMP: RTMPSwitching {
    var applied: [RTMPSettings] = []
    var sound: [Bool] = []
    var status = RTMPState.idle
    var marked: [String] = []
    func apply(_ settings: RTMPSettings, withSound: Bool) {
        applied.append(settings)
        sound.append(withSound)
    }

    func markScene(named name: String) { marked.append(name) }
}

final class FakeAirPlay: AirPlaySwitching {
    var applied: [(isOn: Bool, address: String?)] = []
    func apply(isOn: Bool, address: String?) { applied.append((isOn, address)) }
}

final class FakeCast: CastSwitching {
    var applied: [(isOn: Bool, address: String?, deviceName: String?)] = []
    func apply(isOn: Bool, address: String?, deviceName: String?) { applied.append((isOn, address, deviceName)) }
}

final class FakeAddresses: NetworkAddressListing {
    var hosts: [String] = []
    func localAddresses() -> [String] { hosts }
}

final class FakeFiles: FileRevealing {
    var opened: [URL] = []
    var revealed: [URL] = []
    func openFolder(_ url: URL) { opened.append(url) }
    func reveal(_ url: URL) { revealed.append(url) }
}

final class FakePasswords: PasswordKeeping {
    var kept: [String: String] = [:]
    func password(for account: String) -> String? { kept[account] }
    func setPassword(_ password: String, for account: String) { kept[account] = password.isEmpty ? nil : password }
}

final class FakeRecorder: RecordingSwitching {
    var status = RecordingStatus.off
    var applied: [(isOn: Bool, folder: URL, sceneName: String, options: RecordingOptions)] = []
    var marked: [String] = []
    func apply(isOn: Bool, folder: URL, sceneName: String, options: RecordingOptions) {
        applied.append((isOn, folder, sceneName, options))
    }
    func markScene(named name: String) { marked.append(name) }
}

final class FakeSceneThumbnails: SceneThumbnailCapturing {
    var isBusy = false
    var requests: [(scene: SceneConfiguration, completion: (CGImage?) -> Void)] = []
    func captureThumbnail(of scene: SceneConfiguration, completion: @escaping (CGImage?) -> Void) -> Bool {
        guard !isBusy else { return false }
        requests.append((scene, completion))
        return true
    }
}

final class FakeProcesses: ProcessLocating {
    var paths: [Int32: String] = [:]
    func bundlePath(ofProcess process: Int32) -> String? { paths[process] }
}

final class FakeFileChecker: FileChecking {
    var existing: Set<String> = []
    func exists(atPath path: String) -> Bool { existing.contains(path) }
}

struct FakeFolders: DefaultFolders {
    var desktopDirectory = URL(fileURLWithPath: "/desktop")
}

final class FakePermissions: CameraPermissionRequesting {
    var completions: [() -> Void] = []
    func requestVideoAccess(_ completion: @escaping () -> Void) { completions.append(completion) }
}

@MainActor
final class FakeScheduler: Scheduling {
    var timers: [(interval: TimeInterval, action: @MainActor () -> Void)] = []
    func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        timers.append((interval, action))
    }
    func fire(_ index: Int) { timers[index].action() }
}

/// Runs everything on the spot, on the main actor the tests live on.
final class ImmediateQueue: WorkQueueing, @unchecked Sendable {
    func background(_ work: @escaping () -> Void) { work() }
    func main(_ work: @escaping @MainActor () -> Void) {
        MainActor.assumeIsolated { work() }
    }
}

@MainActor
final class FakeShortcuts: ShortcutListening {
    var onPress: ((SceneShortcut) -> Void)?
    var listenedFor: [[SceneShortcut]] = []
    func listen(for shortcuts: [SceneShortcut]) { listenedFor.append(shortcuts) }
}

final class FakeWork: ScheduledWork {
    var isCancelled = false
    func cancel() { isCancelled = true }
}

/// Keeps what it is asked to do later, to be done when a test says.
@MainActor
final class FakeTimers: OneShotScheduling {
    var scheduled: [(seconds: TimeInterval, action: @MainActor () -> Void, work: FakeWork)] = []
    func after(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledWork {
        let work = FakeWork()
        scheduled.append((seconds, action, work))
        return work
    }
    func fire(_ index: Int) { scheduled[index].action() }
}

final class FakeMIDI: MIDINoteListening {
    var onNote: ((Int) -> Void)?
    var startCount = 0
    func start() { startCount += 1 }
}

final class FakePictureSizes: SourcePictureSizing {
    var sizes: [UUID: CGSize] = [:]
    func pictureSize(ofSource id: UUID) -> CGSize? { sizes[id] }
}

final class FakeOverlayMeasurer: OverlayMeasuring {
    var bounds: [String: CGRect] = [:]
    func bounds(ofEffectNamed name: String, values: [String: EffectValue]) -> CGRect? { bounds[name] }
}

final class FakeSourceChoices: SourceChoiceListing {
    var cameraList: [CameraChoice] = []
    var displayList: [DisplayChoice] = []
    var windowList: [WindowChoice] = []
    var audioList: [AudioDeviceChoice] = []
    func cameras() -> [CameraChoice] { cameraList }
    func displays() -> [DisplayChoice] { displayList }
    func windows() -> [WindowChoice] { windowList }
    func audioOutputs() -> [AudioDeviceChoice] { audioList }
    var microphoneList: [MicrophoneChoice] = []
    func microphones() -> [MicrophoneChoice] { microphoneList }
}

struct FakeDirectoryListing: DirectoryListing {
    var urls: [URL] = []
    /// What particular folders hold, for tests with more than one folder.
    var urlsByDirectory: [String: [URL]] = [:]
    var fails = false
    struct Failure: Error {}
    func files(in directory: URL) throws -> [URL] {
        if fails { throw Failure() }
        return urlsByDirectory[directory.path] ?? urls
    }
}

final class FakeEffectLibrary: EffectLibrary {
    var directory = URL(fileURLWithPath: "/effects")
    var listings: [EffectListing] = []
    var controls: [String: [EffectParameter]] = [:]
    var parameterRequests: [String] = []
    func availableEffects() -> [EffectListing] { listings }
    func parameters(forEffectNamed name: String) -> [EffectParameter] {
        parameterRequests.append(name)
        return controls[name] ?? []
    }
}

/// The state the helper types work on, held in plain properties.
@MainActor
final class FakeState: StudioState, SetupDocumentState, FollowedState, KeyPlayedState, PictureState, ScriptedState,
    StepEditingState {
    var scene = SceneConfiguration()
    var studio = StudioSettings()
    var studioPreview: SceneConfiguration?
    var editedSceneID: UUID?
    var isTransitioning = false
    var preferences = AppPreferences()
    var documentURL: URL?
    var setupProblem: String?
    var startsAfresh = false
    var freshScenes = 0
    func startFreshScene() {
        freshScenes += 1
        scene = SceneConfiguration(items: [sourceItem(.colorBars)])
    }

    var selectedStepID: UUID?
    var isEditedSceneLocked = false
    /// The scene being changed is the one on air here.
    var editedScene: SceneConfiguration {
        get { scene }
        set { scene = newValue }
    }
    var wentLive: [UUID] = []
    func goLive(withScene id: UUID) { wentLive.append(id) }
    var performed: [TriggerAction] = []
    func performOnMain(_ action: TriggerAction) { performed.append(action) }
    var branchTarget: UUID?
    var expandedSteps: Set<UUID> = []
}

/// Keeps the steps it is asked to add.
@MainActor
final class FakeStepAdder: StepAdding {
    var added: [ChainItem.Content] = []
    func add(_ content: ChainItem.Content) { added.append(content) }
}

/// Setup files held in a dictionary, with failures on request.
final class FakeSetupFiling: SetupFiling {
    struct Refusal: Error {}
    var files: [URL: Data] = [:]
    var fails = false

    func read(from url: URL) throws -> Data {
        if fails { throw Refusal() }
        guard let data = files[url] else { throw Refusal() }
        return data
    }

    func write(_ data: Data, to url: URL) throws {
        if fails { throw Refusal() }
        files[url] = data
    }
}

func makePixelBuffer() -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, 4, 4, kCVPixelFormatType_32BGRA, nil, &buffer)
    return buffer!
}

func makeImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}

func effectItem(_ name: String, values: [String: EffectValue] = [:], enabled: Bool = true) -> ChainItem {
    ChainItem(isEnabled: enabled, content: .effect(name: name, values: values))
}

func sourceItem(_ spec: SourceSpec, enabled: Bool = true, pip: PictureInPictureSettings? = nil) -> ChainItem {
    ChainItem(isEnabled: enabled, content: .source(spec), pictureInPicture: pip)
}

func numberControl(_ key: String, name: String, value: Double = 0.5) -> EffectParameter {
    EffectParameter(key: key, displayName: name, kind: .number, defaultValue: .number(value), range: nil)
}
