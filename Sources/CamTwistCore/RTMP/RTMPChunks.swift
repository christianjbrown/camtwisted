import Foundation

/// One RTMP message: a command, a setting, or a piece of video.
public struct RTMPMessage: Equatable, Sendable {
    public enum Kind {
        public static let setChunkSize: UInt8 = 1
        public static let audio: UInt8 = 8
        public static let video: UInt8 = 9
        public static let data: UInt8 = 18
        public static let command: UInt8 = 20
    }

    public let typeID: UInt8
    /// The stream the message belongs to; 0 is the connection itself.
    public let streamID: UInt32
    /// Milliseconds since the stream began.
    public let timestamp: UInt32
    public let payload: Data

    public init(typeID: UInt8, streamID: UInt32 = 0, timestamp: UInt32 = 0, payload: Data) {
        self.typeID = typeID
        self.streamID = streamID
        self.timestamp = timestamp
        self.payload = payload
    }
}

/// The sizes RTMP's chunk headers are built from.
enum RTMPChunkFormat {
    /// A new chunk size is assumed until either side says otherwise.
    static let defaultChunkSize = 128
    /// A timestamp this large or larger is written after the header instead.
    static let extendedTimestampMark: UInt32 = 0xFF_FFFF
    static let timestampLength = 3
    static let lengthLength = 3
    static let streamIDLength = 4
    static let extendedTimestampLength = 4
    static let formatShift: UInt8 = 6
    static let chunkStreamMask: UInt8 = 0x3F
    /// The chunk header that repeats everything from the chunk before.
    static let continuation: UInt8 = 3
    /// Chunk stream ids that mean "the real id follows", in one or two bytes.
    static let oneByteID: UInt8 = 0
    static let twoByteID: UInt8 = 1
    static let extendedIDBase = 64
    static let twoByteIDScale = 256
    static let bitsPerByte = 8
    /// Headers that start a chunk stream, or carry its message length and type.
    static let fullHeader: Int = 0
    static let sameStreamHeader: Int = 1
}

/// Cuts messages into the chunks RTMP sends them as.
public enum RTMPChunkWriter {
    /// A message as chunks: a full header, then the payload in pieces of
    /// `chunkSize` with a one-byte header before each further piece.
    public static func chunks(for message: RTMPMessage, chunkStreamID: UInt8, chunkSize: Int) -> Data {
        let isExtended = message.timestamp >= RTMPChunkFormat.extendedTimestampMark
        let timestampField = isExtended ? RTMPChunkFormat.extendedTimestampMark : message.timestamp
        let extended = isExtended
            ? ByteOrder.bigEndian(UInt64(message.timestamp), bytes: RTMPChunkFormat.extendedTimestampLength)
            : Data()
        var output = Data([chunkStreamID & RTMPChunkFormat.chunkStreamMask])
        output += ByteOrder.bigEndian(UInt64(timestampField), bytes: RTMPChunkFormat.timestampLength)
        output += ByteOrder.bigEndian(UInt64(message.payload.count), bytes: RTMPChunkFormat.lengthLength)
        output.append(message.typeID)
        output += ByteOrder.littleEndian(UInt64(message.streamID), bytes: RTMPChunkFormat.streamIDLength)
        output += extended

        let size = max(chunkSize, 1)
        var offset = message.payload.startIndex
        while offset < message.payload.endIndex {
            let end = min(offset + size, message.payload.endIndex)
            if offset > message.payload.startIndex {
                output.append(
                    RTMPChunkFormat.continuation << RTMPChunkFormat.formatShift
                        | chunkStreamID & RTMPChunkFormat.chunkStreamMask
                )
                output += extended
            }
            output += message.payload[offset..<end]
            offset = end
        }
        return output
    }
}

/// Puts the chunks a server sends back together into messages. Bytes are
/// handed over as they arrive, in whatever pieces the network delivers.
public struct RTMPChunkReader {
    /// What is known about a chunk stream from its earlier chunks.
    private struct Stream {
        var timestamp: UInt32 = 0
        var delta: UInt32 = 0
        var length = 0
        var typeID: UInt8 = 0
        var streamID: UInt32 = 0
        var hasExtendedTimestamp = false
        var payload = Data()
    }

    /// Where each field sits in a header, after the chunk stream id.
    private enum Field {
        static let timestamp = 0
        static let length = 3
        static let typeID = 6
        static let streamID = 7
    }

