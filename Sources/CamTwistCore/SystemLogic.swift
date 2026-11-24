import CoreGraphics
import Foundation

/// Decides which of the Mac's network interfaces other devices can reach it by.
public enum ReachableInterface {
    /// Up, on an IPv4 network, and not this Mac talking to itself.
    public static func qualifies(flags: Int32, family: UInt8) -> Bool {
        flags & IFF_UP != 0 && flags & IFF_LOOPBACK == 0 && family == UInt8(AF_INET)
    }
}

/// Fits a window's wanted size to the room a screen has.
public enum WindowFit {
    /// No bigger than the room, in either direction. With no screen to ask,
    /// the wanted size stands.
    public static func size(wanted: CGSize, room: CGSize?) -> CGSize {
        guard let room else { return wanted }
        return CGSize(width: min(wanted.width, room.width), height: min(wanted.height, room.height))
    }
}
