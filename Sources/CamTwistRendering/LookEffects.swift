import CamTwistCore
import CoreImage
import Foundation

/// Looks and distortions made from Core Image's own filters, each with a
/// control or two.
enum LookEffect {
    private static let degreesToRadians = Double.pi / 180
    private static let fullTurn = 2 * Double.pi

    private static func middle(of canvas: CGSize) -> CIVector {
        CIVector(x: canvas.width / 2, y: canvas.height / 2)
    }

    private static func effect(
        _ name: String, _ parameters: [EffectParameter], _ recipe: @escaping RecipeEffect.Recipe
    ) -> NativeEffect {
        NativeEffect(name: name, kind: .filter, parameters: parameters) { RecipeEffect(canvas: $0, recipe: recipe) }
    }

    /// An effect that is one Core Image filter with nothing to adjust.
    private static func plain(_ name: String, filter: String) -> NativeEffect {
        effect(name, []) { image, _, _, _ in image.applyingFilter(filter) }
    }

    enum Key {
        static let amount = "Amount"
        static let levels = "Levels"
        static let angle = "Angle"
        static let count = "Count"
        static let size = EffectParameterKey.size
        static let color = "Color"
        static let rightSide = "Right_Side"
        static let position = "Position"
        static let radius = "Radius"
    }

    private enum Name {
        static let sepia = "Sepia"
        static let blackAndWhite = "Black and White"
        static let invert = "Invert"
        static let posterize = "Posterize"
        static let hueShift = "Hue Shift"
        static let tint = "Tint"
        static let thermal = "Thermal"
        static let xRay = "X-Ray"
        static let kaleidoscope = "Kaleidoscope"
        static let twirl = "Twirl"
        static let pinch = "Pinch"
        static let halftone = "Halftone"
        static let crystallize = "Crystallize"
        static let glow = "Glow"
        static let motionBlur = "Motion Blur"
        static let zoomBlur = "Zoom Blur"
    }

    private enum Range {
        static let unit: ClosedRange<Double> = 0...1
        static let either: ClosedRange<Double> = -1...1
        static let degrees: ClosedRange<Double> = -180...180
        /// Where a mirror may stand, as a share of the picture's width.
        static let mirrorPosition: ClosedRange<Double> = 0.05...0.95
        static let contrast: ClosedRange<Double> = 0.5...2
        static let posterizeLevels: ClosedRange<Double> = 2...20
        static let kaleidoscopeSegments: ClosedRange<Double> = 2...16
    }

    /// Lengths given as shares of the picture's width.
    private enum Share {
        static let largestDot = 0.05
        static let largestCrystal = 0.08
        static let largestGlow = 0.05
        static let longestSmear = 0.08
        static let largestZoom = 0.06
    }

    /// The smallest sizes Core Image is given, so a control at zero still
    /// leaves something to draw.
    private enum Floor {
        static let dot = 2.0
        static let crystal = 1.0
    }

    /// What every control starts with.
    private enum Start {
        static let sepia = 1.0
        static let contrast = 1.1
        static let posterizeLevels = 6.0
        static let hueDegrees = 90.0
        static let tintAmount = 1.0
        static let kaleidoscopeSegments = 5.0
        static let kaleidoscopeDegrees = 160.0
        static let mirrorPosition = 0.5
        static let distortionAmount = 0.5
        static let distortionSize = 0.6
        static let halftoneSize = 0.2
        static let crystalSize = 0.3
        static let glowAmount = 0.7
        static let glowReach = 0.4
        static let motionBlur = 0.15
        static let motionDegrees = 0.0
        static let zoomBlur = 0.1
        static let tintRed = 0.2
        static let tintGreen = 0.5
        static let tintBlue = 1.0
    }

