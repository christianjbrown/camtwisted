import AppKit
import CamTwistCore
import CoreImage
import ScreenCaptureKit

/// Receives screen frames from ScreenCaptureKit and keeps the latest.
final class ScreenStreamReceiver: NSObject, SCStreamOutput {
    let frames = LatestFrameBox()
    /// The label of the queue that receives screen frames.
    private static let queueLabel = "source.screen"
    let queue: DispatchQueue
    /// The label of the queue that receives screen sound.
    private static let soundQueueLabel = "source.screen.sound"
    let soundQueue: DispatchQueue
    /// Where the sound that comes with the picture goes, when anybody is listening.
    let listener = Locked<((CMSampleBuffer) -> Void)?>(nil)

    init(queue: DispatchQueue, soundQueue: DispatchQueue) {
        self.queue = queue
        self.soundQueue = soundQueue
    }

    /// A receiver on queues of its own, made by what it is handed.
    convenience init(queues: QueueMaking) {
        self.init(
            queue: queues.makeQueue(label: Self.queueLabel, qos: .userInteractive),
            soundQueue: queues.makeQueue(label: Self.soundQueueLabel, qos: .userInteractive)
        )
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio {
            listener.get()?(sampleBuffer)
            return
        }
        guard type == .screen, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frames.store(CIImage(cvPixelBuffer: pixelBuffer))
    }

    /// Asks a stream for the sound that goes with its picture: everything
    /// the Mac plays for a screen, the one app's for a window. This app's
    /// own sound is left out, or it would hear itself.
    static func addSound(to configuration: SCStreamConfiguration) {
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = ScreenStreamDefaults.sampleRate
        configuration.channelCount = ScreenStreamDefaults.channels
    }
}

enum ScreenStreamDefaults {
    static let sampleRate = 48000
    static let channels = 2
    static let frameInterval = CMTime(value: 1, timescale: CMTimeScale(CameraContract.framesPerSecond))
}

/// A display, or part of one, as a source.
public final class DisplaySource: FrameSource, SoundSource {
    public var onSound: ((CMSampleBuffer) -> Void)? {
        get { receiver.listener.get() }
        set { receiver.listener.set(newValue) }
    }

    private let settings: Locked<DisplaySettings>
    private let receiver: ScreenStreamReceiver
    private var stream: SCStream?
    private var startTask: Task<Void, Never>?

    init(settings: DisplaySettings, receiver: ScreenStreamReceiver) {
        self.receiver = receiver
        self.settings = Locked(settings)
    }

    public var latestFrame: CIImage? {
        guard let frame = receiver.frames.load() else { return nil }
        return DisplayCapture.framed(frame, settings: settings.get(), pointer: pointerPosition)
    }

    public func start() {
        guard startTask == nil else { return }
        let displayID = settings.get().displayID
        let showsCursor = settings.get().showsCursor
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
                let configuration = SCStreamConfiguration()
                let scale = NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 1
                configuration.width = DisplayCapture.pixels(CGFloat(display.width), scale: scale)
                configuration.height = DisplayCapture.pixels(CGFloat(display.height), scale: scale)
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.minimumFrameInterval = ScreenStreamDefaults.frameInterval
                configuration.showsCursor = showsCursor
                ScreenStreamReceiver.addSound(to: configuration)
                let stream = SCStream(
                    filter: SCContentFilter(display: display, excludingWindows: []),
                    configuration: configuration,
                    delegate: nil
                )
                try stream.addStreamOutput(self.receiver, type: .screen, sampleHandlerQueue: self.receiver.queue)
                try stream.addStreamOutput(self.receiver, type: .audio, sampleHandlerQueue: self.receiver.soundQueue)
                try await stream.startCapture()
                self.stream = stream
            } catch {
                self.startTask = nil
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
        guard case .display(let new) = spec else { return false }
        let old = settings.get()
        // A different display or cursor setting needs a new stream.
        guard DisplayCapture.keepsStream(from: old, to: new) else { return false }
        settings.set(new)
        return true
    }

    /// Where the pointer is on this display, in unit coordinates.
    private func pointerPosition() -> CGPoint {
        let displayID = settings.get().displayID
        let frame = NSScreen.screens.first(where: { $0.displayID == displayID })?.frame
        return DisplayCapture.unitPosition(of: NSEvent.mouseLocation, on: frame)
    }
}

extension NSScreen {
    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    var displayID: CGDirectDisplayID? {
        (deviceDescription[Self.screenNumberKey] as? NSNumber)?.uint32Value
    }
}

/// A display the user can pick.
public struct DisplayChoice: Identifiable, Equatable {
    public let id: UInt32
    public let name: String
}

public struct DisplaySourceProvider: SourceProvider {
    private let queues: QueueMaking

    public init(queues: QueueMaking) {
        self.queues = queues
    }

    public func displays() -> [DisplayChoice] {
        NSScreen.screens.compactMap { screen in
            screen.displayID.map { DisplayChoice(id: $0, name: screen.localizedName) }
        }
    }

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .display(let settings) = spec else { return nil }
        return DisplaySource(settings: settings, receiver: ScreenStreamReceiver(queues: queues))
    }
}
