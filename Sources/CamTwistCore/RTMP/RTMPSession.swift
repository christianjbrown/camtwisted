import Foundation

/// Where an RTMP stream is sent: the server, the application on it, and
/// the key that names the stream.
public struct RTMPTarget: Equatable, Sendable {
    public static let defaultPort = 1935
    public static let defaultSecurePort = 443

    public let host: String
    public let port: Int
    /// Whether the connection is encrypted (an address that starts rtmps).
    public let isSecure: Bool
    public let application: String
    /// The server's address without the stream key, as the server expects
    /// to be told it.
    public let serverAddress: String
    public let streamKey: String

    private static let plainScheme = "rtmp"
    private static let secureScheme = "rtmps"
    private static let separator = "/"

    /// Reads a server address such as `rtmp://example.com/live` and a
    /// stream key. Nil when the address is not an RTMP one or names no
    /// application, or there is no key.
    public init?(address: String, streamKey: String) {
        let key = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let parts = URLComponents(string: trimmed), let host = parts.host, !host.isEmpty,
              let scheme = parts.scheme?.lowercased(), scheme == Self.plainScheme || scheme == Self.secureScheme
        else { return nil }
        let application = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: Self.separator))
        guard !application.isEmpty else { return nil }
        let isSecure = scheme == Self.secureScheme
        let port = parts.port ?? (isSecure ? Self.defaultSecurePort : Self.defaultPort)
        self.host = host
        self.port = port
        self.isSecure = isSecure
        self.application = application
        self.streamKey = key
        serverAddress = "\(scheme)://\(host):\(port)/\(application)"
    }
}

/// How far a stream has got.
public enum RTMPState: Equatable, Sendable {
    case idle
    /// Talking to the server, not yet sending the picture.
    case connecting
    case live
    case failed(String)
}

/// What the picture being sent is like, which the server is told before
/// the first frame.
public struct RTMPVideoDetails: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let framesPerSecond: Int
    public let bitsPerSecond: Int

    public init(width: Int, height: Int, framesPerSecond: Int, bitsPerSecond: Int) {
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.bitsPerSecond = bitsPerSecond
    }
}

/// Builds the pieces of video RTMP carries, which are FLV video tags.
public enum FLVVideo {
    private static let keyFrame: UInt8 = 0x10
    private static let betweenFrame: UInt8 = 0x20
    private static let avcCodec: UInt8 = 0x07
    private static let sequenceHeaderPacket: UInt8 = 0
    private static let framePacket: UInt8 = 1
    private static let noCompositionOffset: [UInt8] = [0, 0, 0]
    private static let configurationVersion: UInt8 = 1
    /// Reserved bits set, with lengths written in four bytes.
    private static let fourByteLengths: UInt8 = 0xFF
    /// Reserved bits set, with one parameter set.
    private static let oneSet: UInt8 = 0xE1
    private static let setLengthBytes = 2
    /// The profile, compatibility and level sit just after a parameter set's first byte.
    private static let profileRange = 1...3

    /// The tag that tells a player how to decode what follows, made from
    /// the encoder's two parameter sets. Nil when the first is too short
    /// to hold a profile.
    public static func sequenceHeader(sequenceParameters: Data, pictureParameters: Data) -> Data? {
        guard sequenceParameters.count > profileRange.upperBound else { return nil }
        let start = sequenceParameters.startIndex
        var record = Data([configurationVersion])
        record += sequenceParameters[(start + profileRange.lowerBound)...(start + profileRange.upperBound)]
        record += Data([fourByteLengths, oneSet])
        record += ByteOrder.bigEndian(UInt64(sequenceParameters.count), bytes: setLengthBytes) + sequenceParameters
        record += Data([1]) + ByteOrder.bigEndian(UInt64(pictureParameters.count), bytes: setLengthBytes)
        record += pictureParameters
        return Data([keyFrame | avcCodec, sequenceHeaderPacket] + noCompositionOffset) + record
    }

