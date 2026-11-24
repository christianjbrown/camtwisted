import CamTwistCore
import CoreMedia
import CoreMediaIO
import Foundation

/// The one place the extension's parts are built and joined together.
struct CameraExtensionAssembly {
    static let frameQueueLabel = "camera.frames"
    static let logCategory = "camera"

    let pacing: Pacing
    let clock: () -> Date

    /// The log subsystem is the extension's own bundle, or the device name outside one.
    private static var logSubsystem: String {
        Bundle.main.bundleIdentifier ?? CameraContract.deviceName
    }

    func makeProviderSource() -> CameraProviderSource {
        let queue = DispatchQueue(label: Self.frameQueueLabel, qos: .userInteractive)
        let log = OSCameraLogger(subsystem: Self.logSubsystem, category: Self.logCategory)
        let hostTime = { CMClockGetTime(CMClockGetHostTimeClock()) }
        let formatDescription = makeFormatDescription()
        let format = CMIOExtensionStreamFormat(
            formatDescription: formatDescription,
            maxFrameDuration: CameraTiming.frameDuration,
            minFrameDuration: CameraTiming.frameDuration,
            validFrameDurations: nil
        )
        let sourceStream = CameraSourceStream(format: format)
        let sinkStream = CameraSinkStream(format: format)
        let session = CameraSession(silenceTimeout: pacing.cameraSilenceTimeout)
        let watchers = CameraWatcherRegistry()
        let frames = PlaceholderFrameMaker(
            pool: PixelBufferPoolSource(
                width: CameraContract.width, height: CameraContract.height, threshold: pacing.framePoolThreshold
            ),
            placeholder: TestBarsFrameProvider(),
            formatDescription: formatDescription,
            frameDuration: CameraTiming.frameDuration,
            hostTime: hostTime,
            log: log
        )
        let pump = PlaceholderFramePump(
            queue: queue, interval: CameraTiming.frameDuration.seconds, session: session, frames: frames,
            sender: sourceStream, clock: clock
        )
        let consumer = SinkFrameConsumer(
            queue: queue, session: session, reader: sinkStream, sender: sourceStream,
            retryDelay: pacing.cameraRetryDelay, clock: clock, hostTime: hostTime
        )
        let coordinator = CameraStreamCoordinator(
            queue: queue, session: session, watchers: watchers, pump: pump, consumer: consumer
        )
        let deviceSource = CameraDeviceSource(
            sourceStream: sourceStream, sinkStream: sinkStream, controller: coordinator, watchers: watchers
        )
        return CameraProviderSource(clientQueue: nil, deviceSource: deviceSource, watchers: watchers)
    }

    private func makeFormatDescription() -> CMFormatDescription {
        var formatDescription: CMFormatDescription!
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: Int32(CameraContract.width),
            height: Int32(CameraContract.height),
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        return formatDescription
    }
}
