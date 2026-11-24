import CamTwistControl
import CamTwistCore
import CamTwistRendering
import AppKit
import Foundation

extension VirtualMicrophoneSink: @retroactive MicrophoneSwitching {}

/// Runs a command as its own process and waits for it.
protocol CommandRunning {
    /// The command's exit status, or throws when it could not be started.
    func run(_ executable: URL, arguments: [String]) throws -> Int32
}

/// Opens an address in whatever the system uses for it.
protocol AddressOpening {
    func open(_ url: URL)
}

/// Runs commands with the system's own process launcher.
struct ProcessCommandRunner: CommandRunning {
    func run(_ executable: URL, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardError = Pipe()
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// Opens addresses through the workspace.
struct WorkspaceAddressOpener: AddressOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// Installs and removes the virtual microphone's audio driver. Both need an
/// administrator, so macOS asks for a password each time.
final class SystemMicrophoneInstaller: MicrophoneInstalling {
    private static let scriptRunner = "/usr/bin/osascript"
    private static let scriptFlag = "-e"
    private static let missingDriver = "The audio driver is missing from the app. Install the app again."

    /// The folder the app's own files are in, where the driver comes from.
    private let resources: URL?
    private let files: FileChecking
    private let commands: CommandRunning
    private let queue: WorkQueueing

    init(resources: URL?, files: FileChecking, commands: CommandRunning, queue: WorkQueueing) {
        self.resources = resources
        self.files = files
        self.commands = commands
        self.queue = queue
    }

    var isInstalled: Bool { VirtualMicrophoneSink.isInstalled }

    func install(_ completion: @escaping (String?) -> Void) {
        guard let driver = resources?.appendingPathComponent(MicrophoneContract.bundleName),
              files.exists(atPath: driver.path)
        else { return completion(Self.missingDriver) }
        run(MicrophoneInstallScript.install(from: driver.path), completion)
    }

    func remove(_ completion: @escaping (String?) -> Void) {
        run(MicrophoneInstallScript.remove, completion)
    }

    private func run(_ command: String, _ completion: @escaping (String?) -> Void) {
        let commands = commands
        queue.background {
            do {
                let status = try commands.run(
                    URL(fileURLWithPath: Self.scriptRunner),
                    arguments: [Self.scriptFlag, MicrophoneInstallScript.appleScript(running: command)]
                )
                completion(MicrophoneInstallOutcome.problem(exitStatus: status))
            } catch {
                completion(error.localizedDescription)
            }
        }
    }
}

/// The store build's stand-in for the installer. The store does not let an
/// app install an audio driver, so this one sends people to where the
/// microphone can be had separately. Once it is installed the app finds
/// and feeds it just the same.
final class AddOnMicrophoneInstaller: MicrophoneInstalling {
    /// Info.plist key holding the add-on's address, which comes from build configuration.
    static let addressInfoKey = "MicrophoneAddOnURL"
    private static let noAddress = "This build does not say where to get the microphone."
    private static let removeElsewhere = "Remove it with the add-on's own uninstaller."

    /// Where the add-on is to be had, as the build says.
    private let address: String?
    private let opener: AddressOpening
    private let queue: WorkQueueing

    init(address: String?, opener: AddressOpening, queue: WorkQueueing) {
        self.address = address
        self.opener = opener
        self.queue = queue
    }

    var isInstalled: Bool { VirtualMicrophoneSink.isInstalled }

    func install(_ completion: @escaping (String?) -> Void) {
        guard let address, let url = URL(string: address), url.scheme != nil
        else { return completion(Self.noAddress) }
        let opener = opener
        queue.main {
            opener.open(url)
            completion(nil)
        }
    }

    func remove(_ completion: @escaping (String?) -> Void) {
        completion(Self.removeElsewhere)
    }
}
