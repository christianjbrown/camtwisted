import CamTwistCore
import Foundation

/// Where the picture is going and how that is getting on. Each output has
/// a part of its own; this holds them and passes on what all of them are told.
@MainActor
public final class OutputsModel {
    /// The virtual camera.
    public let camera: CameraOutputModel
    /// The virtual microphone.
    public let microphone: MicrophoneOutputModel
    /// The web streams and the stream to an RTMP server.
    public let streams: StreamsModel
    /// AirPlay screens and Cast devices, which play the HLS stream.
    let devices: DevicesModel

    init(camera: CameraOutputModel, microphone: MicrophoneOutputModel, streams: StreamsModel, devices: DevicesModel) {
        self.camera = camera
        self.microphone = microphone
        self.streams = streams
        self.devices = devices
    }

    /// Takes the settings as they now are. The streams hear first, since
    /// the players are told where the stream is.
    func follow(_ preferences: AppPreferences) {
        streams.follow(preferences)
        devices.follow(preferences)
    }

    /// Looks again at how everything is getting on.
    func refresh() {
        camera.refresh()
        microphone.refresh()
        streams.refresh()
        devices.refresh()
    }

    /// Marks, in the streams that mark them, that a different scene is on air.
    func markScene(named name: String) {
        streams.markScene(named: name)
    }
}
