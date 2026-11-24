import Foundation

/// One message to or from a Cast device, such as a Chromecast: who it is
/// from and for, which conversation it belongs to, and its text, which is
/// JSON. On the wire it is a small protocol buffer behind its own length.
public struct CastMessage: Equatable, Sendable {
    public var source: String
    public var destination: String
    public var namespace: String
    public var payload: String

    public init(source: String, destination: String, namespace: String, payload: String) {
        self.source = source
        self.destination = destination
        self.namespace = namespace
        self.payload = payload
    }

    /// The fields of the protocol buffer, by their numbers.
    private enum Field {
        static let protocolVersion: UInt64 = 1
        static let source: UInt64 = 2
        static let destination: UInt64 = 3
        static let namespace: UInt64 = 4
        static let payloadType: UInt64 = 5
        static let payload: UInt64 = 6
    }

    /// How a field's value is laid out.
    private enum Wire {
        static let number: UInt64 = 0
        static let bytes: UInt64 = 2
        /// How many bits of a field's tag say which layout it has.
        static let typeBits: UInt64 = 3
        static let typeMask: UInt64 = 0b111
    }

    /// The first version of the protocol, and a payload that is text.
    private static let version: UInt64 = 0
    private static let textPayload: UInt64 = 0
    /// Bytes in the length that goes in front of every message.
    static let lengthSize = 4
    private static let bitsPerByte = 8

    /// The message as it is sent: its length, then its fields.
    public func framed() -> Data {
        var body = Data()
        body.append(Self.number(Self.version, field: Field.protocolVersion))
        body.append(Self.text(source, field: Field.source))
        body.append(Self.text(destination, field: Field.destination))
        body.append(Self.text(namespace, field: Field.namespace))
        body.append(Self.number(Self.textPayload, field: Field.payloadType))
        body.append(Self.text(payload, field: Field.payload))
        var framed = Data()
        for shift in (0..<Self.lengthSize).reversed() {
            framed.append(UInt8((body.count >> (shift * Self.bitsPerByte)) & Int(UInt8.max)))
        }
        return framed + body
    }

    /// Reads a message's fields, without the length in front. Nil when
    /// they are not laid out as a message's are.
    public init?(body: Data) {
        var texts: [UInt64: String] = [:]
        var reader = VarintReader(bytes: [UInt8](body))
        while !reader.isAtEnd {
            guard let tag = reader.next() else { return nil }
            let field = tag >> Wire.typeBits
            switch tag & Wire.typeMask {
            case Wire.number:
                guard reader.next() != nil else { return nil }
            case Wire.bytes:
                guard let length = reader.next(), let bytes = reader.take(Int(clamping: length)) else { return nil }
                texts[field] = String(decoding: bytes, as: UTF8.self)
            default:
                return nil
            }
        }
        self.init(
            source: texts[Field.source, default: ""], destination: texts[Field.destination, default: ""],
            namespace: texts[Field.namespace, default: ""], payload: texts[Field.payload, default: ""]
        )
    }

    private static func tag(_ field: UInt64, _ wire: UInt64) -> Data {
        varint(field << Wire.typeBits | wire)
    }

    private static func number(_ value: UInt64, field: UInt64) -> Data {
        tag(field, Wire.number) + varint(value)
    }

    private static func text(_ value: String, field: UInt64) -> Data {
        let bytes = Data(value.utf8)
        return tag(field, Wire.bytes) + varint(UInt64(bytes.count)) + bytes
    }

    /// A whole number in as few bytes as it needs: seven bits to a byte,
    /// with the top bit set on every byte but the last.
    static func varint(_ value: UInt64) -> Data {
        var remaining = value
        var bytes = Data()
        repeat {
            let low = UInt8(remaining & VarintReader.valueMask)
            remaining >>= VarintReader.valueBits
            bytes.append(remaining == 0 ? low : low | VarintReader.moreFlag)
        } while remaining != 0
        return bytes
    }
}

/// Reads numbers and runs of bytes out of a protocol buffer.
struct VarintReader {
    static let valueBits: UInt64 = 7
    static let valueMask: UInt64 = 0x7F
    static let moreFlag: UInt8 = 0x80
    /// The most bytes a number can take.
    private static let longest = 10

    private let bytes: [UInt8]
    private var position = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { position >= bytes.count }

    /// The next number, or nil when the bytes run out before it ends.
    mutating func next() -> UInt64? {
        var value: UInt64 = 0
        for index in 0..<Self.longest {
            guard position < bytes.count else { return nil }
            let byte = bytes[position]
            position += 1
            value |= (UInt64(byte) & Self.valueMask) << (UInt64(index) * Self.valueBits)
            if byte & Self.moreFlag == 0 {
                return value
            }
        }
        return nil
    }

    /// The next so many bytes, or nil when there are not that many left.
    mutating func take(_ count: Int) -> [UInt8]? {
        guard count <= bytes.count - position else { return nil }
        defer { position += count }
        return Array(bytes[position..<position + count])
    }
}

/// Gathers bytes as they arrive and hands back each whole message.
public struct CastFrameReader: Sendable {
    /// Longer than any message a device sends. One claiming more is not
    /// a message at all.
    private static let longestMessage = 1 << 20
    private static let bitsPerByte = 8

    private var buffer = Data()
    /// Whether what arrived stopped making sense, after which nothing more is read.
    public private(set) var isBroken = false

    public init() {}

    public mutating func append(_ data: Data) -> [CastMessage] {
        guard !isBroken else { return [] }
        buffer.append(data)
        var messages: [CastMessage] = []
        while buffer.count >= CastMessage.lengthSize {
            let length = buffer.prefix(CastMessage.lengthSize).reduce(0) { $0 << Self.bitsPerByte | Int($1) }
            guard length <= Self.longestMessage else {
                isBroken = true
                return messages
            }
            guard buffer.count >= CastMessage.lengthSize + length else { break }
            let body = buffer.dropFirst(CastMessage.lengthSize).prefix(length)
            buffer = Data(buffer.dropFirst(CastMessage.lengthSize + length))
            guard let message = CastMessage(body: Data(body)) else {
                isBroken = true
                return messages
            }
            messages.append(message)
        }
        return messages
    }
}
