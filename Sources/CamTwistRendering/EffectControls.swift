import CamTwistCore
import CoreGraphics
import Foundation

/// A number control, declared once so the starting value the control shows
/// and the fallback used when reading it back can never drift apart.
struct NumberControl {
    let key: String
    let displayName: String
    let start: Double
    let range: ClosedRange<Double>

    var parameter: EffectParameter {
        EffectParameter(key: key, displayName: displayName, kind: .number, defaultValue: .number(start), range: range)
    }

    func value(in values: [String: EffectValue]) -> Double {
        values.number(key, default: start)
    }
}

/// A switch, which starts off.
struct SwitchControl {
    let key: String
    let displayName: String

    var parameter: EffectParameter {
        EffectParameter(key: key, displayName: displayName, kind: .boolean, defaultValue: .boolean(false))
    }

    func isOn(in values: [String: EffectValue]) -> Bool {
        values.boolean(key)
    }
}

/// A colour control, declared once like the number control.
struct ColorControl {
    let key: String
    let displayName: String
    let red: Double
    let green: Double
    let blue: Double

    var parameter: EffectParameter {
        EffectParameter(
            key: key, displayName: displayName, kind: .color,
            defaultValue: .color(red: red, green: green, blue: blue, alpha: 1)
        )
    }

    func value(in values: [String: EffectValue]) -> CGColor {
        values.color(key, default: CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
    }
}
