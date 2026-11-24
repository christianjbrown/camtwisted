import AVFoundation
import CamTwistControl
import CamTwistCore
import CamTwistRendering
import Foundation

/// Asks macOS for the right to use the microphone.
protocol MicrophoneAccessRequesting {
    func requestAccess()
}

/// Asks through the capture device API.
struct CaptureMicrophoneAccess: MicrophoneAccessRequesting {
    func requestAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }
}

/// The sound that goes out with the streams: whatever in the scene on air
/// makes any, each at its own level, mixed into one.
final class SoundDesk: SoundCapturing {
    private let router: SoundRouting
    private let microphoneAccess: MicrophoneAccessRequesting

    /// - Parameters:
    ///   - router: connects the sound of the sources on air to the mix.
    ///   - microphoneAccess: asks macOS for the microphone.
    init(router: SoundRouting, microphoneAccess: MicrophoneAccessRequesting) {
        self.router = router
        self.microphoneAccess = microphoneAccess
    }

    func apply(_ settings: SoundSettings) {
        // Cameras hand over their own microphones' sound, which macOS only
        // lets them do once it has been asked.
        if settings.isOn {
            microphoneAccess.requestAccess()
        }
    }

    func setSourceLevels(_ levels: [UUID: Double]) {
        router.apply(levels: levels)
    }
}
