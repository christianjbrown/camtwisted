import Foundation

/// How far playing on a Cast device has got.
public enum CastState: Equatable, Sendable {
    case idle
    /// Connected, and asking the device to start its player.
    case starting
    /// The player is up and has been given the stream.
    case loading
    case playing
    case failed(String)
}

/// The conversation with a Cast device that gets a stream playing on it:
/// say hello, start the device's own media player, hand it the stream's
/// address, and keep answering its pings. Everything here is the words;
/// the connection that carries them is elsewhere.
public struct CastSession: Equatable, Sendable {
    private enum Namespace {
        static let connection = "urn:x-cast:com.google.cast.tp.connection"
        static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
        static let receiver = "urn:x-cast:com.google.cast.receiver"
        static let media = "urn:x-cast:com.google.cast.media"
    }

    private enum Party {
        static let sender = "sender-0"
        static let device = "receiver-0"
    }

    private enum Key {
        static let type = "type"
        static let requestID = "requestId"
        static let appID = "appId"
        static let status = "status"
        static let applications = "applications"
        static let transportID = "transportId"
        static let sessionID = "sessionId"
        static let playerState = "playerState"
        static let media = "media"
        static let contentID = "contentId"
        static let contentType = "contentType"
        static let streamType = "streamType"
        static let segmentFormat = "hlsSegmentFormat"
        static let videoSegmentFormat = "hlsVideoSegmentFormat"
        static let autoplay = "autoplay"
    }

    private enum Word {
        static let connect = "CONNECT"
        static let close = "CLOSE"
        static let ping = "PING"
        static let pong = "PONG"
        static let launch = "LAUNCH"
        static let launchError = "LAUNCH_ERROR"
        static let stop = "STOP"
        static let load = "LOAD"
        static let receiverStatus = "RECEIVER_STATUS"
        static let mediaStatus = "MEDIA_STATUS"
        static let live = "LIVE"
        static let playing = "PLAYING"
        static let buffering = "BUFFERING"
        /// The ways a device says it will not play what it was given.
        static let refusals = ["LOAD_FAILED", "LOAD_CANCELLED", "INVALID_REQUEST"]
    }

    /// The media player every Cast device has, and what the stream is.
    private static let mediaPlayerAppID = "CC1AD845"
    private static let playlistType = "application/x-mpegURL"
    /// The stream's pieces are fragmented MP4, which the player has to be told.
    private static let fragmentedMP4 = "fmp4"

    public private(set) var state = CastState.idle
    private let streamAddress: String
    private var nextRequest = 1
    /// The player's own address on the device, once it has started.
    private var transport: String?
    private var sessionID: String?

    /// - Parameter streamAddress: where the device fetches the HLS stream from.
    public init(streamAddress: String) {
        self.streamAddress = streamAddress
    }

    /// The connection is up: say hello and ask for the media player.
    public mutating func connected() -> [CastMessage] {
        state = .starting
        return [
            message(Namespace.connection, to: Party.device, [Key.type: Word.connect]),
            request(Namespace.receiver, to: Party.device, [Key.type: Word.launch, Key.appID: Self.mediaPlayerAppID]),
        ]
    }

    /// Something to say every few seconds, so the device keeps listening.
    public func ping() -> CastMessage {
        message(Namespace.heartbeat, to: Party.device, [Key.type: Word.ping])
    }

    /// Takes in what the device said and gives back what to say in return.
    public mutating func received(_ incoming: CastMessage) -> [CastMessage] {
        guard let payload = Self.object(incoming.payload), let type = payload[Key.type] as? String else { return [] }
        switch (incoming.namespace, type) {
        case (Namespace.heartbeat, Word.ping):
            return [message(Namespace.heartbeat, to: Party.device, [Key.type: Word.pong])]
        case (Namespace.connection, Word.close):
            state = .failed("The device closed the connection.")
            return []
        case (Namespace.receiver, Word.launchError):
            state = .failed("The device could not start its player.")
            return []
        case (Namespace.receiver, Word.receiverStatus):
            return playerStatus(payload)
        case (Namespace.media, Word.mediaStatus):
            mediaStatus(payload)
            return []
        case (Namespace.media, _) where Word.refusals.contains(type):
            state = .failed("The device could not play the stream.")
            return []
        default:
            return []
        }
    }

    /// Stops the player on the device and says goodbye.
    public mutating func stop() -> [CastMessage] {
        var messages: [CastMessage] = []
        if let sessionID {
            messages.append(request(Namespace.receiver, to: Party.device, [Key.type: Word.stop, Key.sessionID: sessionID]))
        }
        messages.append(message(Namespace.connection, to: Party.device, [Key.type: Word.close]))
        state = .idle
        transport = nil
        sessionID = nil
        return messages
    }

    /// The connection has gone.
    public mutating func lost(_ reason: String) {
        state = .failed(reason)
        transport = nil
        sessionID = nil
    }

    /// The device says what it is running. Once that is the media player,
    /// it is given the stream; if the player then goes away, so has the picture.
    private mutating func playerStatus(_ payload: [String: Any]) -> [CastMessage] {
        let status = payload[Key.status] as? [String: Any]
        let applications = status?[Key.applications] as? [[String: Any]]
        let player = applications?.first { $0[Key.appID] as? String == Self.mediaPlayerAppID }
        guard let player, let address = player[Key.transportID] as? String else {
            if transport != nil {
                lost("It was stopped on the device.")
            }
            return []
        }
        guard transport == nil else { return [] }
        transport = address
        sessionID = player[Key.sessionID] as? String
        state = .loading
        let media: [String: Any] = [
            Key.contentID: streamAddress,
            Key.contentType: Self.playlistType,
            Key.streamType: Word.live,
            Key.segmentFormat: Self.fragmentedMP4,
            Key.videoSegmentFormat: Self.fragmentedMP4,
        ]
        return [
            message(Namespace.connection, to: address, [Key.type: Word.connect]),
            request(Namespace.media, to: address, [Key.type: Word.load, Key.media: media, Key.autoplay: true]),
        ]
    }

    private mutating func mediaStatus(_ payload: [String: Any]) {
        let states = (payload[Key.status] as? [[String: Any]])?.compactMap { $0[Key.playerState] as? String }
        if states?.contains(where: { $0 == Word.playing || $0 == Word.buffering }) == true {
            state = .playing
        }
    }

    /// A message that asks for something carries a number of its own.
    private mutating func request(_ namespace: String, to destination: String, _ fields: [String: Any]) -> CastMessage {
        var numbered = fields
        numbered[Key.requestID] = nextRequest
        nextRequest += 1
        return message(namespace, to: destination, numbered)
    }

    private func message(_ namespace: String, to destination: String, _ fields: [String: Any]) -> CastMessage {
        CastMessage(source: Party.sender, destination: destination, namespace: namespace, payload: Self.text(fields))
    }

    /// JSON with its keys in order, so the same fields always read the same.
    static func text(_ fields: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(fields),
              let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func object(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
}
