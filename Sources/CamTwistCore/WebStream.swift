import Foundation

/// Whether a stream is served to other devices over the local network,
/// on which port, and how it is encoded.
public struct WebStreamSettings: Codable, Equatable, Sendable {
    public static let defaultPort = 8090
    /// The port the endless MP4 starts on, apart from the HLS stream's.
    public static let defaultMoviePort = 8091
    public static let portRange: ClosedRange<Int> = 1024...65535

    public var isOn: Bool
    public var port: Int
    /// Optional so settings saved before streams had options still load.
    public var streamOptions: StreamOptions?

    public init(isOn: Bool = false, port: Int = WebStreamSettings.defaultPort, options: StreamOptions = .web) {
        self.isOn = isOn
        self.port = port
        streamOptions = options
    }

    public var options: StreamOptions {
        get { streamOptions ?? .web }
        set { streamOptions = newValue }
    }

    /// The port, held to the ones an ordinary app may listen on.
    public var usablePort: Int {
        min(max(port, Self.portRange.lowerBound), Self.portRange.upperBound)
    }
}

/// What the web stream is doing.
public enum WebStreamStatus: Equatable, Sendable {
    case off
    case running
    case failed(String)
}

/// One piece of the stream: a second or so of video.
public struct StreamSegment: Equatable, Sendable {
    public let sequence: Int
    public let duration: Double
    /// Seconds into the stream that this piece begins.
    public let startsAt: Double
    public let data: Data
}

/// A scene coming on air, to be marked in a stream.
public struct SceneMarker: Equatable, Sendable {
    public let number: Int
    public let name: String
    public let date: Date
}

/// The last few pieces of a live stream, with the header every player
/// needs first. Older pieces fall off the end as new ones arrive.
public struct SegmentWindow: Equatable, Sendable {
    public private(set) var initialization: Data?
    public private(set) var segments: [StreamSegment] = []
    /// The moment, by the clock on the wall, that the stream began. Players
    /// are told it so that markers can be placed in time.
    public private(set) var origin: Date?
    /// Scene changes still worth telling players about.
    public private(set) var markers: [SceneMarker] = []
    private var nextSequence = 0
    private var nextMarker = 0
    /// Seconds of stream in the pieces so far.
    private var length = 0.0
    /// How many pieces a player can still fetch.
    private let capacity: Int

    public init(capacity: Int = Pacing.usual.streamPiecesKept) {
        self.capacity = capacity
    }

    /// Says when the stream began, the first time it is told.
    public mutating func setOrigin(_ date: Date) {
        origin = origin ?? date
    }

    /// Notes that a scene came on air at some moment.
    public mutating func mark(scene name: String, at date: Date) {
        markers.append(SceneMarker(number: nextMarker, name: name, date: date))
        nextMarker += 1
        dropOldMarkers()
    }

    /// When the oldest piece still on offer begins, once the stream's
    /// beginning is known.
    public var firstSegmentDate: Date? {
        guard let origin, let first = segments.first else { return nil }
        return origin.addingTimeInterval(first.startsAt)
    }

    /// Markers from before the oldest piece are no use to a player, bar the
    /// latest of them, which says what scene the stream is on.
    private mutating func dropOldMarkers() {
        guard let start = firstSegmentDate else { return }
        let old = markers.filter { $0.date < start }
        markers.removeAll { $0.date < start && $0.number != old.last?.number }
    }

    public mutating func setInitialization(_ data: Data) {
        initialization = data
    }

    @discardableResult
    public mutating func append(_ data: Data, duration: Double) -> StreamSegment {
        let segment = StreamSegment(sequence: nextSequence, duration: duration, startsAt: length, data: data)
        nextSequence += 1
        length += duration
        segments.append(segment)
        if segments.count > capacity {
            segments.removeFirst(segments.count - capacity)
        }
        dropOldMarkers()
        return segment
    }

    public func segment(numbered sequence: Int) -> StreamSegment? {
        segments.first { $0.sequence == sequence }
    }
}

/// Writes the playlist an HLS player reads to find the pieces.
public enum HLSPlaylist {
    /// The HLS version that allows fragmented MP4 pieces.
    private static let version = 7

