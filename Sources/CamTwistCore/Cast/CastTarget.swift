import Foundation

/// What should be playing where on a Cast device.
public struct CastTarget: Equatable, Sendable {
    public let address: String
    public let device: String

    public init(address: String, device: String) {
        self.address = address
        self.device = device
    }

    /// The target the settings ask for: nothing unless casting is on and
    /// both a stream address and a device are named.
    public static func wanted(isOn: Bool, address: String?, deviceName: String?) -> CastTarget? {
        guard isOn, let address, let deviceName else { return nil }
        return CastTarget(address: address, device: deviceName)
    }
}

/// Leaves a failure alone for a while before trying again.
public enum CastRetry {
    /// Whether a connection may be tried: it has not failed lately, or it
    /// failed long enough ago.
    public static func mayTry(failedAt: Date?, now: Date, delay: TimeInterval) -> Bool {
        guard let failedAt else { return true }
        return now.timeIntervalSince(failedAt) >= delay
    }
}
