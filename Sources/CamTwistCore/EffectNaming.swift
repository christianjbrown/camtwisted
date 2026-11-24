import Foundation

/// The names effects are shown under, in place of their files' own.
public enum EffectNaming {
    /// Names that no rule would guess well.
    private static let overrides: [String: String] = [
        "Mirror": "Mirror",
        "Sobel": "Sobel Edges",
        "LetterBox": "Letterbox",
        "PillarBox": "Pillarbox",
        "Mod": "Mod Wipe",
        "Dip": "Dip to Colour",
    ]
    private static let wordSeparator: Character = "_"

    public static func title(for name: String) -> String {
        overrides[name] ?? tidy(name)
    }

    /// Drops version numbers and splits run-together words.
    private static func tidy(_ name: String) -> String {
        var parts = name.split(separator: wordSeparator).map(String.init)
        if parts.count > 1, let last = parts.last, Double(last) != nil {
            parts.removeLast()
        }
        let words = parts.flatMap(splitRunTogether).map(capitalised)
        return words.isEmpty ? name : words.joined(separator: " ")
    }

    /// Splits `BulletHole` into `Bullet` and `Hole`, leaving `RSS` whole.
    private static func splitRunTogether(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in text {
            if let previous, previous.isLowercase, character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
            previous = character
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }

    private static func capitalised(_ word: String) -> String {
        guard let first = word.first, first.isLowercase else { return word }
        return first.uppercased() + word.dropFirst()
    }
}