    /// A frame's tag. The frame is as the encoder gives it: each unit with
    /// its length in front.
    public static func frame(_ data: Data, isKeyFrame: Bool) -> Data {
        Data([(isKeyFrame ? keyFrame : betweenFrame) | avcCodec, framePacket] + noCompositionOffset) + data
    }
}

/// The conversation with an RTMP server that ends with a stream being
/// published: the handshake, connecting to the application, and asking to
/// publish. It is fed what the server sends and says what to send back.
public struct RTMPSession {
    private enum Handshake {
        static let version: UInt8 = 3
        /// The size of each side's block of the handshake.
        static let blockSize = 1536
        /// The server's version byte and its two blocks.
        static let replySize = 1 + blockSize * 2
    }

    private enum ChunkStream {
        static let control: UInt8 = 2
        static let command: UInt8 = 3
        static let audio: UInt8 = 5
        static let video: UInt8 = 6
    }

    /// The names of the properties servers read in the messages that carry them.
    private enum Field {
        static let cueName = "name"
        static let cueTime = "time"
        static let type = "type"
        static let privacyKind = "nonprivate"
        static let application = "app"
        static let flashVersion = "flashVer"
        static let serverURL = "tcUrl"
        static let width = "width"
        static let height = "height"
        static let frameRate = "framerate"
        static let videoDataRate = "videodatarate"
        static let videoCodecID = "videocodecid"
        static let audioCodecID = "audiocodecid"
        static let audioDataRate = "audiodatarate"
        static let audioSampleRate = "audiosamplerate"
        static let stereo = "stereo"
        static let encoder = "encoder"
        /// A sound with more channels than this is stereo.
        static let monoChannels = 1
    }

    private enum Command {
        static let connect = "connect"
        static let releaseStream = "releaseStream"
        static let prepareToPublish = "FCPublish"
        static let createStream = "createStream"
        static let publish = "publish"
        static let result = "_result"
        static let error = "_error"
        static let status = "onStatus"
        static let setDataFrame = "@setDataFrame"
        static let metadata = "onMetaData"
        static let cuePoint = "onCuePoint"
        static let navigation = "navigation"
        static let live = "live"
        static let statusCode = "code"
        static let statusLevel = "level"
        static let errorLevel = "error"
        static let publishStarted = "NetStream.Publish.Start"
        /// What the encoder says it is, in the form servers expect.
        static let encoderName = "FMLE/3.0 (compatible; CamTwisted)"
        static let avcCodecID = 7.0
        static let aacCodecID = 10.0
    }

    private enum Transaction {
        static let connect = 1.0
        static let releaseStream = 2.0
        static let prepareToPublish = 3.0
        static let createStream = 4.0
        static let publish = 5.0
    }

    private static let chunkSizeBytes = 4
    private static let refused = "The server refused the stream"
    private static let bitsPerKilobit = 1000.0
    private static let millisecondsPerSecond = 1000.0

    public private(set) var state = RTMPState.idle
    private let target: RTMPTarget
    private let details: RTMPVideoDetails
    private let sound: SoundFormat?
    /// Chunks are sent this large, which suits video better than the default.
    private let outgoingChunkSize: Int
    private var handshake = Data()
    private var isHandshaking = false
    private var reader = RTMPChunkReader()
    private var streamID: UInt32 = 0

    /// - Parameter sound: what the stream's sound is like, or nil when it has none.
    /// - Parameter chunkSize: how many bytes each chunk sent holds.
    public init(
        target: RTMPTarget, details: RTMPVideoDetails, sound: SoundFormat? = nil,
        chunkSize: Int = Pacing.usual.streamChunkSize
    ) {
        self.target = target
        self.details = details
        self.sound = sound
        self.outgoingChunkSize = chunkSize
    }

    /// Opens the conversation: what to send as soon as the connection is up.
    public mutating func start() -> Data {
        state = .connecting
        isHandshaking = true
        return Data([Handshake.version]) + Data(count: Handshake.blockSize)
    }

