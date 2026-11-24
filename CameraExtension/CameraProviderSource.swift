import CamTwistCore
import CoreMediaIO
import Foundation

/// The extension's entry point for Core Media I/O: it offers the one device.
final class CameraProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    /// Held so the device's weak reference to its source stays good.
    private let deviceSource: CameraDeviceSource
    private let watchers: CameraWatcherRegistry

    init(clientQueue: DispatchQueue?, deviceSource: CameraDeviceSource, watchers: CameraWatcherRegistry) {
        self.deviceSource = deviceSource
        self.watchers = watchers
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Could not add the camera device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    /// A process has let go of the extension altogether.
    func disconnect(from client: CMIOExtensionClient) {
        watchers.remove(client.pid)
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(
        forProperties properties: Set<CMIOExtensionProperty>
    ) throws -> CMIOExtensionProviderProperties {
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = CameraContract.manufacturer
        }
        return providerProperties
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}
