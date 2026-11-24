import CommonCrypto
import Foundation

/// The screen of the computer being watched, as it stands: four bytes a
/// pixel, blue, green, red, then one that is always full.
public struct RFBFramebuffer: Equatable, Sendable {
    public static let bytesPerPixel = 4
    private static let opaque: UInt8 = 255

    public private(set) var width: Int
    public private(set) var height: Int
    public private(set) var pixels: [UInt8]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * Self.bytesPerPixel)
    }

    /// Whether a rectangle lies wholly on the screen.
    func contains(x: Int, y: Int, width: Int, height: Int) -> Bool {
        x >= 0 && y >= 0 && width >= 0 && height >= 0 && x + width <= self.width && y + height <= self.height
    }

    /// Puts a rectangle of pixels on the screen. One that does not fit is left out.
    mutating func put(_ data: Data, x: Int, y: Int, width: Int, height: Int) {
        guard contains(x: x, y: y, width: width, height: height), data.count == width * height * Self.bytesPerPixel
        else { return }
        let source = [UInt8](data)
        let rowBytes = width * Self.bytesPerPixel
        for row in 0..<height {
            let from = row * rowBytes
            let to = ((y + row) * self.width + x) * Self.bytesPerPixel
            pixels.replaceSubrange(to..<to + rowBytes, with: source[from..<from + rowBytes])
            // The fourth byte of each pixel is spare on the wire: here it is the alpha.
            for column in 0..<width {
                pixels[to + column * Self.bytesPerPixel + ImageAnalysis.alphaOffset] = Self.opaque
            }
        }
    }

    /// Copies one part of the screen onto another, as when a window is dragged.
    mutating func copy(fromX: Int, fromY: Int, toX: Int, toY: Int, width: Int, height: Int) {
        guard contains(x: fromX, y: fromY, width: width, height: height),
              contains(x: toX, y: toY, width: width, height: height)
        else { return }
        let rowBytes = width * Self.bytesPerPixel
        var block = [UInt8]()
        block.reserveCapacity(rowBytes * height)
        for row in 0..<height {
            let from = ((fromY + row) * self.width + fromX) * Self.bytesPerPixel
            block.append(contentsOf: pixels[from..<from + rowBytes])
        }
        for row in 0..<height {
            let to = ((toY + row) * self.width + toX) * Self.bytesPerPixel
            pixels.replaceSubrange(to..<to + rowBytes, with: block[row * rowBytes..<(row + 1) * rowBytes])
        }
    }
}

/// The conversation with a VNC server (the RFB protocol) that gets its
/// screen: agree a version, prove the password, ask for the screen, then
/// keep taking the parts of it that change. Everything here is the words;
/// the connection that carries them is elsewhere.
public struct RFBSession: Sendable {
    public enum State: Equatable, Sendable {
        case connecting
        case running
        case failed(String)
    }

    private enum Phase: Equatable {
        case version
        case securityTypes
        case decidedSecurity
        case challenge
        case securityResult
        case failureReason
        case serverInit
        case running
        case ended
    }

    private enum Wire {
        static let versionLength = 12
        static let versionPrefix = "RFB "
        /// The newest version spoken, and the oldest, which works differently.
        static let newest = "RFB 003.008\n"
        static let oldest = "RFB 003.003\n"
        static let newestMinor = 8
        static let minorRange = 8..<11

        static let securityNone: UInt8 = 1
        static let securityPassword: UInt8 = 2
        static let challengeLength = 16
        static let sharedScreen: UInt8 = 1

        static let serverInitFixedLength = 24

        static let setPixelFormat: UInt8 = 0
        static let setEncodings: UInt8 = 2
        static let updateRequest: UInt8 = 3
        static let incremental: UInt8 = 1

        static let framebufferUpdate: UInt8 = 0
        static let colourMap: UInt8 = 1
        static let bell: UInt8 = 2
        static let cutText: UInt8 = 3

        static let updateHeaderLength = 4
        static let rectangleHeaderLength = 12
        static let copySourceLength = 4
        static let colourMapHeaderLength = 6
        static let colourMapEntryLength = 6
        static let cutTextHeaderLength = 8

        /// A message kind, or a count of security types, is one byte.
        static let byteLength = 1
        /// Width, height, counts and coordinates are two bytes wide.
        static let shortLength = 2
        /// A rectangle's encoding number is four bytes wide.
        static let encodingLength = 4
        /// Where each field sits within a server's greeting or a rectangle header.
        static let screenWidthOffset = 0
        static let screenHeightOffset = 2
        static let rectangleXOffset = 0
        static let rectangleYOffset = 2
        static let rectangleWidthOffset = 4
        static let rectangleHeightOffset = 6
        static let rectangleEncodingOffset = 8
        /// Where the source corner sits within a copy rectangle's body.
        static let copySourceXOffset = 0
        static let copySourceYOffset = 2

