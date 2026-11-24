import CamTwistCore
import CamTwistRendering
import CoreGraphics
import CoreVideo
import Foundation

// The narrow views of the outside world that the model works through. The
// app hands in the real ones; tests hand in fakes.

/// Where the latest picture on air can be read.
public protocol ProgramFrameProviding {
    var latestProgramFrame: CVPixelBuffer? { get }
}

/// What the model asks of the render loop.
public protocol ProgramRendering: ProgramFrameProviding {
    func setProgram(_ scene: SceneConfiguration)
    func setPreview(_ scene: SceneConfiguration?)
    func startTransition(to scene: SceneConfiguration, named name: String, duration: TimeInterval)
    func onTransitionFinished(_ handler: @escaping (SceneConfiguration) -> Void)
    func start()
}

/// Draws the finished picture with more or less detail.
public protocol DrawingSizing: AnyObject {
    func setDrawingSize(_ size: DrawingSize)
}

/// Tells how big a source's own picture is, once it has one.
public protocol SourcePictureSizing {
    func pictureSize(ofSource id: UUID) -> CGSize?
}

/// Tells where an effect draws on the picture, in fractions of it with the
/// origin at the bottom left, or nil when it draws nothing of its own.
public protocol OverlayMeasuring {
    func bounds(ofEffectNamed name: String, values: [String: EffectValue]) -> CGRect?
}

/// Lists the things on this Mac that can be picked as sources.
public protocol SourceChoiceListing {
    func cameras() -> [CameraChoice]
    func displays() -> [DisplayChoice]
    func windows() -> [WindowChoice]
    func audioOutputs() -> [AudioDeviceChoice]
    func microphones() -> [MicrophoneChoice]
}

/// Serves the picture to other devices on the local network.
public protocol WebStreamSwitching: AnyObject {
    func apply(_ settings: WebStreamSettings, withSound: Bool)
    /// Marks a scene coming on air, when the stream is set to mark them.
    func markScene(named name: String)
    var status: WebStreamStatus { get }
}

/// Sends the picture to an RTMP server.
public protocol RTMPSwitching: AnyObject {
    func apply(_ settings: RTMPSettings, withSound: Bool)
    /// Marks a scene coming on air, when the stream is set to mark them.
    func markScene(named name: String)
    var status: RTMPState { get }
}

/// Records the picture on air to a movie.
public protocol RecordingSwitching: AnyObject {
    var status: RecordingStatus { get }
    /// Starts a recording in a folder, made the way the options say, or
    /// ends the one under way.
    func apply(isOn: Bool, folder: URL, sceneName: String, options: RecordingOptions)
    /// A different scene has come on air.
    func markScene(named name: String)
}

/// Plays the picture on a Cast device, such as a Chromecast.
public protocol CastSwitching: AnyObject {
    /// Switches it on or off. `address` is where the device fetches the
    /// stream from, and `deviceName` is which device, as it names itself.
    func apply(isOn: Bool, address: String?, deviceName: String?)
}

/// Plays the picture on an AirPlay device, such as an Apple TV.
public protocol AirPlaySwitching: AnyObject {
    /// Switches it on or off. `address` is where the device fetches the
    /// stream from: the HLS stream this Mac serves.
    func apply(isOn: Bool, address: String?)
}

/// Mixes the sound of the sources on air for the streams that carry it.
public protocol SoundCapturing: AnyObject {
    func apply(_ settings: SoundSettings)
    /// Says which sources in the scene on air are heard, and how loud.
    func setSourceLevels(_ levels: [UUID: Double])
}

/// Tells which addresses other devices can reach this Mac at.
public protocol NetworkAddressListing {
    func localAddresses() -> [String]
}

/// Reports the MIDI notes that are pressed.
public protocol MIDINoteListening: AnyObject {
    var onNote: ((Int) -> Void)? { get set }
    func start()
}

/// Runs AppleScript source.
public protocol ScriptRunning {
    func run(_ source: String)
}

/// Saves a frame as a picture file.
public protocol SnapshotWriting {
    /// Saves into a folder, making it if needed. Returns where the picture
    /// went, or nil when it could not be saved.
    func write(_ pixelBuffer: CVPixelBuffer, to directory: URL) -> URL?
}

/// Makes the small picture of what an effect does.
public protocol EffectThumbnailing {
    func thumbnail(forEffectNamed name: String) -> CGImage?
    /// A picture of a transition half way between two scenes.
    func thumbnail(forTransitionNamed name: String) -> CGImage?
}