    private enum Controls {
        static let sepia = NumberControl(key: Key.amount, displayName: "Amount", start: Start.sepia, range: Range.unit)
        static let contrast = NumberControl(
            key: Key.amount, displayName: "Contrast", start: Start.contrast, range: Range.contrast
        )
        static let posterize = NumberControl(
            key: Key.levels, displayName: "Levels", start: Start.posterizeLevels, range: Range.posterizeLevels
        )
        static let hue = NumberControl(key: Key.angle, displayName: "Degrees", start: Start.hueDegrees, range: Range.degrees)
        static let tintColor = ColorControl(
            key: Key.color, displayName: "Colour", red: Start.tintRed, green: Start.tintGreen, blue: Start.tintBlue
        )
        static let tintAmount = NumberControl(
            key: Key.amount, displayName: "Amount", start: Start.tintAmount, range: Range.unit
        )
        static let segments = NumberControl(
            key: Key.count, displayName: "Segments", start: Start.kaleidoscopeSegments, range: Range.kaleidoscopeSegments
        )
        static let segmentAngle = NumberControl(
            key: Key.angle, displayName: "Degrees", start: Start.kaleidoscopeDegrees, range: Range.degrees
        )
        static let rightSide = SwitchControl(key: Key.rightSide, displayName: "Keep the right side")
        static let mirrorPosition = NumberControl(
            key: Key.position, displayName: "Where the mirror is", start: Start.mirrorPosition, range: Range.mirrorPosition
        )
        static let distortionAmount = NumberControl(
            key: Key.amount, displayName: "Amount", start: Start.distortionAmount, range: Range.either
        )
        static let distortionSize = NumberControl(
            key: Key.size, displayName: "Size", start: Start.distortionSize, range: Range.unit
        )
        static let halftone = NumberControl(
            key: Key.size, displayName: "Dot size", start: Start.halftoneSize, range: Range.unit
        )
        static let crystal = NumberControl(
            key: Key.size, displayName: "Crystal size", start: Start.crystalSize, range: Range.unit
        )
        static let glowAmount = NumberControl(
            key: Key.amount, displayName: "Amount", start: Start.glowAmount, range: Range.unit
        )
        static let glowReach = NumberControl(
            key: Key.size, displayName: "Reach", start: Start.glowReach, range: Range.unit
        )
        static let motionAmount = NumberControl(
            key: Key.amount, displayName: "Amount", start: Start.motionBlur, range: Range.unit
        )
        static let motionAngle = NumberControl(
            key: Key.angle, displayName: "Degrees", start: Start.motionDegrees, range: Range.degrees
        )
        static let zoom = NumberControl(key: Key.amount, displayName: "Amount", start: Start.zoomBlur, range: Range.unit)
    }

    /// One half of the picture reflected onto the other.
    static let mirrorName = "Mirror"