    /// Header lengths after the chunk stream id, by header format.
    private static let headerLengths = [11, 7, 3, 0]
    private static let chunkSizeLength = 4
    /// The top bit of a chunk size is reserved and always clear.
    private static let chunkSizeMask: UInt64 = 0x7FFF_FFFF

    private var buffer = Data()
    private var streams: [Int: Stream] = [:]
    private var chunkSize = RTMPChunkFormat.defaultChunkSize

    public init() {}

    /// Takes more bytes and hands back every message they complete. A
    /// message that changes the chunk size is obeyed as well as handed back.
    public mutating func append(_ data: Data) -> [RTMPMessage] {
        buffer.append(data)
        var messages: [RTMPMessage] = []
        while let used = readChunk(into: &messages) {
            buffer.removeFirst(used)
        }
        return messages
    }

    /// Reads one chunk from the front of the buffer, when all of it has
    /// arrived, and says how many bytes it took.
    private mutating func readChunk(into messages: inout [RTMPMessage]) -> Int? {
        var reader = ByteReader(buffer)
        guard let first = reader.byte() else { return nil }
        let format = Int(first >> RTMPChunkFormat.formatShift)
        var id = Int(first & RTMPChunkFormat.chunkStreamMask)
        if id == Int(RTMPChunkFormat.oneByteID) {
            guard let next = reader.byte() else { return nil }
            id = RTMPChunkFormat.extendedIDBase + Int(next)
        } else if id == Int(RTMPChunkFormat.twoByteID) {
            guard let low = reader.byte(), let high = reader.byte() else { return nil }
            id = RTMPChunkFormat.extendedIDBase + Int(low) + Int(high) * RTMPChunkFormat.twoByteIDScale
        }
        var stream = streams[id, default: Stream()]
        guard let header = reader.bytes(Self.headerLengths[format]) else { return nil }
        let fields = Array(header)
        /// A whole number from the header's bytes, most significant first.
        func number(at start: Int, bytes count: Int) -> UInt64 {
            fields[start..<start + count].reduce(UInt64(0)) { $0 << RTMPChunkFormat.bitsPerByte | UInt64($1) }
        }

        var timeField: UInt32?
        if format < Int(RTMPChunkFormat.continuation) {
            timeField = UInt32(number(at: Field.timestamp, bytes: RTMPChunkFormat.timestampLength))
        }
        if format <= RTMPChunkFormat.sameStreamHeader {
            stream.length = Int(number(at: Field.length, bytes: RTMPChunkFormat.lengthLength))
            stream.typeID = fields[Field.typeID]
        }
        if format == RTMPChunkFormat.fullHeader {
            // The message stream is the one field written least significant byte first.
            stream.streamID = fields[Field.streamID..<Field.streamID + RTMPChunkFormat.streamIDLength]
                .reversed().reduce(UInt32(0)) { $0 << RTMPChunkFormat.bitsPerByte | UInt32($1) }
        }
        if let field = timeField {
            stream.hasExtendedTimestamp = field == RTMPChunkFormat.extendedTimestampMark
        }
        var time = timeField
        if stream.hasExtendedTimestamp {
            guard let extended = reader.integer(bytes: RTMPChunkFormat.extendedTimestampLength) else { return nil }
            // A continuation repeats the extended timestamp without meaning a new one.
            if timeField != nil { time = UInt32(truncatingIfNeeded: extended) }
        }
        // A chunk that starts a message moves its clock: a full header sets
        // it, a shorter one adds to it, and a bare one adds the same again.
        if stream.payload.isEmpty {
            if format == RTMPChunkFormat.fullHeader, let time {
                stream.timestamp = time
                stream.delta = 0
            } else {
                stream.delta = time ?? stream.delta
                stream.timestamp &+= stream.delta
            }
        }

        let wanted = min(chunkSize, stream.length - stream.payload.count)
        guard let piece = reader.bytes(wanted) else { return nil }
        stream.payload.append(piece)
        if stream.payload.count >= stream.length {
            let message = RTMPMessage(
                typeID: stream.typeID, streamID: stream.streamID, timestamp: stream.timestamp, payload: stream.payload
            )
            stream.payload = Data()
            if message.typeID == RTMPMessage.Kind.setChunkSize {
                var size = ByteReader(message.payload)
                if let asked = size.integer(bytes: Self.chunkSizeLength), asked & Self.chunkSizeMask > 0 {
                    chunkSize = Int(asked & Self.chunkSizeMask)
                }
            }
            messages.append(message)
        }
        streams[id] = stream
        return buffer.count - reader.remaining
    }
}
