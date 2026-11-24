import AVFoundation
import CamTwistControl
import CamTwistCore
import Foundation
import Observation

/// Plays the HLS stream this Mac serves on an AirPlay device. The device
/// is chosen with the system's own picker, and then fetches the stream
/// from this Mac itself.
@Observable
final class AirPlayOutput: AirPlaySwitching, AirPlayWatching {
    /// The player the device picker sends to a device.
    let player: AVPlayer
    /// The queue what the views watch is changed on, and retries wait on.
    private let main: DispatchQueue
    /// Whether the picture is playing on a device right now.
    private(set) var isOnDevice = false

    /// How long to wait before trying again when the stream cannot be played yet.
    private let retryDelay: TimeInterval
    private var address: String?
    private var observations: [NSKeyValueObservation] = []
    private var itemObservation: NSKeyValueObservation?

    init(player: AVPlayer, main: DispatchQueue, retryDelay: TimeInterval) {
        self.player = player
        self.main = main
        self.retryDelay = retryDelay
        player.allowsExternalPlayback = true
        // Until a device is chosen the stream plays here, unseen. It is
        // kept silent, or it would be heard out of this Mac as well.
        player.volume = AirPlayPolicy.volume(isOnDevice: false)
        observations.append(player.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] player, _ in
            main.async {
                self?.isOnDevice = player.isExternalPlaybackActive
                player.volume = AirPlayPolicy.volume(isOnDevice: player.isExternalPlaybackActive)
            }
        })
    }

    func apply(isOn: Bool, address: String?) {
        let wanted = AirPlayPolicy.wantedAddress(isOn: isOn, address: address)
        guard wanted != self.address else { return }
        self.address = wanted
        play()
    }

    private func play() {
        itemObservation = nil
        guard let address, let url = URL(string: address) else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            return
        }
        let item = AVPlayerItem(url: url)
        // The stream may not have its first pieces yet: if it cannot be
        // played, it is tried again shortly.
        let retryDelay = self.retryDelay
        let main = self.main
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            main.asyncAfter(deadline: .now() + retryDelay) {
                guard let self, self.player.currentItem === item else { return }
                self.play()
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }
}
