import Foundation

/// The steps the virtual camera goes through while it is put on this Mac or
/// taken away. The system's requests and its capture devices feed it events.
public struct CameraInstallMachine: Equatable {
    public private(set) var state: CameraInstallState = .unknown
    /// Whether the request in hand takes the camera away rather than putting it in.
    private var isRemoving = false

    public init() {}

    /// Brings the state in line with whether the system lists the camera.
    public mutating func refresh(cameraIsPresent: Bool) {
        if state == .installing { return }
        if state == .needsApproval, !cameraIsPresent { return }
        if cameraIsPresent {
            state = .installed
        } else if state == .installed {
            state = .unknown
        }
    }

    public mutating func beginInstall() {
        state = .installing
        isRemoving = false
    }

    public mutating func beginRemove() {
        state = .installing
        isRemoving = true
    }

    public mutating func needsApproval() {
        state = .needsApproval
    }

    /// The system finished the request. `completed` is false when it still
    /// waits on a restart or on approval.
    public mutating func finished(completed: Bool) {
        if isRemoving {
            // Gone, or gone once the Mac next restarts.
            isRemoving = false
            state = .unknown
            return
        }
        state = completed ? .installed : .needsApproval
    }

    public mutating func failed(_ message: String) {
        isRemoving = false
        state = .failed(message)
    }
}
