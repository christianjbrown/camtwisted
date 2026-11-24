import CamTwistCore
import CamTwistRendering
import Foundation

/// The players elsewhere that show the picture by playing the HLS stream:
/// AirPlay screens and Cast devices.
@MainActor
final class DevicesModel {
    /// The settings that say whether to play, and on which Cast device.
    private var preferences: AppPreferences

    private let airPlay: AirPlaySwitching
    private let cast: CastSwitching
    private let stream: StreamAddressing

    init(preferences: AppPreferences, airPlay: AirPlaySwitching, cast: CastSwitching, stream: StreamAddressing) {
        self.preferences = preferences
        self.airPlay = airPlay
        self.cast = cast
        self.stream = stream
    }

    /// Takes the settings as they now are, and tells AirPlay and Cast.
    func follow(_ preferences: AppPreferences) {
        self.preferences = preferences
        refresh()
    }

    /// Tells AirPlay and Cast whether to play and where the stream is.
    /// Said again each time round, since this Mac's address can change.
    func refresh() {
        let address = stream.webStreamLinks.first?.address
        airPlay.apply(isOn: preferences.sendsToAirPlay, address: address)
        cast.apply(isOn: preferences.sendsToCast, address: address, deviceName: preferences.castDeviceName)
    }
}
