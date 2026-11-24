import AppKit
import CamTwistCore
import Foundation

/// Which control an effect's setting is shown with.
public enum ParameterControlKind: Equatable {
    case number(ClosedRange<Double>)
    case toggle
    /// A file of one of these types, chosen with the system's panel.
    case file(types: [String])
    case font
    case choices([String])
    case text
    case color

    public init(parameter: EffectParameter, value: EffectValue) {
        switch value {
        case .number: self = .number(parameter.range ?? EffectParameterRange.fallback)
        case .boolean: self = .toggle
        case .string:
            if let types = parameter.fileTypes {
                self = .file(types: types)
            } else if parameter.isFont {
                self = .font
            } else if let choices = parameter.choices {
                self = .choices(choices)
            } else {
                self = .text
            }
        case .color: self = .color
        }
    }
}

/// The words on a file setting.
public enum FileSettingText {
    public static func shown(path: String) -> String {
        path.isEmpty ? "None chosen" : (path as NSString).lastPathComponent
    }

    public static func chooseTitle(path: String) -> String {
        path.isEmpty ? "Choose file" : "Choose another file"
    }
}

extension EffectValue {
    /// A colour from the system's picker, in sRGB. One with no sRGB form is white.
    public init(picked: NSColor) {
        guard let color = picked.usingColorSpace(.sRGB) else {
            self = .color(red: 1, green: 1, blue: 1, alpha: 1)
            return
        }
        self = .color(
            red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: color.alphaComponent
        )
    }
}

/// A source's branch: the effects and sources that apply to it alone.
public enum BranchEditing {
    /// A branch with nothing in it is stored as none.
    public static func stored(_ items: [ChainItem]) -> [ChainItem]? { items.isEmpty ? nil : items }

    public static func shown(_ stored: [ChainItem]?) -> [ChainItem] { stored ?? [] }

    /// Which source new steps go to after the button is pressed: this one,
    /// or the main chain when it already is.
    public static func target(afterPressingFor id: UUID, current: UUID?) -> UUID? {
        current == id ? nil : id
    }

    public static func buttonTitle(isTarget: Bool, sourceTitle: String) -> String {
        isTarget ? "Stop adding here" : "Add to \(sourceTitle) only"
    }
}

/// One slider of the placement controls every source has.
public struct PlacementSlider {
    public let title: String
    public let range: ClosedRange<Double>
    public let value: (PictureInPictureSettings) -> Double
    public let setValue: (inout PictureInPictureSettings, Double) -> Void

    public static let all: [PlacementSlider] = [
        PlacementSlider(
            title: "Position X", range: PictureInPictureSettings.positionRange,
            value: { $0.center.x }, setValue: { $0.center.x = $1 }
        ),
        PlacementSlider(
            title: "Position Y", range: PictureInPictureSettings.positionRange,
            value: { $0.center.y }, setValue: { $0.center.y = $1 }
        ),
        PlacementSlider(
            title: "Size", range: PictureInPictureSettings.scaleRange, value: { $0.scale }, setValue: { $0.scale = $1 }
        ),
        PlacementSlider(
            title: "Rotate", range: PictureInPictureSettings.rotationRange,
            value: { $0.rotation }, setValue: { $0.rotation = $1 }
        ),
        PlacementSlider(
            title: "Tilt", range: PictureInPictureSettings.rotationRange, value: { $0.tilt }, setValue: { $0.tilt = $1 }
        ),
        PlacementSlider(
            title: "Swing", range: PictureInPictureSettings.rotationRange,
            value: { $0.swing }, setValue: { $0.swing = $1 }
        ),
    ]
}

/// Whether picture in picture is on, which is when placement settings exist.
public enum PlacementEditing {
    public static func isOn(_ settings: PictureInPictureSettings?) -> Bool { settings != nil }

    public static func settings(whenOn isOn: Bool) -> PictureInPictureSettings? {
        isOn ? PictureInPictureSettings() : nil
    }
}
