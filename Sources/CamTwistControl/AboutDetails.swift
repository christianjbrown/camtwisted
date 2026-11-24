import Foundation

/// What the About window says about the app, read from the app's own
/// information so a change of maker, version, wording or address needs no
/// new code.
public struct AboutDetails: Equatable {
    /// The keys the details are filed under in the app's information.
    public enum Key {
        public static let name = "CFBundleName"
        public static let version = "CFBundleShortVersionString"
        public static let build = "CFBundleVersion"
        public static let copyright = "NSHumanReadableCopyright"
        public static let maker = "AboutMaker"
        public static let supportAddress = "AboutSupportURL"
        public static let inspiration = "AboutInspiration"
    }

    /// How the version and its build number are written out.
    private enum Wording {
        static let version = "Version"
        static let buildOpening = "("
        static let buildClosing = ")"
        static let separator = " "
    }

    public let name: String
    /// The version with its build number, or nothing when neither is known.
    public let versionLine: String
    public let copyright: String
    /// Who made the app, or nothing when it does not say.
    public let maker: String
    /// Where to go for help.
    public let supportAddress: URL?
    /// What the app was inspired by, and that it stands on its own, a line at a time.
    public let inspiration: [String]

    public init(information: [String: Any]) {
        func text(_ key: String) -> String { information[key] as? String ?? "" }
        func lines(_ key: String) -> [String] { information[key] as? [String] ?? [] }
        func address(_ key: String) -> URL? { URL(string: text(key)) }
        name = text(Key.name)
        let version = text(Key.version), build = text(Key.build)
        let numbers = [version, build.isEmpty ? "" : Wording.buildOpening + build + Wording.buildClosing]
            .filter { !$0.isEmpty }
        versionLine = numbers.isEmpty ? "" : ([Wording.version] + numbers).joined(separator: Wording.separator)
        copyright = text(Key.copyright)
        maker = text(Key.maker)
        supportAddress = address(Key.supportAddress)
        inspiration = lines(Key.inspiration)
    }
}
