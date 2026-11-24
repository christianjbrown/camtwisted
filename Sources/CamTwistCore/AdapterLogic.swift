import CoreGraphics
import Foundation

// The decisions the app's thin system adapters used to make themselves.
// The adapters call these and only carry out what they say.

/// Names snapshot files after the moment they were taken.
public enum SnapshotName {
    private static let prefix = "CamTwisted "
    public static let fileExtension = "png"
    /// The year first, and no colons, which Finder does not allow in a name.
    private static let pattern = "yyyy-MM-dd HH.mm.ss"
    private static let fixedLocale = "en_US_POSIX"

    /// The name without its extension.
    public static func baseName(at date: Date, in timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: fixedLocale)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return prefix + formatter.string(from: date)
    }
}

/// Reads a MIDI packet.
public enum MIDINoteMessage {
    private static let statusMask: UInt8 = 0xF0
    private static let noteOn: UInt8 = 0x90
    /// Bytes in a note message: status, note, velocity.
    private static let length = 3
    private static let statusIndex = 0
    private static let noteIndex = 1
    private static let velocityIndex = 2
    /// A note-on with no velocity is how some keyboards say note-off.
    private static let silentVelocity: UInt8 = 0

    /// The note a packet presses, or nil when it is anything else: too
    /// short, not a note-on, or a note-on that is really a note-off.
    public static func notePressed(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= length else { return nil }
        let isNoteOn = bytes[statusIndex] & statusMask == noteOn
        guard isNoteOn, bytes[velocityIndex] > silentVelocity else { return nil }
        return Int(bytes[noteIndex])
    }
}

/// What to do after reading from a Cast device's connection.
public enum CastReadOutcome: Equatable {
    /// The device said no: there is nothing more to say to it.
    case refused
    /// The connection ended or went wrong.
    case lost
    case keepReading

    public static func after(sessionFailed: Bool, connectionEnded: Bool, readerBroken: Bool) -> CastReadOutcome {
        if sessionFailed { return .refused }
        return connectionEnded || readerBroken ? .lost : .keepReading
    }
}

/// Lists Cast devices by name.
public enum CastDeviceOrder {
    public static func sorted<Device>(_ devices: [Device], name: (Device) -> String) -> [Device] {
        devices.sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
    }
}

/// What a finished attempt to install or remove the virtual microphone says.
public enum MicrophoneInstallOutcome {
    public static let cancelled = "It was not allowed, or was cancelled."
    private static let success: Int32 = 0

    /// Nil when the script succeeded.
    public static func problem(exitStatus: Int32) -> String? {
        exitStatus == success ? nil : cancelled
    }
}

/// Which display a screen is, from the record the system keeps of it.
public enum DisplayIdentity {
    public static let screenNumberKey = "NSScreenNumber"

    /// The display's number, when the record has one.
    public static func displayID(inDescription description: [String: Any]) -> UInt32? {
        (description[screenNumberKey] as? NSNumber)?.uint32Value
    }
}

/// Keys that close the full screen output.
public enum FullScreenKeys {
    private static let escapeKeyCode: UInt16 = 53

    public static func closes(keyCode: UInt16) -> Bool { keyCode == escapeKeyCode }
}

/// How the AirPlay player behaves.
public enum AirPlayPolicy {
    private static let audible: Float = 1
    private static let silent: Float = 0

    /// The address to play: only while the output is on.
    public static func wantedAddress(isOn: Bool, address: String?) -> String? {
        isOn ? address : nil
    }

    /// The stream plays unseen and silent until a device has it, or it
    /// would be heard out of this Mac as well.
    public static func volume(isOnDevice: Bool) -> Float { isOnDevice ? audible : silent }
}

/// Which passwords the keychain keeps.
public enum KeychainRules {
    /// An empty password is no password: nothing is kept for it.
    public static func keeps(_ password: String) -> Bool { !password.isEmpty }
}

/// Shrinks a picture to the size a tile needs.
public enum ThumbnailScale {
    /// How wide a tile's picture is kept, in pixels.
    public static let width: CGFloat = 480

    public static func factor(forWidth pictureWidth: CGFloat) -> CGFloat { width / pictureWidth }
}