    public static func text(for window: SegmentWindow) -> String {
        let longest = window.segments.map(\.duration).max() ?? 1
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:\(version)",
            "#EXT-X-TARGETDURATION:\(Int(longest.rounded(.up)))",
            "#EXT-X-MEDIA-SEQUENCE:\(window.segments.first?.sequence ?? 0)",
            "#EXT-X-MAP:URI=\"\(WebStreamRoute.initializationName)\"",
        ]
        // The time on the wall of the first piece lets players place the
        // markers, each of which says when a scene came on air.
        if let start = window.firstSegmentDate {
            lines.append("#EXT-X-PROGRAM-DATE-TIME:\(timestamp(start))")
            for marker in window.markers {
                lines.append(
                    "#EXT-X-DATERANGE:ID=\"scene-\(marker.number)\",START-DATE=\"\(timestamp(marker.date))\""
                        + ",X-SCENE=\"\(quotable(marker.name))\""
                )
            }
        }
        for segment in window.segments {
            lines.append(String(format: "#EXTINF:%.3f,", segment.duration))
            lines.append(WebStreamRoute.segmentName(segment.sequence))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension HLSPlaylist {
    private static let unquotable: Set<Character> = ["\"", "\n", "\r"]

    /// A moment as the playlist format writes it: to the millisecond, in UTC.
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// A name with whatever would break out of a quoted value taken out.
    static func quotable(_ name: String) -> String {
        String(name.filter { !unquotable.contains($0) })
    }
}

/// Builds the box that carries an event in a fragmented MP4 stream, which
/// is how a scene change is marked in the endless MP4.
public enum EventMessageBox {
    /// Says what kind of event this is, to players that look for it.
    public static let scheme = "urn:camtwisted:scene"
    private static let boxType = "emsg"
    /// The version of the box that carries its time as a moment in the stream.
    private static let version: UInt8 = 1
    private static let millisecondsPerSecond = 1000.0
    private static let sizeLength = 4
    private static let flagsLength = 3
    private static let shortLength = 4
    private static let timeLength = 8
    /// An event with no set length.
    private static let unknownDuration: UInt64 = 0xFFFF_FFFF

    /// A box saying a scene came on air, a number of seconds into the stream.
    public static func data(scene name: String, number: Int, atSeconds seconds: Double) -> Data {
        var body = Data(boxType.utf8)
        body.append(version)
        body += Data(count: flagsLength)
        body += ByteOrder.bigEndian(UInt64(millisecondsPerSecond), bytes: shortLength)
        body += ByteOrder.bigEndian(UInt64(max(seconds, 0) * millisecondsPerSecond), bytes: timeLength)
        body += ByteOrder.bigEndian(unknownDuration, bytes: shortLength)
        body += ByteOrder.bigEndian(UInt64(number), bytes: shortLength)
        body += Data(scheme.utf8) + Data([0])
        body += Data([0])
        body += Data(name.utf8)
        return ByteOrder.bigEndian(UInt64(body.count + sizeLength), bytes: sizeLength) + body
    }
}

/// What an address on the web stream's server asks for.
public enum WebStreamRoute: Equatable, Sendable {
    /// A page that plays the stream.
    case page
    case playlist
    case initialization
    case segment(Int)
    /// The whole stream as one endless MP4.
    case movie
    case unknown

    public static let playlistName = "stream.m3u8"
    public static let movieName = "stream.mp4"
    public static let initializationName = "init.mp4"
    private static let segmentPrefix = "segment-"
    private static let segmentSuffix = ".m4s"
    private static let separator = "/"
    private static let queryMark: Character = "?"

    public static func segmentName(_ sequence: Int) -> String {
        segmentPrefix + String(sequence) + segmentSuffix
    }

    public init(path: String) {
        // Players add cache-busting queries; only the name matters.
        let name = String(path.prefix { $0 != Self.queryMark })
            .trimmingCharacters(in: CharacterSet(charactersIn: Self.separator))
        switch name {
        case "": self = .page
        case Self.playlistName: self = .playlist
        case Self.initializationName: self = .initialization
        case Self.movieName: self = .movie
        default:
            guard name.hasPrefix(Self.segmentPrefix), name.hasSuffix(Self.segmentSuffix),
                  let sequence = Int(name.dropFirst(Self.segmentPrefix.count).dropLast(Self.segmentSuffix.count))
            else {
                self = .unknown
                return
            }
            self = .segment(sequence)
        }
    }
}

/// The first line of a request from a browser or player.
public struct HTTPRequest: Equatable, Sendable {
    public let method: String
    public let path: String

    private static let lineEnd = "\r\n"
    private static let partsInRequestLine = 3

    /// Reads the request line from what a client sent, or nil when it is
    /// not one.
    public init?(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8),
              let line = text.components(separatedBy: Self.lineEnd).first
        else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count == Self.partsInRequestLine else { return nil }
        method = String(parts[0])
        path = String(parts[1])
    }
}

/// An answer to send back.
public struct HTTPResponse: Equatable, Sendable {
    public enum ContentType: String, Sendable {
        case playlist = "application/vnd.apple.mpegurl"
        case video = "video/mp4"
        case page = "text/html; charset=utf-8"
        case text = "text/plain; charset=utf-8"
    }

    public static let ok = 200
    public static let notFound = 404

    public let status: Int
    public let contentType: ContentType
    public let body: Data

    private static let reasons = [ok: "OK", notFound: "Not Found"]
    private static let lineEnd = "\r\n"

    public init(status: Int = HTTPResponse.ok, contentType: ContentType, body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    public static var missing: HTTPResponse {
        HTTPResponse(status: notFound, contentType: .text, body: Data("Not found\n".utf8))
    }

    /// The whole answer, headers then body, for a client that gets it in one go.
    public var data: Data {
        Self.head(status: status, contentType: contentType, length: body.count) + body
    }

    /// Headers alone. With no length the body carries on until the
    /// connection closes, which is how an endless video is sent.
    public static func head(status: Int = HTTPResponse.ok, contentType: ContentType, length: Int?) -> Data {
        var lines = [
            "HTTP/1.1 \(status) \(reasons[status, default: ""])",
            "Content-Type: \(contentType.rawValue)",
            // Anything on the network may play it, including a page from elsewhere.
            "Access-Control-Allow-Origin: *",
            "Cache-Control: no-cache",
            "Connection: close",
        ]
        if let length {
            lines.append("Content-Length: \(length)")
        }
        return Data((lines.joined(separator: lineEnd) + lineEnd + lineEnd).utf8)
    }
}

/// The page served at the top of the web stream: a player for it.
public enum WebStreamPage {
    public static func html(title: String) -> String {
        """
        <!doctype html>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>html,body{margin:0;height:100%;background:#000}video{width:100%;height:100%}</style>
        <video src="\(WebStreamRoute.playlistName)" autoplay muted playsinline controls></video>

        """
    }
}
