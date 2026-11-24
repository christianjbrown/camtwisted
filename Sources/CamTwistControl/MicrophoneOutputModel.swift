import CamTwistCore
import Foundation
import Observation

/// The virtual microphone: whether it is installed, and installing and
/// removing it.
@MainActor
@Observable
public final class MicrophoneOutputModel: QuietlyAssigning {
    /// Where the virtual microphone stands on this Mac.
    public private(set) var state = MicrophoneInstallState.notInstalled

    /// Called once the microphone has been installed or removed. The
    /// audio server restarts either way, so the outputs have to be put
    /// into effect again.
    @ObservationIgnored var onChanged: (() -> Void)?

    private let setup: MicrophoneSettingUp
    private nonisolated let queue: WorkQueueing

    init(setup: MicrophoneSettingUp, queue: WorkQueueing) {
        self.setup = setup
        self.queue = queue
    }

    /// Looks again at where the microphone stands.
    func refresh() {
        assign(\.state, setup.state)
    }

    public func install() {
        change { $0.install($1) }
    }

    public func remove() {
        change { $0.remove($1) }
    }

    /// Runs an install or a removal and shows how it went.
    private func change(_ change: (MicrophoneSettingUp, @escaping () -> Void) -> Void) {
        let queue = self.queue
        change(setup) { [weak self] in
            queue.main { self?.onChanged?() }
        }
        state = setup.state
    }
}
