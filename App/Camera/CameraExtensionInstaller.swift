import AVFoundation
import CamTwistControl
import CamTwistCore
import Observation
import Foundation
import SystemExtensions

/// Hands requests about system extensions to macOS.
protocol ExtensionRequestSubmitting {
    func submit(_ request: OSSystemExtensionRequest)
}

/// The system's own extension manager.
struct SystemExtensionRequests: ExtensionRequestSubmitting {
    func submit(_ request: OSSystemExtensionRequest) {
        OSSystemExtensionManager.shared.submitRequest(request)
    }
}

/// Installs and updates the camera extension through macOS.
@Observable
final class CameraExtensionInstaller: NSObject, OSSystemExtensionRequestDelegate {
    /// Info.plist key holding the extension's bundle identifier, which comes
    /// from build configuration.
    static let bundleIdentifierInfoKey = "CameraExtensionBundleIdentifier"

    private(set) var state: CameraInstallState = .unknown {
        didSet { onChange?() }
    }
    /// Told each time the state has changed.
    @ObservationIgnored var onChange: (() -> Void)?

    private let extensionIdentifier: String
    /// Decides what each event the system sends means for the camera.
    private var machine = CameraInstallMachine()

    private let requests: ExtensionRequestSubmitting

    /// - Parameters:
    ///   - extensionIdentifier: the extension's bundle identifier, as the build says.
    ///   - requests: where requests to install and remove it go.
    init(extensionIdentifier: String, requests: ExtensionRequestSubmitting) {
        self.extensionIdentifier = extensionIdentifier
        self.requests = requests
        super.init()
        refresh()
    }

    /// Looks for the camera among the system's capture devices.
    func refresh() {
        apply { $0.refresh(cameraIsPresent: cameraIsPresent) }
    }

    func install() {
        apply { $0.beginInstall() }
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionIdentifier, queue: .main
        )
        request.delegate = self
        requests.submit(request)
    }

    func remove() {
        apply { $0.beginRemove() }
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: extensionIdentifier, queue: .main
        )
        request.delegate = self
        requests.submit(request)
    }

    /// Feeds the machine an event and shows the state it lands in.
    private func apply(_ event: (inout CameraInstallMachine) -> Void) {
        event(&machine)
        state = machine.state
    }

    private var cameraIsPresent: Bool {
        AVCaptureDevice(uniqueID: CameraContract.deviceID.uuidString) != nil
    }

    // MARK: OSSystemExtensionRequestDelegate

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        apply { $0.needsApproval() }
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        apply { $0.finished(completed: result == .completed) }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        apply { $0.failed(error.localizedDescription) }
    }
}

extension CameraExtensionInstaller: CameraInstalling {}
