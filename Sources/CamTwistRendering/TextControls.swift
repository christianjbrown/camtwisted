import CamTwistCore
import CoreGraphics
import Foundation

/// The controls that say where text sits and how big and how turned it is.
/// They are named so the picture can be dragged, resized and turned.
struct TextPlacement {
    let xKey: String
    let yKey: String
    let sizeKey: String
    let rotationKey: String
    let startX: Double
    let startY: Double
    /// How much of the picture's width the text spans to begin with.
    let startSize: Double

    var parameters: [EffectParameter] {
        [
            NumberControl(key: xKey, displayName: "X Position", start: startX, range: OverlayRange.position).parameter,
            NumberControl(key: yKey, displayName: "Y Position", start: startY, range: OverlayRange.position).parameter,
        ] + TextStamp.controls(sizeKey: sizeKey, defaultSize: startSize, rotationKey: rotationKey)
    }

    func centre(in values: [String: EffectValue], canvas: CGSize) -> CGPoint {
        OverlayPlacement.point(
            x: values.number(xKey, default: startX), y: values.number(yKey, default: startY), canvas: canvas
        )
    }

    func width(in values: [String: EffectValue], canvas: CGSize) -> CGFloat {
        CGFloat(values.number(sizeKey, default: startSize)) * canvas.width
    }

    func rotation(in values: [String: EffectValue]) -> Double {
        values.number(rotationKey, default: 0)
    }
}

/// The font and colours of a piece of text.
struct TextLook {
    static let defaultFont = "Helvetica-Bold"

    let fontKey: String
    let colorKey: String
    let shadowKey: String
    /// Nil for text that has no box behind it.
    let backgroundKey: String?

    private static let clear = CGColor(gray: 0, alpha: 0)

    var parameters: [EffectParameter] {
        let clearColor = EffectValue.color(red: 0, green: 0, blue: 0, alpha: 0)
        var controls = [
            EffectParameter(
                key: fontKey, displayName: "Font Name", kind: .string, defaultValue: .string(Self.defaultFont), isFont: true
            ),
            ColorControl(key: colorKey, displayName: "Color", red: 1, green: 1, blue: 1).parameter,
            // Shadows and boxes start clear, which is off. Their controls are there to turn them on.
            EffectParameter(key: shadowKey, displayName: "Shadow", kind: .color, defaultValue: clearColor),
        ]
        if let backgroundKey {
            controls.append(
                EffectParameter(key: backgroundKey, displayName: "Background", kind: .color, defaultValue: clearColor)
            )
        }
        return controls
    }

    func fontName(in values: [String: EffectValue]) -> String {
        values.string(fontKey, default: Self.defaultFont)
    }

    func color(in values: [String: EffectValue]) -> CGColor {
        values.color(colorKey, default: CGColor(gray: 1, alpha: 1))
    }

    func shadow(in values: [String: EffectValue]) -> CGColor? {
        Self.visible(values.color(shadowKey, default: Self.clear))
    }

    func background(in values: [String: EffectValue]) -> CGColor? {
        backgroundKey.flatMap { Self.visible(values.color($0, default: Self.clear)) }
    }

    private static func visible(_ color: CGColor) -> CGColor? {
        color.alpha > 0 ? color : nil
    }
}