    /// Takes what the server sent and gives back what to send in reply.
    public mutating func received(_ data: Data) -> Data {
        var incoming = data
        var reply = Data()
        if isHandshaking {
            handshake.append(data)
            guard handshake.count >= Handshake.replySize else { return Data() }
            // The reply to the server's first block is that block sent back.
            let start = handshake.startIndex
            reply += handshake[(start + 1)..<(start + 1 + Handshake.blockSize)]
            incoming = Data(handshake[(start + Handshake.replySize)...])
            handshake = Data()
            isHandshaking = false
            reply += connectRequest()
        }
        for message in reader.append(incoming) where message.typeID == RTMPMessage.Kind.command {
            reply += answer(to: AMF0.decode(message.payload))
        }
        return reply
    }

    /// A video tag as chunks ready to send, or nothing until the stream is live.
    public func video(_ tag: Data, atMilliseconds timestamp: UInt32) -> Data {
        guard state == .live else { return Data() }
        return RTMPChunkWriter.chunks(
            for: RTMPMessage(typeID: RTMPMessage.Kind.video, streamID: streamID, timestamp: timestamp, payload: tag),
            chunkStreamID: ChunkStream.video, chunkSize: outgoingChunkSize
        )
    }

    /// An audio tag as chunks ready to send, or nothing until the stream is live.
    public func audio(_ tag: Data, atMilliseconds timestamp: UInt32) -> Data {
        guard state == .live else { return Data() }
        return RTMPChunkWriter.chunks(
            for: RTMPMessage(typeID: RTMPMessage.Kind.audio, streamID: streamID, timestamp: timestamp, payload: tag),
            chunkStreamID: ChunkStream.audio, chunkSize: outgoingChunkSize
        )
    }

    /// A marker saying a scene came on air, as chunks ready to send, or
    /// nothing until the stream is live. It is a cue point, which is what
    /// this format's chapters are made of.
    public func marker(scene name: String, atMilliseconds timestamp: UInt32) -> Data {
        guard state == .live else { return Data() }
        let values: [AMF0Value] = [
            .string(Command.cuePoint),
            .object([
                AMF0Property(Field.cueName, .string(name)),
                AMF0Property(Field.cueTime, .number(Double(timestamp) / Self.millisecondsPerSecond)),
                AMF0Property(Field.type, .string(Command.navigation)),
            ]),
        ]
        return RTMPChunkWriter.chunks(
            for: RTMPMessage(
                typeID: RTMPMessage.Kind.data, streamID: streamID, timestamp: timestamp, payload: AMF0.encode(values)
            ),
            chunkStreamID: ChunkStream.command, chunkSize: outgoingChunkSize
        )
    }

    private func command(_ values: [AMF0Value], onStream stream: UInt32 = 0) -> Data {
        RTMPChunkWriter.chunks(
            for: RTMPMessage(typeID: RTMPMessage.Kind.command, streamID: stream, payload: AMF0.encode(values)),
            chunkStreamID: ChunkStream.command, chunkSize: outgoingChunkSize
        )
    }

    /// The larger chunk size, then the request to connect to the application.
    private func connectRequest() -> Data {
        let chunkSize = RTMPMessage(
            typeID: RTMPMessage.Kind.setChunkSize,
            payload: ByteOrder.bigEndian(UInt64(outgoingChunkSize), bytes: Self.chunkSizeBytes)
        )
        return RTMPChunkWriter.chunks(
            for: chunkSize, chunkStreamID: ChunkStream.control, chunkSize: RTMPChunkFormat.defaultChunkSize
        ) + command([
            .string(Command.connect), .number(Transaction.connect),
            .object([
                AMF0Property(Field.application, .string(target.application)),
                AMF0Property(Field.type, .string(Field.privacyKind)),
                AMF0Property(Field.flashVersion, .string(Command.encoderName)),
                AMF0Property(Field.serverURL, .string(target.serverAddress)),
            ]),
        ])
    }

