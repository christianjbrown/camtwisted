import CamTwistCore
import CamTwistRendering
import Foundation
import Observation

/// The virtual camera: whether it is installed, whether the picture is
/// going to it, and who is watching.
@MainActor
@Observable
public final class CameraOutputModel: QuietlyAssigning {
    public private(set) var isSending = false
    /// The apps that have the virtual camera's picture open, named as one phrase. Empty with none.
    public private(set) var watchers = ""
    /// Where the virtual camera stands on this Mac.
    public private(set) var installState = CameraInstallState.unknown

    private let connection: CameraConnectionReporting
    private let use: CameraWatcherNaming
    private let installer: CameraInstalling

    init(connection: CameraConnectionReporting, use: CameraWatcherNaming, installer: CameraInstalling) {
        self.connection = connection
        self.use = use
        self.installer = installer
        installState = installer.state
        // The installer keeps this, so it must not hold the installer in turn.
        installer.onChange = { [weak self] in
            guard let self else { return }
            self.installState = self.installer.state
        }
    }

    /// Looks again at whether the picture is going out and who has it open.
    func refresh() {
        assign(\.isSending, connection.isConnected)
        assign(\.watchers, use.sentence(for: connection.watcherProcessIDs))
        installer.refresh()
    }

    public func install() {
        installer.install()
    }

    public func remove() {
        installer.remove()
    }
}
