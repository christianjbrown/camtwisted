import CamTwistCore
import CoreMediaIO
import Foundation
import IOKit.audio

/// The virtual camera's device: its properties and its two streams. What
/// the streams do when started is the controller's business.
final class CameraDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private let sourceStream: CameraSourceStream
    private let sinkStream: CameraSinkStream
    /// Held so the streams' weak reference to it stays good.
    private let controller: CameraStreamController
    private let watchers: CameraWatcherRegistry
    private static let watchersProperty = CMIOExtensionProperty(rawValue: CameraWatchers.extensionProperty)

    init(
        sourceStream: CameraSourceStream, sinkStream: CameraSinkStream, controller: CameraStreamController,
        watchers: CameraWatcherRegistry
    ) {
        self.sourceStream = sourceStream
        self.sinkStream = sinkStream
        self.controller = controller
        self.watchers = watchers
        super.init()
        sourceStream.attach(controller)
        sinkStream.attach(controller)
        device = CMIOExtensionDevice(
            localizedName: CameraContract.cameraName,
            deviceID: CameraContract.deviceID,
            legacyDeviceID: nil,
            source: self
        )
        do {
            // Order matters: it is the stream order the host app relies on.
            try device.addStream(sourceStream.stream)
            try device.addStream(sinkStream.stream)
        } catch {
            fatalError("Could not add the camera streams: \(error.localizedDescription)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel, Self.watchersProperty]
    }

    func deviceProperties(
        forProperties properties: Set<CMIOExtensionProperty>
    ) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = CameraContract.deviceModel
        }
        if properties.contains(Self.watchersProperty) {
            deviceProperties.setPropertyState(
                CMIOExtensionPropertyState(value: watchers.propertyText as NSString), forProperty: Self.watchersProperty
            )
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}
}