    static let all: [NativeEffect] = [
        effect(Name.sepia, [Controls.sepia.parameter]) { image, values, _, _ in
            image.applyingFilter(CIFilterName.sepia, parameters: [kCIInputIntensityKey: Controls.sepia.value(in: values)])
        },
        effect(Name.blackAndWhite, [Controls.contrast.parameter]) { image, values, _, _ in
            image.applyingFilter(CIFilterName.colorControls, parameters: [
                kCIInputSaturationKey: 0, kCIInputContrastKey: Controls.contrast.value(in: values),
            ])
        },
        plain(Name.invert, filter: CIFilterName.colorInvert),
        effect(Name.posterize, [Controls.posterize.parameter]) { image, values, _, _ in
            image.applyingFilter(CIFilterName.posterize, parameters: [CIInputKey.levels: Controls.posterize.value(in: values)])
        },
        effect(Name.hueShift, [Controls.hue.parameter]) { image, values, _, _ in
            image.applyingFilter(CIFilterName.hueAdjust, parameters: [
                kCIInputAngleKey: Controls.hue.value(in: values) * degreesToRadians,
            ])
        },
        effect(Name.tint, [Controls.tintColor.parameter, Controls.tintAmount.parameter]) { image, values, _, _ in
            image.applyingFilter(CIFilterName.monochrome, parameters: [
                kCIInputColorKey: CIColor(cgColor: Controls.tintColor.value(in: values)),
                kCIInputIntensityKey: Controls.tintAmount.value(in: values),
            ])
        },
        plain(Name.thermal, filter: CIFilterName.thermal),
        plain(Name.xRay, filter: CIFilterName.xRay),
        effect(Name.kaleidoscope, [Controls.segments.parameter, Controls.segmentAngle.parameter]) { image, values, canvas, _ in
            image.applyingFilter(CIFilterName.kaleidoscope, parameters: [
                CIInputKey.count: Controls.segments.value(in: values),
                kCIInputAngleKey: Controls.segmentAngle.value(in: values) * degreesToRadians,
                kCIInputCenterKey: middle(of: canvas),
            ])
        },
        effect(mirrorName, [Controls.rightSide.parameter, Controls.mirrorPosition.parameter]) { image, values, canvas, _ in
            // One side of the picture, and its reflection across the line
            // where the mirror stands.
            let keepsRight = Controls.rightSide.isOn(in: values)
            let position = Controls.mirrorPosition.value(in: values)
            let line = min(max(position, Range.mirrorPosition.lowerBound), Range.mirrorPosition.upperBound) * canvas.width
            let side = keepsRight
                ? CGRect(x: line, y: 0, width: canvas.width - line, height: canvas.height)
                : CGRect(x: 0, y: 0, width: line, height: canvas.height)
            let kept = image.cropped(to: side)
            let reflection = kept.transformed(by: CGAffineTransform(translationX: 2 * line, y: 0).scaledBy(x: -1, y: 1))
            return kept.composited(over: reflection)
        },
        effect(Name.twirl, [Controls.distortionAmount.parameter, Controls.distortionSize.parameter]) { image, values, canvas, _ in
            image.clampedToExtent().applyingFilter(CIFilterName.twirl, parameters: [
                kCIInputCenterKey: middle(of: canvas),
                kCIInputRadiusKey: Controls.distortionSize.value(in: values) * canvas.width / 2,
                kCIInputAngleKey: Controls.distortionAmount.value(in: values) * fullTurn,
            ])
        },
        effect(Name.pinch, [Controls.distortionAmount.parameter, Controls.distortionSize.parameter]) { image, values, canvas, _ in
            image.clampedToExtent().applyingFilter(CIFilterName.pinch, parameters: [
                kCIInputCenterKey: middle(of: canvas),
                kCIInputRadiusKey: Controls.distortionSize.value(in: values) * canvas.width / 2,
                kCIInputScaleKey: Controls.distortionAmount.value(in: values),
            ])
        },
        effect(Name.halftone, [Controls.halftone.parameter]) { image, values, canvas, _ in
            image.applyingFilter(CIFilterName.dotScreen, parameters: [
                kCIInputCenterKey: middle(of: canvas),
                kCIInputWidthKey: max(Controls.halftone.value(in: values) * Share.largestDot * canvas.width, Floor.dot),
            ])
        },
        effect(Name.crystallize, [Controls.crystal.parameter]) { image, values, canvas, _ in
            image.clampedToExtent().applyingFilter(CIFilterName.crystallize, parameters: [
                kCIInputCenterKey: middle(of: canvas),
                kCIInputRadiusKey: max(Controls.crystal.value(in: values) * Share.largestCrystal * canvas.width, Floor.crystal),
            ])
        },
        effect(Name.glow, [Controls.glowAmount.parameter, Controls.glowReach.parameter]) { image, values, canvas, _ in
            image.clampedToExtent().applyingFilter(CIFilterName.bloom, parameters: [
                kCIInputIntensityKey: Controls.glowAmount.value(in: values),
                kCIInputRadiusKey: Controls.glowReach.value(in: values) * Share.largestGlow * canvas.width,
            ])
        },
        effect(Name.motionBlur, [Controls.motionAmount.parameter, Controls.motionAngle.parameter]) { image, values, canvas, _ in
            image.clampedToExtent().applyingFilter(CIFilterName.motionBlur, parameters: [
                kCIInputRadiusKey: Controls.motionAmount.value(in: values) * Share.longestSmear * canvas.width,
                kCIInputAngleKey: Controls.motionAngle.value(in: values) * degreesToRadians,
            ])
        },
        effect(Name.zoomBlur, [Controls.zoom.parameter]) { image, values, canvas, _ in
            image.clampedToExtent().applyingFilter(CIFilterName.zoomBlur, parameters: [
                kCIInputCenterKey: middle(of: canvas),
                CIInputKey.amount: Controls.zoom.value(in: values) * Share.largestZoom * canvas.width,
            ])
        },
    ]
}

public extension NativeEffect {
    /// Looks and distortions: sepia, black and white, invert, posterize,
    /// hue shift, tint, thermal, X-ray, kaleidoscope, mirror,
    /// twirl, pinch, halftone, crystallize, glow, motion blur and zoom blur.
    static var looks: [NativeEffect] { LookEffect.all }
}
