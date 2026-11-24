import Foundation

/// A value an effect control can hold.
public enum EffectValue: Codable, Equatable, Sendable {
    case number(Double)
    case boolean(Bool)
    case string(String)
    case color(red: Double, green: Double, blue: Double, alpha: Double)
}

public enum EffectParameterKind: String, Codable, Sendable {
    case number
    case boolean
    case string
    case color
}

/// One control an effect exposes.
public struct EffectParameter: Equatable, Identifiable, Sendable {
    public let key: String
    public let displayName: String
    public let kind: EffectParameterKind
    public let defaultValue: EffectValue
    public let range: ClosedRange<Double>?
    /// For a text control that takes one of a few set values, those values.
    public let choices: [String]?
    /// Whether a text control holds the name of a font, to be picked from
    /// the fonts on this Mac.
    public let isFont: Bool
    /// For a text control that holds the path of a file, the kinds of file
    /// it takes, by extension.
    public let fileTypes: [String]?

    public var id: String { key }

    public init(
        key: String,
        displayName: String,
        kind: EffectParameterKind,
        defaultValue: EffectValue,
        range: ClosedRange<Double>? = nil,
        choices: [String]? = nil,
        isFont: Bool = false,
        fileTypes: [String]? = nil
    ) {
        self.key = key
        self.displayName = displayName
        self.kind = kind
        self.defaultValue = defaultValue
        self.range = range
        self.choices = choices
        self.isFont = isFont
        self.fileTypes = fileTypes
    }
}

/// The values a newly added effect starts with, where they should differ
/// from the ones the effect declares.
public enum EffectStartingValues {
    /// Marks a control as belonging to a drop shadow.
    private static let shadowMarker = "shadow"

    /// Drop shadows start switched off: their colour is clear and any
    /// offset is zero. The controls are still there to turn them back on.
    /// Everything else starts with the value the effect declares.
    public static func values(for parameters: [EffectParameter]) -> [String: EffectValue] {
        var values: [String: EffectValue] = [:]
        for parameter in parameters where parameter.key.lowercased().contains(shadowMarker) {
            switch parameter.kind {
            case .color: values[parameter.key] = .color(red: 0, green: 0, blue: 0, alpha: 0)
            case .number: values[parameter.key] = .number(0)
            case .boolean: values[parameter.key] = .boolean(false)
            case .string: break
            }
        }
        return values
    }
}

public enum EffectParameterRange {
    /// Used when an effect gives a number control no limits of its own.
    public static let fallback: ClosedRange<Double> = 0...1
}
