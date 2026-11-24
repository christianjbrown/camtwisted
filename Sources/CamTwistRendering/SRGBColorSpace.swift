import CoreGraphics

/// The colour space every picture here is drawn and read in.
enum SRGBColorSpace {
    static let shared = make(named: CGColorSpace.sRGB)

    /// The named colour space, or plain device RGB when the system does not
    /// know the name, so drawing never has to give up.
    static func make(named name: CFString) -> CGColorSpace {
        CGColorSpace(name: name) ?? CGColorSpaceCreateDeviceRGB()
    }
}
