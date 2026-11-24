import Foundation

/// How a recording is getting on.
public enum RecordingStatus: Equatable, Sendable {
    case off
    /// Being written to a file of this name.
    case recording(String)
    case failed(String)
}

/// Names recordings after when they began, so they sort in order and
/// never collide.
public enum RecordingName {
    private static let prefix = "CamTwisted "
    private static let extensionSeparator = "."
    /// The year first, and no colons, which Finder does not allow in a name.
    private static let pattern = "yyyy-MM-dd 'at' HH.mm.ss"
    private static let fixedLocale = "en_US_POSIX"

    /// - Parameter container: the kind of file, which gives the name its extension.
    public static func fileName(
        startingAt date: Date, as container: RecordingContainer, in timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: fixedLocale)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return prefix + formatter.string(from: date) + extensionSeparator + container.fileExtension
    }
}