/// Shows the program picture filling one screen.
@MainActor
public protocol FullScreenPresenting: AnyObject {
    /// Called when the output closes by itself.
    var onClose: (() -> Void)? { get set }
    /// Covers the display. Returns false when that display is not connected.
    func show(onDisplay displayID: UInt32) -> Bool
    func hide()
}

/// Where the virtual camera stands on this Mac.
public enum CameraInstallState: Equatable {
    case unknown
    case installed
    case installing
    case needsApproval
    case failed(String)
}

/// Where the virtual microphone stands on this Mac.
public enum MicrophoneInstallState: Equatable {
    case notInstalled
    case installing
    case installed
    case failed(String)
}

/// Puts the virtual microphone's audio driver on this Mac and takes it away.
public protocol MicrophoneInstalling: AnyObject {
    /// Whether the system has the microphone right now.
    var isInstalled: Bool { get }
    /// Asks for an administrator and installs. Calls back, on any queue,
    /// with what went wrong or nil.
    func install(_ completion: @escaping (String?) -> Void)
    func remove(_ completion: @escaping (String?) -> Void)
}

/// Whether the mix is played to the virtual microphone.
public protocol MicrophoneSwitching: AnyObject {
    var isEnabled: Bool { get set }
}

/// Installs and updates the camera extension.
public protocol CameraInstalling: AnyObject {
    var state: CameraInstallState { get }
    func install()
    /// Takes the camera off this Mac again.
    func remove()
    func refresh()
    /// Called each time the state has changed.
    var onChange: (() -> Void)? { get set }
}

/// Whether anything is reading the virtual camera.
public protocol CameraConnectionReporting: AnyObject {
    var isConnected: Bool { get }
    /// The processes that have the camera's picture open, as the camera reports them.
    var watcherProcessIDs: [Int32] { get }
    /// Whether the picture is sent to the camera at all.
    var isEnabled: Bool { get set }
}

/// Keeps the app's windows above the others, or lets them settle.
@MainActor
public protocol WindowKeeping {
    func keepOnTop(_ keeps: Bool)
    /// How big the main window's content is, in points, when there is a window.
    var contentSize: CGSize? { get }
    func resize(to size: CGSize)
    /// Puts the window back to its usual size.
    func resetSize()
}

/// A monitor that can show its picture the other way round.
public protocol PreviewMirroring: AnyObject {
    var isMirrored: Bool { get set }
}

/// Shows folders and files to the user.
public protocol FileRevealing {
    /// Opens a folder, making it first if it does not exist yet.
    func openFolder(_ url: URL)
    /// Shows a file selected in its folder.
    func reveal(_ url: URL)
}

/// Where the system keeps the folders the app falls back on.
public protocol DefaultFolders {
    var desktopDirectory: URL { get }
}

/// Asks for permission to use cameras.
public protocol CameraPermissionRequesting {
    /// Calls back, on any thread, once the answer is known.
    func requestVideoAccess(_ completion: @escaping () -> Void)
}

/// Something waiting to be done later, which can be called off.
public protocol ScheduledWork {
    func cancel()
}

/// Work done once, a while from now, on the main actor.
@MainActor
public protocol OneShotScheduling {
    func after(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledWork
}

/// Reports presses of keyboard shortcuts, whichever app is in front.
@MainActor
public protocol ShortcutListening: AnyObject {
    var onPress: ((SceneShortcut) -> Void)? { get set }
    /// Listens for these shortcuts from now on, and no others.
    func listen(for shortcuts: [SceneShortcut])
}

/// Repeating timers on the main actor.
@MainActor
public protocol Scheduling {
    func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void)
}

/// Moves work between threads. Tests run it on the spot.
public protocol WorkQueueing: Sendable {
    /// Runs work off the main thread.
    func background(_ work: @escaping () -> Void)
    /// Runs work on the main actor.
    func main(_ work: @escaping @MainActor () -> Void)
}

/// Lets the person pick files or folders.
public protocol FileChoosing {
    /// The paths chosen, or none when the person gave up. An empty set of
    /// extensions means folders only.
    func chooseFiles(allowedExtensions: Set<String>, allowsFolders: Bool, allowsMany: Bool) -> [String]
}

/// Lets the person pick where a setup file is opened from or saved to.
public protocol SetupFileChoosing {
    func chooseSetupToOpen() -> URL?
    /// - Parameter suggestedName: the name of the file the setup came from, if any.
    func chooseSetupToSave(suggestedName: String?) -> URL?
}