        static let rawEncoding: Int32 = 0
        static let copyEncoding: Int32 = 1
        /// Not a picture: the server saying its screen has changed size.
        static let sizeEncoding: Int32 = -223

        static let bitsPerPixel: UInt8 = 32
        static let depth: UInt8 = 24
        static let fullChannel: UInt16 = 255
        static let redShift: UInt8 = 16
        static let greenShift: UInt8 = 8
        static let blueShift: UInt8 = 0
    }

    private enum Problem {
        static let notVNC = "That is not a VNC server."
        static let noWayIn = "The server offers no way of signing in that this app knows."
        static let wrongPassword = "The password was not accepted."
        static let confused = "The server sent something that made no sense."
    }

    public private(set) var state = State.connecting
    /// The server's screen. It has no size until the server has said what its is.
    public private(set) var framebuffer = RFBFramebuffer(width: 0, height: 0)
    /// How many whole updates of the screen have been taken in.
    public private(set) var updateCount = 0

    private let password: String
    private var phase = Phase.version
    private var isOldest = false
    private var buffer: [UInt8] = []

    public init(password: String) {
        self.password = password
    }

    /// Takes in what the server sent and gives back what to send in return.
    public mutating func receive(_ data: Data) -> [Data] {
        buffer.append(contentsOf: data)
        var replies: [Data] = []
        // Each step takes what it needs from the front of the buffer, or
        // waits for more to arrive.
        while let reply = step() {
            replies.append(contentsOf: reply)
        }
        return replies
    }

    /// One step of the conversation: nil when more bytes are needed, or it is over.
    private mutating func step() -> [Data]? {
        switch phase {
        case .version: return agreeVersion()
        case .securityTypes: return chooseSecurity()
        case .decidedSecurity: return takeDecidedSecurity()
        case .challenge: return answerChallenge()
        case .securityResult: return takeSecurityResult()
        case .failureReason: return takeFailureReason()
        case .serverInit: return takeServerInit()
        case .running: return takeMessage()
        case .ended: return nil
        }
    }

    // MARK: Signing in

    private mutating func agreeVersion() -> [Data]? {
        guard let bytes = take(Wire.versionLength) else { return nil }
        let text = String(decoding: bytes, as: UTF8.self)
        guard text.hasPrefix(Wire.versionPrefix), let minor = Int(Array(text)[Wire.minorRange].map(String.init).joined())
        else { return fail(Problem.notVNC) }
        // Anything before the newest is spoken to as the oldest, which every server knows.
        isOldest = minor < Wire.newestMinor
        phase = isOldest ? .decidedSecurity : .securityTypes
        return [Data((isOldest ? Wire.oldest : Wire.newest).utf8)]
    }

    private mutating func chooseSecurity() -> [Data]? {
        guard let count = peek(Wire.byteLength)?.first else { return nil }
        guard count > 0 else {
            _ = take(Wire.byteLength)
            phase = .failureReason
            return []
        }
        guard let offered = take(1 + Int(count))?.dropFirst() else { return nil }
        // No password is used where none is asked for; otherwise the password.
        if offered.contains(Wire.securityNone) {
            phase = .securityResult
            return [Data([Wire.securityNone])]
        }
        if offered.contains(Wire.securityPassword) {
            phase = .challenge
            return [Data([Wire.securityPassword])]
        }
        return fail(Problem.noWayIn)
    }

    /// The oldest version does not offer a choice: the server says which.
    private mutating func takeDecidedSecurity() -> [Data]? {
        guard let kind = takeNumber(MemoryLayout<UInt32>.size) else { return nil }
        switch UInt8(clamping: kind) {
        case Wire.securityNone:
            phase = .serverInit
            return [Data([Wire.sharedScreen])]
        case Wire.securityPassword:
            phase = .challenge
            return []
        default:
            return fail(Problem.noWayIn)
        }
    }

    private mutating func answerChallenge() -> [Data]? {
        guard let challenge = take(Wire.challengeLength) else { return nil }
        phase = .securityResult
        return [RFBPassword.response(to: Data(challenge), password: password)]
    }

    private mutating func takeSecurityResult() -> [Data]? {
        guard let result = takeNumber(MemoryLayout<UInt32>.size) else { return nil }
        guard result == 0 else { return fail(Problem.wrongPassword) }
        phase = .serverInit
        return [Data([Wire.sharedScreen])]
    }

