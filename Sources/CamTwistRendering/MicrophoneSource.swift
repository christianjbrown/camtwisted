import AVFoundation
import CamTwistCore
import CoreImage
import Foundation

/// A microphone as a source: it has no picture, only sound, which joins
/// the mix the streams carry.
public final class MicrophoneSource: NSObject, FrameSource, SoundSource, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let deviceID: String?
    /// The label of the queue that receives microphone audio.
    static let queueLabel = "source.microphone"
    private let queue: DispatchQueue
    private let listener = Locked<((CMSampleBuffer) -> Void)?>(nil)
    private var session: AVCaptureSession?
    private var isWanted = false

    /// - Parameter deviceID: the microphone to listen to, or nil for the system's own choice.
    public init(deviceID: String?, queue: DispatchQueue) {
        self.queue = queue
        self.deviceID = deviceID
    }

    public var onSound: ((CMSampleBuffer) -> Void)? {
        get { listener.get() }
        set { listener.set(newValue) }
    }

    /// A microphone shows nothing.
    public var latestFrame: CIImage? { nil }

    /// Starts listening. The first time, macOS asks whether the app may.
    public func start() {
        queue.async { [weak self] in
            self?.isWanted = true
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
                guard allowed else { return }
                self?.queue.async { self?.listen() }
            }
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.isWanted = false
            self?.session?.stopRunning()
            self?.session = nil
        }
    }

    public func update(to spec: SourceSpec) -> Bool {
        spec == .microphone(deviceID: deviceID)
    }

    public func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        listener.get()?(sampleBuffer)
    }

    private func listen() {
        // It may have been stopped again while macOS was asking.
        guard isWanted, session == nil else { return }
        let chosen = MicrophoneSourceProvider.devices().first { $0.uniqueID == deviceID }
        guard let device = chosen ?? AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        let session = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else { return }
        session.addInput(input)
        session.addOutput(output)
        session.startRunning()
        self.session = session
    }
}

public struct MicrophoneSourceProvider: SourceProvider {
    private let queues: QueueMaking

    public init(queues: QueueMaking) {
        self.queues = queues
    }

    /// The microphones on this Mac.
    public func microphones() -> [MicrophoneChoice] {
        Self.devices().map { MicrophoneChoice(id: $0.uniqueID, name: $0.localizedName) }
    }

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .microphone(let deviceID) = spec else { return nil }
        return MicrophoneSource(deviceID: deviceID, queue: queues.makeQueue(label: MicrophoneSource.queueLabel, qos: .default))
    }

    static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices
    }
}
