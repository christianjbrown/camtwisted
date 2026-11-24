import AVFoundation
import CamTwistCore
import CoreImage

/// A real camera as a source.
public final class CameraSource: NSObject, FrameSource, SoundSource, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate {
    private let device: AVCaptureDevice
    private let listener = Locked<((CMSampleBuffer) -> Void)?>(nil)

    /// Where the camera's own microphone is heard, when it has one.
    public var onSound: ((CMSampleBuffer) -> Void)? {
        get { listener.get() }
        set { listener.set(newValue) }
    }

    private let session = AVCaptureSession()
    private let frames = LatestFrameBox()
    /// The label of the queue that receives camera frames.
    static let queueLabel = "source.camera"
    private let queue: DispatchQueue
    private var isConfigured = false

    public init(device: AVCaptureDevice, queue: DispatchQueue) {
        self.queue = queue
        self.device = device
    }

    public var latestFrame: CIImage? { frames.load() }

    public func start() {
        queue.async {
            self.configureIfNeeded()
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    public func stop() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.frames.store(nil)
        }
    }

    public func update(to spec: SourceSpec) -> Bool {
        spec == .camera(deviceID: device.uniqueID)
    }

    private func configureIfNeeded() {
        guard !isConfigured, let input = try? AVCaptureDeviceInput(device: device) else { return }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        // The microphone built into the camera, when it has one, is heard too.
        if let microphone = device.linkedDevices.first(where: { $0.hasMediaType(.audio) }),
           let sound = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(sound) {
            let soundOutput = AVCaptureAudioDataOutput()
            soundOutput.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(soundOutput) {
                session.addInput(sound)
                session.addOutput(soundOutput)
            }
        }
        session.commitConfiguration()
        isConfigured = true
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output is AVCaptureAudioDataOutput {
            listener.get()?(sampleBuffer)
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frames.store(CIImage(cvPixelBuffer: pixelBuffer))
    }
}

/// A camera the user can pick.
public struct CameraChoice: Identifiable, Equatable {
    public let id: String
    public let name: String
    /// The most pixels it can give in a frame, for telling the better of two.
    public let pixels: Int

    public init(id: String, name: String, pixels: Int = 0) {
        self.id = id
        self.name = name
        self.pixels = pixels
    }
}

public struct CameraSourceProvider: SourceProvider {
    private let queues: QueueMaking

    public init(queues: QueueMaking) {
        self.queues = queues
    }

    public func cameras() -> [CameraChoice] {
        devices().map { device in
            let sizes = device.formats.map { format -> (width: Int, height: Int) in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return (Int(dimensions.width), Int(dimensions.height))
            }
            return CameraChoice(
                id: device.uniqueID, name: device.localizedName, pixels: CameraListing.mostPixels(of: sizes)
            )
        }
    }

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .camera(let deviceID) = spec else { return nil }
        return devices().first { $0.uniqueID == deviceID }.map {
            CameraSource(device: $0, queue: queues.makeQueue(label: CameraSource.queueLabel, qos: .userInteractive))
        }
    }

    /// Every camera except our own virtual one, which would feed back.
    private func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.filter { CameraListing.isOffered(uniqueID: $0.uniqueID) }
    }
}
