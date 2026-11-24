import CamTwistCore
import CoreMedia
import CoreMediaIO
import Foundation

/// Pushes frames into the camera extension's sink stream, which hands them
/// to every app that has the virtual camera selected.
public final class VirtualCameraSink: FrameSink {
    private var deviceID: CMIOObjectID?
    private var streamID: CMIOStreamID?
    private var queue: CMSimpleQueue?
    private var formatDescription: CMFormatDescription?
    private var reconnects: AttemptThrottle
    private let clock: () -> TimeInterval

    /// - Parameter reconnectInterval: seconds between looks for the camera while it is not there.
    public init(reconnectInterval: TimeInterval, clock: @escaping () -> TimeInterval) {
        self.reconnects = AttemptThrottle(interval: reconnectInterval)
        self.clock = clock
    }

    /// Whether frames are currently reaching the camera.
    public private(set) var isConnected = false

    /// The processes that have the camera's picture open, as the camera
    /// extension reports them. Empty when it is not installed or says none.
    public var watcherProcessIDs: [Int32] {
        guard let device = CoreMediaIODevices.device(withUID: CameraContract.deviceID.uuidString),
              let text = CoreMediaIODevices.text(of: device, selector: CMIOObjectPropertySelector(CameraWatchers.selector))
        else { return [] }
        return CameraWatchers.processes(in: text)
    }

    /// Whether frames are sent at all. Switched off, other apps see the
    /// camera but get no picture from it.
    public var isEnabled: Bool {
        get { enabled.get() }
        set { enabled.set(newValue) }
    }

    private let enabled = Locked(true)

    public func send(_ pixelBuffer: CVPixelBuffer) {
        guard isEnabled, connectIfNeeded(), let queue else { return }
        guard CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else { return }
        guard let sampleBuffer = makeSampleBuffer(pixelBuffer) else { return }
        let element = Unmanaged.passRetained(sampleBuffer).toOpaque()
        if CMSimpleQueueEnqueue(queue, element: element) != noErr {
            Unmanaged<CMSampleBuffer>.fromOpaque(element).release()
            disconnect()
        }
    }

    public func disconnect() {
        if let deviceID, let streamID {
            CMIODeviceStopStream(deviceID, streamID)
        }
        deviceID = nil
        streamID = nil
        queue = nil
        isConnected = false
    }

    private func connectIfNeeded() -> Bool {
        if isConnected { return true }
        guard reconnects.permits(at: clock()) else { return false }

        guard let device = CoreMediaIODevices.device(withUID: CameraContract.deviceID.uuidString) else {
            return false
        }
        let streams = CoreMediaIODevices.streams(of: device)
        guard streams.indices.contains(CameraContract.sinkStreamIndex) else { return false }
        let sink = streams[CameraContract.sinkStreamIndex]

        var unmanagedQueue: Unmanaged<CMSimpleQueue>?
        let status = CMIOStreamCopyBufferQueue(sink, { _, _, _ in }, nil, &unmanagedQueue)
        guard status == noErr, let unmanagedQueue else { return false }
        guard CMIODeviceStartStream(device, sink) == noErr else {
            unmanagedQueue.release()
            return false
        }
        queue = unmanagedQueue.takeRetainedValue()
        deviceID = device
        streamID = sink
        isConnected = true
        return true
    }

    private func makeSampleBuffer(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        if formatDescription == nil
            || !CMVideoFormatDescriptionMatchesImageBuffer(formatDescription!, imageBuffer: pixelBuffer) {
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription
            )
        }
        guard let formatDescription else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(CameraContract.framesPerSecond)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}

/// Lookups in Core Media I/O's object tree.
enum CoreMediaIODevices {
    static func device(withUID uid: String) -> CMIOObjectID? {
        let devices: [CMIOObjectID] = objects(
            of: CMIOObjectID(kCMIOObjectSystemObject),
            selector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices)
        )
        return devices.first { self.uid(of: $0) == uid }
    }

    static func streams(of device: CMIOObjectID) -> [CMIOStreamID] {
        objects(of: device, selector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams))
    }

    private static func address(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private static func objects(of object: CMIOObjectID, selector: CMIOObjectPropertySelector) -> [CMIOObjectID] {
        var address = address(selector)
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &dataSize) == noErr else { return [] }
        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        guard count > 0 else { return [] }
        var result = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, dataSize, &dataUsed, &result) == noErr else {
            return []
        }
        return result
    }

    private static func uid(of device: CMIOObjectID) -> String? {
        text(of: device, selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID))
    }

    /// A property of a device whose value is text.
    static func text(of device: CMIOObjectID, selector: CMIOObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var dataUsed: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &dataUsed, &value) == noErr else {
            return nil
        }
        return value?.takeRetainedValue() as String?
    }
}
