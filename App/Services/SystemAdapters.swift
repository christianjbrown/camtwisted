import AppKit
import AVFoundation
import CamTwistControl
import CamTwistCore
import CamTwistRendering
import Foundation
import Observation

// Thin adapters that let the model's protocols reach the real system. They
// hold no decisions; the model decides, these only do.
//
// Each is marked as a conformance added from outside the type's own
// library, which is what these are: the libraries do not know the model.

extension RenderLoop: @retroactive ProgramRendering, @retroactive ProgramFrameProviding {}

extension RenderLoop: @retroactive DrawingSizing {}

extension SourceRegistry: @retroactive SourcePictureSizing {
    public func pictureSize(ofSource id: UUID) -> CGSize? {
        latestFrame(for: id)?.extent.size
    }
}
extension OverlayMeasurer: @retroactive OverlayMeasuring {}
extension VirtualCameraSink: @retroactive CameraConnectionReporting {}
extension EffectThumbnailer: @retroactive EffectThumbnailing {}
extension MIDIListener: MIDINoteListening {}
extension FullScreenOutput: FullScreenPresenting {}
extension PreviewSink: PreviewMirroring {}
extension WebStreamOutput: @retroactive WebStreamSwitching {}
extension RTMPOutput: @retroactive RTMPSwitching {}
extension RecordingOutput: @retroactive RecordingSwitching {}

/// The addresses other devices on the network can reach this Mac at.
struct SystemAddresses: NetworkAddressListing {
    /// The return value of `getifaddrs` and `getnameinfo` when they work.
    private static let succeeded: Int32 = 0

    func localAddresses() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == Self.succeeded else { return [] }
        defer { freeifaddrs(first) }
        var addresses: [String] = []
        var next = first
        while let interface = next {
            defer { next = interface.pointee.ifa_next }
            let flags = Int32(interface.pointee.ifa_flags)
            // Up, on a network, and not this Mac talking to itself.
            guard let address = interface.pointee.ifa_addr,
                  ReachableInterface.qualifies(flags: flags, family: address.pointee.sa_family)
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == Self.succeeded {
                addresses.append(String(cString: host))
            }
        }
        return addresses
    }
}

/// The cameras, screens, windows and audio outputs of this Mac.
struct SystemSourceChoices: SourceChoiceListing {
    let cameraProvider: CameraSourceProvider
    let displayProvider: DisplaySourceProvider
    let windowProvider: WindowSourceProvider
    let microphoneProvider: MicrophoneSourceProvider

    func cameras() -> [CameraChoice] { cameraProvider.cameras() }
    func displays() -> [DisplayChoice] { displayProvider.displays() }
    func windows() -> [WindowChoice] { windowProvider.windows() }
    func audioOutputs() -> [AudioDeviceChoice] { AudioOutputDevices.all() }
    func microphones() -> [MicrophoneChoice] { microphoneProvider.microphones() }
}

/// Sets the level of every window the app has.
struct AppKitWindowKeeper: WindowKeeping {
    func keepOnTop(_ keeps: Bool) {
        // The model is made before the app itself exists, and says how its
        // windows should sit straight away: there are none to tell yet.
        for window in NSApp?.windows ?? [] {
            window.level = keeps ? .floating : .normal
        }
    }

    private var mainWindow: NSWindow? { NSApp?.windows.first { $0.isVisible && $0.canBecomeMain } }

    var contentSize: CGSize? { mainWindow.map { $0.contentRect(forFrameRect: $0.frame).size } }

    func resize(to size: CGSize) {
        guard let window = mainWindow else { return }
        // No bigger than the screen has room for.
        window.setContentSize(WindowFit.size(wanted: size, room: window.screen?.visibleFrame.size))
    }

    /// Back to the usual size, in the middle of its screen.
    func resetSize() {
        resize(to: Layout.windowSize)
        mainWindow?.center()
    }
}

/// Reads and writes setup files on disk.
struct DiskSetupFiling: SetupFiling {
    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

/// Finds the bundle of a running process.
struct RunningProcesses: ProcessLocating {
    func bundlePath(ofProcess process: Int32) -> String? {
        NSRunningApplication(processIdentifier: process)?.bundleURL?.path
    }
}

/// Asks the disk whether a file or folder is there.
struct DiskFileChecker: FileChecking {
    func exists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

/// Opens folders and shows files through Finder.
struct WorkspaceFiles: FileRevealing {
    func openFolder(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// The folders the system provides.
struct SystemFolders: DefaultFolders {
    /// Where snapshots and recordings go until a folder is chosen. The
    /// store build may not write to the Desktop, so it uses Movies.
    var desktopDirectory: URL {
        #if STORE
        let usual = FileManager.SearchPathDirectory.moviesDirectory
        #else
        let usual = FileManager.SearchPathDirectory.desktopDirectory
        #endif
        return FileManager.default.urls(for: usual, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
}

/// Asks the system for permission to use cameras.
struct CaptureCameraPermission: CameraPermissionRequesting {
    func requestVideoAccess(_ completion: @escaping () -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { _ in completion() }
    }
}

/// Repeating timers on the main run loop.
struct TimerScheduler: Scheduling {
    @MainActor
    func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        // The timers are meant to run as long as the app does.
        _ = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
    }
}

extension TimerScheduler: OneShotScheduling {
    @MainActor
    func after(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledWork {
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
    }
}

extension Timer: ScheduledWork {
    public func cancel() {
        invalidate()
    }
}

/// Moves work onto a utility queue and onto the main thread.
struct DispatchWorkQueue: WorkQueueing {
    private static let backgroundLabel = "camtwisted.background"

    private let backgroundQueue = DispatchQueue(label: DispatchWorkQueue.backgroundLabel, qos: .utility)

    func background(_ work: @escaping () -> Void) {
        backgroundQueue.async(execute: work)
    }

    func main(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in work() }
    }
}

/// The two monitors the window shows. They are views' business, so they
/// live here and not in the model.
@Observable
final class PreviewMonitors {
    let program: PreviewSink
    let preview: PreviewSink
    /// The studio window's own pair: a monitor draws in one place at a time.
    let studioProgram: PreviewSink
    let studioPreview: PreviewSink

    /// - Parameter main: the queue the monitors draw on.
    init(main: DispatchQueue) {
        program = PreviewSink(main: main)
        preview = PreviewSink(main: main)
        studioProgram = PreviewSink(main: main)
        studioPreview = PreviewSink(main: main)
    }
}
