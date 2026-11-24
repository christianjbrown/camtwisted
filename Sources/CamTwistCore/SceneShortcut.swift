import Foundation

/// The keys held down with a keyboard shortcut.
public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let control = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let shift = ShortcutModifiers(rawValue: 1 << 2)
    public static let command = ShortcutModifiers(rawValue: 1 << 3)

    /// The ones that make a key a shortcut rather than typing. Shift on its
    /// own only makes a capital letter.
    public static let commanding: ShortcutModifiers = [.control, .option, .command]

    /// Each one with the symbol a Mac menu shows for it, in the order menus show them.
    private static let symbols: [(modifier: ShortcutModifiers, symbol: String)] = [
        (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]

    /// The symbols for the keys held, as a Mac menu writes them.
    public var title: String {
        Self.symbols.filter { contains($0.modifier) }.map(\.symbol).joined()
    }
}

/// A keyboard shortcut that puts a scene on air from whichever app is in front.
public struct SceneShortcut: Codable, Hashable, Sendable {
    /// Where the key is on the keyboard, which stays the same whatever
    /// the keyboard's language.
    public let keyCode: Int
    /// What the key says on it, for showing the shortcut.
    public let key: String
    public let modifiers: ShortcutModifiers

    public init(keyCode: Int, key: String, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.key = key
        self.modifiers = modifiers
    }

    /// The shortcut as a Mac menu writes it, such as ⌃⌥1.
    public var title: String { modifiers.title + key }
}

/// Another scene that takes over by itself once this one has been on air
/// for a while.
public struct SceneHandover: Codable, Equatable, Sendable {
    /// How long a scene stays on air before handing over, when nobody says.
    public static let defaultSeconds = 30.0
    /// The shortest and longest a scene can stay on air before handing over.
    public static let secondsRange: ClosedRange<Double> = 1...3600

    public var sceneID: UUID
    public var seconds: Double

    public init(sceneID: UUID, seconds: Double = SceneHandover.defaultSeconds) {
        self.sceneID = sceneID
        self.seconds = seconds
    }
}
