import CamTwistCore
import CoreImage
import ScreenCaptureKit

/// One window as a source, captured even while other windows cover it.
public final class WindowSource: FrameSource, SoundSource {
    public var onSound: ((CMSampleBuffer) -> Void)? {
        get { receiver.listener.get() }
        set { receiver.listener.set(newValue) }
    }

    private let settings: WindowSettings
    /// Seconds to wait before looking again for the window.
    private let retryDelay: TimeInterval
    private let receiver: ScreenStreamReceiver
    private let sleep: Sleeper
    private var stream: SCStream?
    private var startTask: Task<Void, Never>?

    init(settings: WindowSettings, retryDelay: TimeInterval, receiver: ScreenStreamReceiver, sleep: @escaping Sleeper) {
        self.receiver = receiver
        self.sleep = sleep
        self.settings = settings
        self.retryDelay = retryDelay
    }

    public var latestFrame: CIImage? { receiver.frames.load() }

    public func start() {
        guard startTask == nil else { return }
        startTask = Task { [weak self] in
            // The window may not be open yet, so keep looking until it is.
            while let self, !Task.isCancelled, self.stream == nil {
                await self.startCapture()
                try? await self.sleep(self.retryDelay)
            }
        }
    }

    public func stop() {
        startTask?.cancel()
        startTask = nil
        let stream = self.stream
        self.stream = nil
        receiver.frames.store(nil)
        Task { try? await stream?.stopCapture() }
    }

    public func update(to spec: SourceSpec) -> Bool {
        spec == .window(settings)
    }

    private func startCapture() async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false),
              let window = content.windows.first(where: matches)
        else { return }
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(SCContentFilter(desktopIndependentWindow: window).pointPixelScale)
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = ScreenStreamDefaults.frameInterval
        ScreenStreamReceiver.addSound(to: configuration)
        let stream = SCStream(
            filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration, delegate: nil
        )
        do {
            try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: receiver.queue)
            try stream.addStreamOutput(receiver, type: .audio, sampleHandlerQueue: receiver.soundQueue)
            try await stream.startCapture()
            self.stream = stream
        } catch {
            return
        }
    }

    private func matches(_ window: SCWindow) -> Bool {
        WindowSelection.isMatch(
            title: window.title, application: window.owningApplication?.applicationName, settings: settings
        )
    }
}

/// A window the user can pick.
public struct WindowChoice: Identifiable, Equatable {
    public let title: String
    public let application: String

    public var id: String { application + "\n" + title }
}

public struct WindowSourceProvider: SourceProvider {
    /// Seconds a window source waits before looking again for its window.
    private let retryDelay: TimeInterval
    /// The process identifier of this app, whose own windows are left out.
    private let ownProcessIdentifier: Int32
    private let sleep: Sleeper
    private let queues: QueueMaking

    public init(retryDelay: TimeInterval, ownProcessIdentifier: Int32, sleep: @escaping Sleeper, queues: QueueMaking) {
        self.sleep = sleep
        self.queues = queues
        self.retryDelay = retryDelay
        self.ownProcessIdentifier = ownProcessIdentifier
    }

    /// The titled windows currently open, without this app's own.
    public func windows() -> [WindowChoice] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return WindowSelection.choices(from: list, excludingProcess: ownProcessIdentifier)
    }

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .window(let settings) = spec else { return nil }
        return WindowSource(
            settings: settings, retryDelay: retryDelay, receiver: ScreenStreamReceiver(queues: queues), sleep: sleep
        )
    }
}
