import Foundation

/// Follows the virtual microphone through being installed and removed.
final class MicrophoneSetup {
    private let installer: MicrophoneInstalling
    private let output: MicrophoneSwitching
    private let lock = NSLock()
    private var isWorking = false
    private var problem: String?

    init(installer: MicrophoneInstalling, output: MicrophoneSwitching) {
        self.installer = installer
        self.output = output
    }

    /// Where things stand: at work, failed, or whatever the system says.
    var state: MicrophoneInstallState {
        lock.lock()
        defer { lock.unlock() }
        if isWorking {
            return .installing
        }
        if let problem {
            return .failed(problem)
        }
        return installer.isInstalled ? .installed : .notInstalled
    }

    func install(_ finished: @escaping () -> Void) {
        run({ $0.install($1) }, finished)
    }

    func remove(_ finished: @escaping () -> Void) {
        run({ $0.remove($1) }, finished)
    }

    private func run(
        _ change: (MicrophoneInstalling, @escaping (String?) -> Void) -> Void, _ finished: @escaping () -> Void
    ) {
        set(isWorking: true, problem: nil)
        // Held on to until the system answers, which it always does.
        change(installer) { problem in
            self.set(isWorking: false, problem: problem)
            // The audio server has started again: whatever was playing to
            // the microphone has to begin afresh.
            self.output.isEnabled = false
            finished()
        }
    }

    private func set(isWorking: Bool, problem: String?) {
        lock.lock()
        self.isWorking = isWorking
        self.problem = problem
        lock.unlock()
    }
}
