import CamTwistCore
import Foundation

/// Small switches about how the app itself behaves.
public struct AppPreferences: Codable, Equatable {
    public var mirrorsPreview = false
    public var keepsWindowOnTop = false

    /// Where snapshots are saved. Nil means the Desktop.
    public var snapshotsFolder: String?

    /// Optional so preferences saved before it existed still load.
    public var autosavesSetting: Bool?

    /// Whether a setup that has a file is saved to it after every change.
    public var autosaves: Bool {
        get { autosavesSetting ?? false }
        set { autosavesSetting = newValue }
    }

    /// Optional so preferences saved before it existed still load.
    public var webStreamSettings: WebStreamSettings?

    /// The HLS stream.
    public var webStream: WebStreamSettings {
        get { webStreamSettings ?? WebStreamSettings() }
        set { webStreamSettings = newValue }
    }

    /// Optional so preferences saved before it existed still load.
    public var webMovieSettings: WebStreamSettings?

    /// The endless MP4, served apart from the HLS stream on a port of its own.
    public var webMovie: WebStreamSettings {
        get { webMovieSettings ?? WebStreamSettings(port: WebStreamSettings.defaultMoviePort) }
        set { webMovieSettings = newValue }
    }

    /// Optional so preferences saved before it existed still load.
    public var rtmpSettings: RTMPSettings?

    public var rtmp: RTMPSettings {
        get { rtmpSettings ?? RTMPSettings() }
        set { rtmpSettings = newValue }
    }

    /// Optional so preferences saved before it existed still load.
    public var airPlayEnabled: Bool?

    /// Whether the picture is offered to an AirPlay device.
    public var sendsToAirPlay: Bool {
        get { airPlayEnabled ?? false }
        set { airPlayEnabled = newValue }
    }

    /// Optional so preferences saved before it existed still load.
    public var recordingSettings: RecordingOptions?

    /// How a recording is made. Whatever is put here is made to fit the
    /// rules about what goes with what, so it can always be recorded.
    public var recording: RecordingOptions {
        get { RecordingRules.usable(recordingSettings ?? RecordingOptions()) }
        set { recordingSettings = RecordingRules.usable(newValue) }
    }

    /// Where recordings are saved. Nil means wherever snapshots go.
    public var recordingsFolder: String?

    /// Optional so preferences saved before it existed still load.
    public var castEnabled: Bool?

    /// Whether the picture is played on a Cast device.
    public var sendsToCast: Bool {
        get { castEnabled ?? false }
        set { castEnabled = newValue }
    }

    /// The Cast device chosen, by the name it gives itself. Nil until one is chosen.
    public var castDeviceName: String?

    /// The HLS stream as it has to be served: switched on for its own
    /// sake, or because AirPlay or a Cast device plays from it.
    public var servedWebStream: WebStreamSettings {
        var stream = webStream
        stream.isOn = stream.isOn || sendsToAirPlay || sendsToCast
        return stream
    }

    /// Optional so preferences saved before it existed still load.
    public var microphoneEnabled: Bool?

    /// Whether the mix goes to the virtual microphone.
    public var sendsToMicrophone: Bool {
        get { microphoneEnabled ?? false }
        set { microphoneEnabled = newValue }
    }

    /// Optional so preferences saved before it existed still load.
    public var cameraEnabled: Bool?

    /// Whether the picture goes to the virtual camera. It does unless switched off.
    public var sendsToCamera: Bool {
        get { cameraEnabled ?? true }
        set { cameraEnabled = newValue }
    }

    /// The pictures the outputs encode: which of them are switched on, and
    /// how tall each wants its picture. Recording is a thing done now, not
    /// a setting, so whether it is under way is said from outside.
    func pictureDemands(isRecording: Bool) -> [PictureDemand] {
        [
            PictureDemand(isOn: servedWebStream.isOn, height: webStream.options.usable.height),
            PictureDemand(isOn: webMovie.isOn, height: webMovie.options.usable.height),
            PictureDemand(isOn: rtmp.isOn, height: rtmp.options.usable.height),
            PictureDemand(isOn: isRecording, height: recording.height),
        ]
    }
}
