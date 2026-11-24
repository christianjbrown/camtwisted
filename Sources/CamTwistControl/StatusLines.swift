import CamTwistCore
import Foundation

// What the output pane says about each output, decided here so the views
// only show it.

/// The picture beside a status line. Each raw value is an SF Symbol name.
public enum StatusIcon: String, Equatable {
    case done = "checkmark.circle"
    case working = "hourglass"
    case warning = "exclamationmark.triangle"
    case failure = "xmark.octagon"
    case notStarted = "circle.dashed"
    case recording = "record.circle"
    case live = "dot.radiowaves.left.and.right"
    case playing = "tv"
}

/// How a status line is coloured. The view maps it to a colour.
public enum StatusTint: Equatable {
    case normal
    case alert
}

/// One line saying where an output has got to.
public struct StatusLine: Equatable {
    public let text: String
    public let icon: StatusIcon
    public let tint: StatusTint

    public init(_ text: String, _ icon: StatusIcon, tint: StatusTint = .normal) {
        self.text = text
        self.icon = icon
        self.tint = tint
    }

    static let approvalSteps = """
        Open System Settings, go to General, then "Login Items & Extensions". Scroll down to "By Category", \
        click the (i) beside "Camera Extensions", and switch \(CameraContract.deviceName) on.
        """

    /// Where the virtual camera has got to. Watchers say who has it open.
    public static func camera(_ state: CameraInstallState, watchers: String, isSending: Bool) -> StatusLine {
        switch state {
        case .installed:
            if !watchers.isEmpty { return StatusLine("Installed, in use by \(watchers)", .done) }
            return StatusLine(isSending ? "Installed, and getting the picture" : "Installed", .done)
        case .installing: return StatusLine("Installing", .working)
        case .needsApproval: return StatusLine(approvalSteps, .warning)
        case .failed(let message): return StatusLine(message, .failure)
        case .unknown: return StatusLine("Not installed yet", .notStarted)
        }
    }

    /// Where the virtual microphone has got to.
    public static func microphone(_ state: MicrophoneInstallState) -> StatusLine {
        switch state {
        case .installed: return StatusLine("Installed", .done)
        case .installing: return StatusLine("Installing: sound on this Mac stops for a moment", .working)
        case .failed(let message): return StatusLine(message, .failure)
        case .notInstalled: return StatusLine("Not installed yet", .notStarted)
        }
    }

    /// How the recording is getting on.
    public static func recording(_ status: RecordingStatus) -> StatusLine {
        switch status {
        case .off: return StatusLine("Starting", .working)
        case .recording(let name): return StatusLine("Recording to \(name)", .recording, tint: .alert)
        case .failed(let message): return StatusLine(message, .failure)
        }
    }

    /// How far playing on a Cast device has got. Nothing is said while idle.
    public static func cast(_ state: CastState) -> StatusLine? {
        switch state {
        case .idle: return nil
        case .starting, .loading: return StatusLine("Starting on the device", .working)
        case .playing: return StatusLine("Playing on the device", .playing)
        case .failed(let message): return StatusLine(message, .failure)
        }
    }

    /// How far the RTMP stream has got. Nothing is said while idle.
    public static func rtmp(_ state: RTMPState) -> StatusLine? {
        switch state {
        case .idle: return nil
        case .connecting: return StatusLine("Connecting", .working)
        case .live: return StatusLine("Live", .live, tint: .alert)
        case .failed(let message): return StatusLine("Could not stream: \(message)", .failure)
        }
    }

    /// Whether a web stream failed to start. Nothing is said otherwise: a
    /// running stream shows its links instead.
    public static func webStream(_ status: WebStreamStatus) -> StatusLine? {
        if case .failed(let message) = status { return StatusLine("Could not start: \(message)", .failure) }
        return nil
    }
}

/// The camera's install button and whether it can remove the camera.
public struct CameraInstallControls: Equatable {
    public let installTitle: String
    public let canRemove: Bool
    public let isBusy: Bool

    public init(_ state: CameraInstallState) {
        switch state {
        case .installed: installTitle = "Reinstall camera"
        case .unknown, .installing: installTitle = "Install camera"
        case .needsApproval, .failed: installTitle = "Try again"
        }
        canRemove = state == .installed
        isBusy = state == .installing
    }
}

/// The microphone's install button and whether it can remove the microphone.
public struct MicrophoneInstallControls: Equatable {
    public let installTitle: String
    public let canRemove: Bool
    public let isBusy: Bool
    /// Whether to offer the add-on, where the microphone is a separate
    /// download: not once it is there.
    public let offersAddOn: Bool

    public init(_ state: MicrophoneInstallState) {
        offersAddOn = state != .installed
        installTitle = state == .installed ? "Reinstall microphone" : "Install microphone"
        canRemove = state == .installed
        isBusy = state == .installing
    }
}
