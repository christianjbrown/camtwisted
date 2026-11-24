import Foundation

/// Where an effect follows somebody else's work, so they can be thanked
/// beside it.
public enum EffectCredits {
    /// Credits by effect name.
    private static let named: [String: String] = [
        "Flame": "After xflame from XScreenSaver",
        "Matrix": "After MatrixTV from EffecTV by Monji Kimura",
    ]

    public static func credit(forEffectNamed name: String) -> String? {
        named[name]
    }
}
