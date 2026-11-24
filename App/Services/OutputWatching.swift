import AVFoundation
import CamTwistControl
import CamTwistCore
import SwiftUI

/// What the views watch of the AirPlay output.
protocol AirPlayWatching: AnyObject {
    /// The player the device picker sends to a device.
    var player: AVPlayer { get }
    /// Whether the picture is playing on a device right now.
    var isOnDevice: Bool { get }
}

/// What a view gets when no AirPlay output was handed down to it: a player
/// that plays nothing, on no device.
private final class NoAirPlay: AirPlayWatching {
    let player = AVPlayer()
    let isOnDevice = false
}

/// What a view gets when no Cast output was handed down to it: no devices.
private final class NoCast: CastWatching {
    let devices: [CastDevice] = []
    let state = CastState.idle
}

private struct AirPlayKey: EnvironmentKey {
    static let defaultValue: AirPlayWatching = NoAirPlay()
}

private struct CastKey: EnvironmentKey {
    static let defaultValue: CastWatching = NoCast()
}

extension EnvironmentValues {
    /// The AirPlay output, as far as the views need it.
    var airPlay: AirPlayWatching {
        get { self[AirPlayKey.self] }
        set { self[AirPlayKey.self] = newValue }
    }

    /// The Cast output, as far as the views need it.
    var cast: CastWatching {
        get { self[CastKey.self] }
        set { self[CastKey.self] = newValue }
    }
}