    /// The server's own words for why it will not go on.
    private mutating func takeFailureReason() -> [Data]? {
        guard let header = peek(MemoryLayout<UInt32>.size) else { return nil }
        let length = Self.number(header)
        guard let message = take(MemoryLayout<UInt32>.size + length)?.dropFirst(MemoryLayout<UInt32>.size) else { return nil }
        return fail(String(decoding: message, as: UTF8.self))
    }

    private mutating func takeServerInit() -> [Data]? {
        guard let fixed = peek(Wire.serverInitFixedLength) else { return nil }
        let nameLength = Self.number(fixed.suffix(MemoryLayout<UInt32>.size))
        guard let whole = take(Wire.serverInitFixedLength + nameLength) else { return nil }
        let width = Self.number(Self.field(whole, Wire.screenWidthOffset, Wire.shortLength))
        let height = Self.number(Self.field(whole, Wire.screenHeightOffset, Wire.shortLength))
        framebuffer = RFBFramebuffer(width: width, height: height)
        phase = .running
        state = .running
        return [Self.pixelFormatMessage, Self.encodingsMessage, updateRequest(incremental: false)]
    }

    // MARK: Taking the screen

    private mutating func takeMessage() -> [Data]? {
        guard let kind = peek(Wire.byteLength)?.first else { return nil }
        switch kind {
        case Wire.framebufferUpdate: return takeUpdate()
        case Wire.colourMap: return skipColourMap()
        case Wire.bell: return take(Wire.byteLength).map { _ in [] }
        case Wire.cutText: return skipCutText()
        default: return fail(Problem.confused)
        }
    }

    /// A whole update is taken in one go, once all of it has arrived.
    private mutating func takeUpdate() -> [Data]? {
        guard let header = peek(Wire.updateHeaderLength) else { return nil }
        let count = Self.number(header.suffix(Wire.shortLength))
        // Looked through where it lies: the pixels are only copied once they are all here.
        let bytes = buffer
        var cursor = Wire.updateHeaderLength
        var rectangles: [(x: Int, y: Int, width: Int, height: Int, encoding: Int32, body: Range<Int>)] = []
        for _ in 0..<count {
            guard bytes.count >= cursor + Wire.rectangleHeaderLength else { return nil }
            let x = Self.number(Self.field(bytes, cursor + Wire.rectangleXOffset, Wire.shortLength))
            let y = Self.number(Self.field(bytes, cursor + Wire.rectangleYOffset, Wire.shortLength))
            let width = Self.number(Self.field(bytes, cursor + Wire.rectangleWidthOffset, Wire.shortLength))
            let height = Self.number(Self.field(bytes, cursor + Wire.rectangleHeightOffset, Wire.shortLength))
            let encoding = Int32(bitPattern: UInt32(Self.number(Self.field(bytes, cursor + Wire.rectangleEncodingOffset, Wire.encodingLength))))
            cursor += Wire.rectangleHeaderLength
            let length: Int
            switch encoding {
            case Wire.rawEncoding: length = width * height * RFBFramebuffer.bytesPerPixel
            case Wire.copyEncoding: length = Wire.copySourceLength
            case Wire.sizeEncoding: length = 0
            default: return fail(Problem.confused)
            }
            guard bytes.count >= cursor + length else { return nil }
            rectangles.append((x, y, width, height, encoding, cursor..<cursor + length))
            cursor += length
        }
        _ = take(cursor)
        for rectangle in rectangles {
            switch rectangle.encoding {
            case Wire.rawEncoding:
                framebuffer.put(
                    Data(bytes[rectangle.body]), x: rectangle.x, y: rectangle.y,
                    width: rectangle.width, height: rectangle.height
                )
            case Wire.copyEncoding:
                let source = rectangle.body.lowerBound
                framebuffer.copy(
                    fromX: Self.number(Self.field(bytes, source + Wire.copySourceXOffset, Wire.shortLength)), fromY: Self.number(Self.field(bytes, source + Wire.copySourceYOffset, Wire.shortLength)),
                    toX: rectangle.x, toY: rectangle.y, width: rectangle.width, height: rectangle.height
                )
            default:
                // The screen has changed size: it starts again, blank.
                framebuffer = RFBFramebuffer(width: rectangle.width, height: rectangle.height)
            }
        }
        updateCount += 1
        return [updateRequest(incremental: true)]
    }

