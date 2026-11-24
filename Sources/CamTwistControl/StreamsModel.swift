import CamTwistCore
import CamTwistRendering
import Foundation
import Observation

/// The streams the picture goes out on: the HLS and MP4 web streams and
/// the one to an RTMP server.
@MainActor
@Observable
public final class StreamsModel: QuietlyAssigning {
    /// Whether the web stream is being served, or why it is not.
    public private(set) var webStreamStatus = WebStreamStatus.off
    /// Whether the endless MP4 is being served, or why it is not.
    public private(set) var webMovieStatus = WebStreamStatus.off
    /// How far the stream to an RTMP server has got.
    public private(set) var rtmpStatus = RTMPState.idle
    /// The settings that say which ports the web streams are on.
    private var preferences: AppPreferences

    private let webStream: WebStreamSwitching
    private let webMovie: WebStreamSwitching
    private let rtmp: RTMPSwitching
    private let links: StreamLinkListing
    private let addresses: NetworkAddressListing

    init(
        preferences: AppPreferences, webStream: WebStreamSwitching, webMovie: WebStreamSwitching,
        rtmp: RTMPSwitching, links: StreamLinkListing, addresses: NetworkAddressListing
    ) {
        self.preferences = preferences
        self.webStream = webStream
        self.webMovie = webMovie
        self.rtmp = rtmp
        self.links = links
        self.addresses = addresses
    }

    /// Takes the settings as they now are.
    func follow(_ preferences: AppPreferences) {
        self.preferences = preferences
    }

    /// Looks again at how each stream is getting on.
    func refresh() {
        assign(\.webStreamStatus, webStream.status)
        assign(\.webMovieStatus, webMovie.status)
        assign(\.rtmpStatus, rtmp.status)
    }

    /// Marks, in the streams that mark them, that a different scene is on air.
    func markScene(named name: String) {
        webStream.markScene(named: name)
        webMovie.markScene(named: name)
        rtmp.markScene(named: name)
    }

    /// Where other devices can watch the HLS stream.
    public var webStreamLinks: [WebStreamLink] {
        links.streamLinks(hosts: addresses.localAddresses(), port: preferences.webStream.usablePort)
    }

    /// Where other devices can watch the endless MP4.
    public var webMovieLinks: [WebStreamLink] {
        links.movieLinks(hosts: addresses.localAddresses(), port: preferences.webMovie.usablePort)
    }
}

/// Says where the HLS stream can be watched, for whatever plays it.
@MainActor
protocol StreamAddressing: AnyObject {
    var webStreamLinks: [WebStreamLink] { get }
}

extension StreamsModel: StreamAddressing {}
