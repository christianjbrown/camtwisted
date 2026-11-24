import Foundation

/// Another computer's screen, watched over VNC: where the computer is. Its
/// password is kept in the Mac's keychain, never here, so a setup that
/// includes it can be shared.
public struct VNCSettings: Codable, Equatable, Sendable {
    /// The port VNC servers listen on unless told otherwise.
    public static let defaultPort = 5900
    private static let portSeparator: Character = ":"
    private static let portRange = 1...65535

    /// The computer's name or address, with its port after a colon when
    /// that is not the usual one, as typed.
    public var address: String

    public init(address: String = "") {
        self.address = address
    }

    /// The computer's name or address alone. Empty until one is typed.
    public var host: String {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.lastIndex(of: Self.portSeparator), Int(trimmed[trimmed.index(after: separator)...]) != nil
        else { return trimmed }
        return String(trimmed[..<separator])
    }

    /// The port: the one typed after a colon when it is a real port, or the usual one.
    public var port: Int {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.lastIndex(of: Self.portSeparator),
              let typed = Int(trimmed[trimmed.index(after: separator)...]), Self.portRange.contains(typed)
        else { return Self.defaultPort }
        return typed
    }

    /// What the password is kept under: the computer and its port.
    public var account: String { "\(host)\(Self.portSeparator)\(port)" }
}
