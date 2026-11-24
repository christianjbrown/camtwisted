import Foundation

/// A value in AMF0, the format RTMP writes its commands in.
public indirect enum AMF0Value: Equatable, Sendable {
    case number(Double)
    case boolean(Bool)
    case string(String)
    case null
    /// Named values in order.
    case object([AMF0Property])
    /// Named values in order, written with their count in front: how
    /// stream details are sent.
    case array([AMF0Property])
}

public struct AMF0Property: Equatable, Sendable {
    public let name: String
    public let value: AMF0Value

    public init(_ name: String, _ value: AMF0Value) {
        self.name = name
        self.value = value
    }
}

/// Writes and reads AMF0.
public enum AMF0 {
    private enum Marker {
        static let number: UInt8 = 0x00
        static let boolean: UInt8 = 0x01
        static let string: UInt8 = 0x02
        static let object: UInt8 = 0x03
        static let null: UInt8 = 0x05
        static let undefined: UInt8 = 0x06
        static let array: UInt8 = 0x08
        static let objectEnd: UInt8 = 0x09
    }

    private static let numberLength = 8
    private static let shortLength = 2
    private static let countLength = 4

    public static func encode(_ values: [AMF0Value]) -> Data {
        values.reduce(into: Data()) { $0.append(encode($1)) }
    }

    public static func encode(_ value: AMF0Value) -> Data {
        switch value {
        case .number(let number):
            return Data([Marker.number]) + ByteOrder.bigEndian(number.bitPattern, bytes: numberLength)
        case .boolean(let flag):
            return Data([Marker.boolean, flag ? 1 : 0])
        case .string(let text):
            return Data([Marker.string]) + shortString(text)
        case .null:
            return Data([Marker.null])
        case .object(let properties):
            return Data([Marker.object]) + encode(properties)
        case .array(let properties):
            return Data([Marker.array]) + ByteOrder.bigEndian(UInt64(properties.count), bytes: countLength)
                + encode(properties)
        }
    }

    /// Every value that can be read from the front of some data. Reading
    /// stops, keeping what it has, at anything cut short or unknown.
    public static func decode(_ data: Data) -> [AMF0Value] {
        var reader = ByteReader(data)
        var values: [AMF0Value] = []
        while !reader.isAtEnd, let value = value(from: &reader) {
            values.append(value)
        }
        return values
    }

    private static func encode(_ properties: [AMF0Property]) -> Data {
        properties.reduce(into: Data()) { $0.append(shortString($1.name) + encode($1.value)) }
            + Data([0, 0, Marker.objectEnd])
    }

    private static func shortString(_ text: String) -> Data {
        let bytes = Data(text.utf8)
        return ByteOrder.bigEndian(UInt64(bytes.count), bytes: shortLength) + bytes
    }

    private static func value(from reader: inout ByteReader) -> AMF0Value? {
        guard let marker = reader.byte() else { return nil }
        switch marker {
        case Marker.number:
            return reader.integer(bytes: numberLength).map { .number(Double(bitPattern: $0)) }
        case Marker.boolean:
            return reader.byte().map { .boolean($0 != 0) }
        case Marker.string:
            return string(from: &reader).map { .string($0) }
        case Marker.null, Marker.undefined:
            return .null
        case Marker.object:
            return properties(from: &reader).map { .object($0) }
        case Marker.array:
            guard reader.integer(bytes: countLength) != nil else { return nil }
            return properties(from: &reader).map { .array($0) }
        default:
            return nil
        }
    }

    private static func string(from reader: inout ByteReader) -> String? {
        guard let length = reader.integer(bytes: shortLength), let bytes = reader.bytes(Int(length)) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Named values up to the mark that ends an object.
    private static func properties(from reader: inout ByteReader) -> [AMF0Property]? {
        var properties: [AMF0Property] = []
        while let name = string(from: &reader) {
            if name.isEmpty {
                return reader.byte() == Marker.objectEnd ? properties : nil
            }
            guard let value = value(from: &reader) else { return nil }
            properties.append(AMF0Property(name, value))
        }
        return nil
    }
}

/// Whole numbers as bytes, in either order.
enum ByteOrder {
    private static let bitsPerByte = 8

    /// The low `bytes` bytes of a number, most significant first.
    static func bigEndian(_ value: UInt64, bytes: Int) -> Data {
        Data((0..<bytes).reversed().map { UInt8(truncatingIfNeeded: value >> UInt64($0 * bitsPerByte)) })
    }

    /// The low `bytes` bytes of a number, least significant first.
    static func littleEndian(_ value: UInt64, bytes: Int) -> Data {
        Data((0..<bytes).map { UInt8(truncatingIfNeeded: value >> UInt64($0 * bitsPerByte)) })
    }
}

/// Reads bytes off the front of some data, refusing to read past the end.
struct ByteReader {
    private static let bitsPerByte = 8

    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        offset = data.startIndex
    }

    var isAtEnd: Bool { offset >= data.endIndex }
    var remaining: Int { data.endIndex - offset }

    mutating func byte() -> UInt8? {
        guard remaining >= 1 else { return nil }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func bytes(_ count: Int) -> Data? {
        guard count >= 0, remaining >= count else { return nil }
        defer { offset += count }
        return data.subdata(in: offset..<offset + count)
    }

    /// A whole number of some bytes, most significant first.
    mutating func integer(bytes count: Int) -> UInt64? {
        bytes(count).map { $0.reduce(UInt64(0)) { $0 << UInt64(Self.bitsPerByte) | UInt64($1) } }
    }
}