    private mutating func skipColourMap() -> [Data]? {
        guard let header = peek(Wire.colourMapHeaderLength) else { return nil }
        let entries = Self.number(header.suffix(Wire.shortLength))
        return take(Wire.colourMapHeaderLength + entries * Wire.colourMapEntryLength).map { _ in [] }
    }

    private mutating func skipCutText() -> [Data]? {
        guard let header = peek(Wire.cutTextHeaderLength) else { return nil }
        let length = Self.number(header.suffix(MemoryLayout<UInt32>.size))
        return take(Wire.cutTextHeaderLength + length).map { _ in [] }
    }

    // MARK: What is sent

    /// Asks for pixels as four bytes: blue, green, red and a spare.
    static var pixelFormatMessage: Data {
        var message = Data([Wire.setPixelFormat, 0, 0, 0, Wire.bitsPerPixel, Wire.depth, 0, 1])
        for channel in [Wire.fullChannel, Wire.fullChannel, Wire.fullChannel] {
            message.append(contentsOf: bytes(of: Int(channel), count: MemoryLayout<UInt16>.size))
        }
        message.append(contentsOf: [Wire.redShift, Wire.greenShift, Wire.blueShift, 0, 0, 0])
        return message
    }

    /// Says which ways of sending the screen are understood.
    static var encodingsMessage: Data {
        let encodings = [Wire.rawEncoding, Wire.copyEncoding, Wire.sizeEncoding]
        var message = Data([Wire.setEncodings, 0])
        message.append(contentsOf: bytes(of: encodings.count, count: MemoryLayout<UInt16>.size))
        for encoding in encodings {
            message.append(contentsOf: bytes(of: Int(UInt32(bitPattern: encoding)), count: MemoryLayout<UInt32>.size))
        }
        return message
    }

    /// Asks for the screen: all of it, or only what has changed since.
    private func updateRequest(incremental: Bool) -> Data {
        var message = Data([Wire.updateRequest, incremental ? Wire.incremental : 0, 0, 0, 0, 0])
        message.append(contentsOf: Self.bytes(of: framebuffer.width, count: MemoryLayout<UInt16>.size))
        message.append(contentsOf: Self.bytes(of: framebuffer.height, count: MemoryLayout<UInt16>.size))
        return message
    }

    // MARK: Bytes

    private mutating func fail(_ reason: String) -> [Data]? {
        state = .failed(reason)
        phase = .ended
        return nil
    }

    private func peek(_ count: Int) -> ArraySlice<UInt8>? {
        buffer.count >= count ? buffer.prefix(count) : nil
    }

    private mutating func take(_ count: Int) -> [UInt8]? {
        guard let front = peek(count).map(Array.init) else { return nil }
        buffer.removeFirst(count)
        return front
    }

    private mutating func takeNumber(_ count: Int) -> Int? {
        take(count).map(Self.number)
    }

    private static let bitsPerByte = 8

    /// The `length` bytes starting `offset` bytes in.
    static func field<Bytes: Collection>(_ bytes: Bytes, _ offset: Int, _ length: Int) -> Bytes.SubSequence
    where Bytes.Index == Int {
        bytes[offset..<offset + length]
    }

    /// A whole number sent most significant byte first.
    static func number<Bytes: Sequence>(_ bytes: Bytes) -> Int where Bytes.Element == UInt8 {
        bytes.reduce(0) { $0 << bitsPerByte | Int($1) }
    }

    static func bytes(of value: Int, count: Int) -> [UInt8] {
        (0..<count).reversed().map { UInt8((value >> ($0 * bitsPerByte)) & Int(UInt8.max)) }
    }
}

/// Proves a VNC password without sending it: the server's challenge is
/// encrypted with the password as the key.
public enum RFBPassword {
    private static let keyLength = 8
    private static let bitsPerByte = 8

    public static func response(to challenge: Data, password: String) -> Data {
        // The key is the password's first eight bytes, padded with noughts,
        // with the bits of each byte in reverse order: a quirk VNC has always had.
        var key = [UInt8](password.utf8.prefix(keyLength))
        key.append(contentsOf: [UInt8](repeating: 0, count: keyLength - key.count))
        key = key.map(reversed)
        let input = [UInt8](challenge)
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeDES)
        var written = 0
        CCCrypt(
            CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmDES), CCOptions(kCCOptionECBMode),
            key, key.count, nil, input, input.count, &output, output.count, &written
        )
        return Data(output.prefix(input.count))
    }

    private static func reversed(_ byte: UInt8) -> UInt8 {
        (0..<bitsPerByte).reduce(0) { $0 | ((byte >> $1) & 1) << (bitsPerByte - 1 - $1) }
    }
}
