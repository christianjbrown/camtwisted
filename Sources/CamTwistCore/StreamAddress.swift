import Foundation

/// A stream played from an address: a live stream, or a video on a server.
public struct StreamSettings: Codable, Equatable, Sendable {
    public static let fullVolume = 1.0

    /// Where the stream is: a web address, or a file's path.
    public var address: String
    /// From silent at 0 to full at 1.
    public var volume: Double

    public init(address: String = "", volume: Double = StreamSettings.fullVolume) {
        self.address = address
        self.volume = volume
    }
}

/// Reads what somebody typed as the address of a stream.
public enum StreamAddress {
    /// The kinds of address the player can open. RTMP is not one: macOS
    /// has no player for it.
    private static let playableSchemes: Set<String> = ["http", "https", "file"]
    private static let schemeMark = "://"
    private static let pathStart = "/"
    private static let assumedScheme = "https://"

    /// The address as something to play, or nil when there is nothing to
    /// play or it is a kind that cannot be. A bare path is a file, and an
    /// address with no scheme is taken as a secure web address.
    public static func url(from text: String) -> URL? {
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        if address.hasPrefix(pathStart) {
            return URL(fileURLWithPath: address)
        }
        guard address.contains(schemeMark) else {
            return URL(string: assumedScheme + address)
        }
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              playableSchemes.contains(scheme)
        else { return nil }
        return url
    }
}
