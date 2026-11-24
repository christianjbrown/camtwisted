import CamTwistCore
import CoreMediaIO
import Foundation

/// Receives start and stop requests for the device's streams.
protocol CameraStreamController: AnyObject {
    /// A process has asked for the camera's picture.
    func sourceWanted(byProcess process: pid_t)
    func startSource()
    func stopSource()
    func startSink(client: CMIOExtensionClient)
    func stopSink()
}

/// The frame duration every stream of this camera runs at.
enum CameraTiming {
    static let frameDuration = CMTime(value: 1, timescale: CMTimeScale(CameraContract.framesPerSecond))
    static let onlyFormatIndex = 0
}

/// The stream other apps read: the camera's picture.
final class CameraSourceStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let format: CMIOExtensionStreamFormat
    private weak var controller: CameraStreamController?

    init(format: CMIOExtensionStreamFormat) {
        self.format = format
        super.init()
        stream = CMIOExtensionStream(
            localizedName: CameraContract.sourceStreamName,
            streamID: CameraContract.sourceStreamID,
            direction: .source,
            clockType: .hostTime,
            source: self
        )
    }

    /// Says who to tell when the stream starts or stops.
    func attach(_ controller: CameraStreamController) {
        self.controller = controller
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(
        forProperties properties: Set<CMIOExtensionProperty>
    ) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = CameraTiming.onlyFormatIndex
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = CameraTiming.frameDuration
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        controller?.sourceWanted(byProcess: client.pid)
        return true
    }

    func startStream() throws {
        controller?.startSource()
    }

    func stopStream() throws {
        controller?.stopSource()
    }
}

/// The stream the host app writes its frames into.
final class CameraSinkStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let format: CMIOExtensionStreamFormat
    private weak var controller: CameraStreamController?
    private var client: CMIOExtensionClient?

    init(format: CMIOExtensionStreamFormat) {
        self.format = format
        super.init()
        stream = CMIOExtensionStream(
            localizedName: CameraContract.sinkStreamName,
            streamID: CameraContract.sinkStreamID,
            direction: .sink,
            clockType: .hostTime,
            source: self
        )
    }

    /// Says who to tell when the stream starts or stops.
    func attach(_ controller: CameraStreamController) {
        self.controller = controller
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }

    var availableProperties: Set<CMIOExtensionProperty> {
        [
            .streamActiveFormatIndex,
            .streamFrameDuration,
            .streamSinkBufferQueueSize,
            .streamSinkBuffersRequiredForStartup,
            .streamSinkBufferUnderrunCount,
            .streamSinkEndOfData,
        ]
    }

    func streamProperties(
        forProperties properties: Set<CMIOExtensionProperty>
    ) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = CameraTiming.onlyFormatIndex
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = CameraTiming.frameDuration
        }
        if properties.contains(.streamSinkBufferQueueSize) {
            streamProperties.sinkBufferQueueSize = CameraContract.sinkQueueSize
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            streamProperties.sinkBuffersRequiredForStartup = CameraContract.sinkBuffersRequiredForStartup
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        guard let client else { return }
        controller?.startSink(client: client)
    }

    func stopStream() throws {
        controller?.stopSink()
    }
}

extension CameraSourceStream: CameraFrameSender {
    func send(_ frame: TimedFrame) {
        stream.send(
            frame.sampleBuffer,
            discontinuity: [],
            hostTimeInNanoseconds: HostTime.nanoseconds(forSeconds: frame.time.seconds)
        )
    }
}

extension CameraSinkStream: CameraSinkReading {
    func consumeFrame(from client: CMIOExtensionClient, completion: @escaping (CMSampleBuffer?, UInt64) -> Void) {
        stream.consumeSampleBuffer(from: client) { sampleBuffer, sequenceNumber, _, _, _ in
            completion(sampleBuffer, sequenceNumber)
        }
    }

    func announceOutput(sequenceNumber: UInt64, at time: CMTime) {
        let output = CMIOExtensionScheduledOutput(
            sequenceNumber: sequenceNumber,
            hostTimeInNanoseconds: HostTime.nanoseconds(forSeconds: time.seconds)
        )
        stream.notifyScheduledOutputChanged(output)
    }
}
