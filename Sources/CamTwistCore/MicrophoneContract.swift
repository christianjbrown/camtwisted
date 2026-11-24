import Foundation

/// The fixed contract between the app and the audio driver that is the
/// virtual microphone.
///
/// The driver is built from C, with the same values written there, and a
/// test keeps the two in step. They are constants rather than
/// configuration because a mismatch between the two binaries cannot be
/// repaired at run time.
public enum MicrophoneContract {
    /// What other apps see in their list of microphones.
    public static let deviceName = "CamTwisted Virtual Microphone output"
    public static let deviceUID = "CamTwistedMicrophone"
    /// The hidden device the app plays its mix to, which the microphone hears.
    public static let feedName = "CamTwisted Microphone Feed"
    public static let feedUID = "CamTwistedMicrophoneFeed"
    public static let manufacturer = "CamTwisted"

    public static let sampleRate = 48000.0
    public static let channels = 2

    /// The driver's bundle, as it sits inside the app and once installed.
    public static let bundleName = "CamTwistedAudio.driver"
    /// Where macOS looks for audio drivers.
    public static let installDirectory = "/Library/Audio/Plug-Ins/HAL"
    /// The system's audio server, which only finds a driver when it starts.
    public static let audioServerName = "coreaudiod"

    public static var installedPath: String { installDirectory + "/" + bundleName }
}

/// The commands that put the driver in place or take it away. They need an
/// administrator, so they are run through the system's own password prompt.
public enum MicrophoneInstallScript {
    private enum Tool {
        static let remove = "/bin/rm -rf"
        static let makeDirectory = "/bin/mkdir -p"
        static let copy = "/bin/cp -R"
        static let own = "/usr/sbin/chown -R root:wheel"
        static let restart = "/usr/bin/killall"
    }

    private static let then = " && "
    private static let quote = "'"
    /// A quote inside quoted shell text: close, an escaped quote, open again.
    private static let escapedQuote = "'\\''"
    private static let scriptQuote = "\""
    private static let scriptEscape = "\\"

    /// Replaces whatever driver is installed with the one at a path, then
    /// restarts the audio server so it is found.
    public static func install(from bundlePath: String) -> String {
        [
            removeInstalled,
            "\(Tool.makeDirectory) \(quoted(MicrophoneContract.installDirectory))",
            "\(Tool.copy) \(quoted(bundlePath)) \(quoted(MicrophoneContract.installedPath))",
            "\(Tool.own) \(quoted(MicrophoneContract.installedPath))",
            restartAudio,
        ].joined(separator: then)
    }

    /// Takes the driver away and restarts the audio server so it is gone.
    public static var remove: String {
        [removeInstalled, restartAudio].joined(separator: then)
    }

    /// AppleScript that runs shell commands as an administrator, which is
    /// what puts the system's password prompt up.
    public static func appleScript(running command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: scriptEscape, with: scriptEscape + scriptEscape)
            .replacingOccurrences(of: scriptQuote, with: scriptEscape + scriptQuote)
        return "do shell script \(scriptQuote)\(escaped)\(scriptQuote) with administrator privileges"
    }

    private static var removeInstalled: String {
        "\(Tool.remove) \(quoted(MicrophoneContract.installedPath))"
    }

    /// The server is started again by the system as soon as it stops. With
    /// none running there is nothing to stop, which is fine too.
    private static var restartAudio: String {
        "(\(Tool.restart) \(MicrophoneContract.audioServerName) || true)"
    }

    private static func quoted(_ text: String) -> String {
        quote + text.replacingOccurrences(of: quote, with: escapedQuote) + quote
    }
}
