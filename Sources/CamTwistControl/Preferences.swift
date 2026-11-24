import CamTwistCore
import Foundation

/// Puts the app's preferences into effect.
@MainActor
struct PreferenceApplier {
    let monitor: PreviewMirroring
    let windows: WindowKeeping
    let webStream: WebStreamSwitching
    let webMovie: WebStreamSwitching
    let camera: CameraConnectionReporting
    let rtmp: RTMPSwitching
    let sound: SoundCapturing
    let microphone: MicrophoneSwitching
    let drawing: DrawingSizing
    let drawingSizes: DrawingSizeChoosing

    /// - Parameter isHeard: whether any scene has a source that makes
    ///   sound with its volume up. The streams carry sound exactly when
    ///   one does; with none they go out with no sound track at all.
    /// - Parameter isRecording: whether a recording is under way, which
    ///   counts among the outputs when the picture's detail is chosen.
    func apply(_ preferences: AppPreferences, isHeard: Bool, isRecording: Bool) {
        let withSound = isHeard
        monitor.isMirrored = preferences.mirrorsPreview
        windows.keepOnTop(preferences.keepsWindowOnTop)
        webStream.apply(preferences.servedWebStream, withSound: withSound)
        webMovie.apply(preferences.webMovie, withSound: withSound)
        camera.isEnabled = preferences.sendsToCamera
        rtmp.apply(preferences.rtmp, withSound: withSound)
        sound.apply(SoundSettings(isOn: isHeard))
        microphone.isEnabled = preferences.sendsToMicrophone
        // Nobody chooses how much detail is drawn: it follows what the outputs ask for.
        drawing.setDrawingSize(drawingSizes.size(for: preferences.pictureDemands(isRecording: isRecording)))
    }
}
