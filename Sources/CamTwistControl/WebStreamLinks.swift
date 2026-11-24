import CamTwistCore
import Foundation

/// An address another device can open to watch the web stream.
public struct WebStreamLink: Equatable, Identifiable {
    public let title: String
    public let address: String

    public var id: String { title }
}

/// Works out the addresses of the web stream.
enum WebStreamLinks {
    /// Used when this Mac has no address on a network: only it can watch.
    private static let thisMacOnly = "localhost"
    private static let pageTitle = "Page that plays it"
    private static let playlistTitle = "HLS"
    private static let movieTitle = "MP4"

    /// Where the HLS stream is: its playlist, and a page that plays it.
    static func streamLinks(hosts: [String], port: Int) -> [WebStreamLink] {
        let base = base(hosts: hosts, port: port)
        return [
            WebStreamLink(title: playlistTitle, address: base + WebStreamRoute.playlistName),
            WebStreamLink(title: pageTitle, address: base),
        ]
    }

    /// Where the endless MP4 is.
    static func movieLinks(hosts: [String], port: Int) -> [WebStreamLink] {
        [WebStreamLink(title: movieTitle, address: base(hosts: hosts, port: port) + WebStreamRoute.movieName)]
    }

    private static func base(hosts: [String], port: Int) -> String {
        "http://\(hosts.first ?? thisMacOnly):\(port)/"
    }
}