    private mutating func answer(to values: [AMF0Value]) -> Data {
        guard case .string(let name)? = values.first else { return Data() }
        var transaction = 0.0
        if values.count > 1, case .number(let number) = values[1] { transaction = number }
        switch (name, transaction) {
        case (Command.result, Transaction.connect):
            return command([.string(Command.releaseStream), .number(Transaction.releaseStream), .null, .string(target.streamKey)])
                + command([.string(Command.prepareToPublish), .number(Transaction.prepareToPublish), .null, .string(target.streamKey)])
                + command([.string(Command.createStream), .number(Transaction.createStream), .null])
        case (Command.result, Transaction.createStream):
            if case .number(let id)? = values.last { streamID = UInt32(id) }
            return command([
                .string(Command.publish), .number(Transaction.publish), .null,
                .string(target.streamKey), .string(Command.live),
            ], onStream: streamID)
        case (Command.status, _):
            return status(values.last)
        case (Command.error, _):
            state = .failed(Self.refused)
            return Data()
        default:
            return Data()
        }
    }

    /// The server's word on the request to publish: it has started, or it failed.
    private mutating func status(_ info: AMF0Value?) -> Data {
        guard case .object(let properties)? = info else { return Data() }
        func text(_ name: String) -> String? {
            if case .string(let value)? = properties.first(where: { $0.name == name })?.value { return value }
            return nil
        }
        let code = text(Command.statusCode)
        if code == Command.publishStarted {
            state = .live
            return metadata()
        }
        if text(Command.statusLevel) == Command.errorLevel {
            state = .failed(code ?? Self.refused)
        }
        return Data()
    }

    /// What the picture is like, sent once the stream is live.
    private func metadata() -> Data {
        var properties = [
            AMF0Property(Field.width, .number(Double(details.width))),
            AMF0Property(Field.height, .number(Double(details.height))),
            AMF0Property(Field.frameRate, .number(Double(details.framesPerSecond))),
            AMF0Property(Field.videoDataRate, .number(Double(details.bitsPerSecond) / Self.bitsPerKilobit)),
            AMF0Property(Field.videoCodecID, .number(Command.avcCodecID)),
        ]
        if let sound {
            properties += [
                AMF0Property(Field.audioCodecID, .number(Command.aacCodecID)),
                AMF0Property(Field.audioDataRate, .number(Double(sound.bitsPerSecond) / Self.bitsPerKilobit)),
                AMF0Property(Field.audioSampleRate, .number(Double(sound.sampleRate))),
                AMF0Property(Field.stereo, .boolean(sound.channels > Field.monoChannels)),
            ]
        }
        properties.append(AMF0Property(Field.encoder, .string(Command.encoderName)))
        let values: [AMF0Value] = [.string(Command.setDataFrame), .string(Command.metadata), .array(properties)]
        return RTMPChunkWriter.chunks(
            for: RTMPMessage(typeID: RTMPMessage.Kind.data, streamID: streamID, payload: AMF0.encode(values)),
            chunkStreamID: ChunkStream.command, chunkSize: outgoingChunkSize
        )
    }
}

/// Whether the picture is sent to an RTMP server, and which.
public struct RTMPSettings: Codable, Equatable, Sendable {
    public var isOn: Bool
    /// The server and application, such as `rtmp://example.com/live`.
    public var address: String
    /// The key that names the stream on the server. It is as good as a
    /// password for the channel it belongs to.
    public var streamKey: String
    /// Optional so settings saved before streams had options still load.
    public var streamOptions: StreamOptions?

    public init(isOn: Bool = false, address: String = "", streamKey: String = "", options: StreamOptions = .server) {
        self.isOn = isOn
        self.address = address
        self.streamKey = streamKey
        streamOptions = options
    }

    public var options: StreamOptions {
        get { streamOptions ?? .server }
        set { streamOptions = newValue }
    }
}
