import CamTwistCore
import CoreImage
import Foundation

/// Looks built from Core Image's own filters, each with its own controls.
enum ClassicFilter {
    enum Name {
        static let glowingEdges = "Glowing Edges"
        static let edges = "Edges"
        static let sobel = "Sobel"
        static let monochrome = "Monochrome"
        static let watercolor = "Watercolor"
        static let inkNoir = "Ink Noir"
        static let troll = "Troll"
        static let whirlpool = "Whirlpool"
        static let colourBurst = "Colour Burst"
        static let frostedGlass = "Frosted Glass"
        static let goo = "Goo"
        static let ablaze = "Ablaze"
        static let liquidMetal = "Liquid Metal"
    }

    enum Key {
        static let radius = "Radius"
        static let intensity = "Intensity"
        static let color = "Color"
        static let blobbiness = "Blobbiness"
        static let amount = "Amount"
        static let zoom = "Zoom"
        static let spin = "Spin"
        static let masterZoom = "Master_Zoom"
        static let zoomRed = "Zoom_Red"
        static let zoomGreen = "Zoom_Green"
        static let zoomBlue = "Zoom_Blue"
        static let fine = "Fine"
        static let scale = "Scale"
        static let length = "Length"
        static let flicker = "Flicker"
        static let power = "Power"
        static let height = "Height"
    }

    private enum Range {
        static let edgeRadius: ClosedRange<Double> = 0...20
        static let edgeIntensity: ClosedRange<Double> = 0...10
        static let monochromeIntensity: ClosedRange<Double> = 0...2
        static let blobbiness: ClosedRange<Double> = 1...10
        static let troll: ClosedRange<Double> = 0...40
        static let either: ClosedRange<Double> = -1...1
        static let masterZoom: ClosedRange<Double> = 0.1...2
        static let channelZoom: ClosedRange<Double> = 1...1.5
        static let frost: ClosedRange<Double> = 0...1000
        static let frostScale: ClosedRange<Double> = 1...4
        static let fireLength: ClosedRange<Double> = 0...100
        static let flicker: ClosedRange<Double> = 0...10
        static let firePower: ClosedRange<Double> = 0...2
        static let liquidMetalHeight: ClosedRange<Double> = 0...200
    }

    private enum Start {
        static let edgeRadius = 1.0
        static let edgeIntensity = 5.0
        static let monochromeIntensity = 1.0
        static let monochromeRed = 0.667
        static let monochromeGreen = 0.524
        static let monochromeBlue = 0.372
        static let blobbiness = 1.0
        static let troll = 20.0
        static let whirlpoolZoom = -0.5
        static let whirlpoolSpin = -0.5
        static let masterZoom = 1.0
        static let zoomRed = 1.114
        static let zoomGreen = 1.018
        static let zoomBlue = 1.055
        static let frost = 40.0
        static let frostScale = 1.0
        static let gooGreen = 0.977
        static let fireLength = 10.0
        static let flicker = 10.0
        static let firePower = 1.0
        static let liquidMetalHeight = 100.0
    }

    private enum Controls {
        static let edgeRadius = NumberControl(
            key: Key.radius, displayName: "Radius", start: Start.edgeRadius, range: Range.edgeRadius
        )
        static let edgeIntensity = NumberControl(
            key: Key.intensity, displayName: "Intensity", start: Start.edgeIntensity, range: Range.edgeIntensity
        )
        static let sobelColor = ColorControl(key: Key.color, displayName: "Color", red: 1, green: 1, blue: 1)
        static let monochromeColor = ColorControl(
            key: Key.color, displayName: "Colour", red: Start.monochromeRed, green: Start.monochromeGreen,
            blue: Start.monochromeBlue
        )
        static let monochromeIntensity = NumberControl(
            key: Key.intensity, displayName: "Intensity", start: Start.monochromeIntensity,
            range: Range.monochromeIntensity
        )
        static let blobbiness = NumberControl(
            key: Key.blobbiness, displayName: "Blobbiness", start: Start.blobbiness, range: Range.blobbiness
        )
        static let troll = NumberControl(key: Key.amount, displayName: "Value", start: Start.troll, range: Range.troll)
        static let whirlpoolZoom = NumberControl(
            key: Key.zoom, displayName: "Zoom", start: Start.whirlpoolZoom, range: Range.either
        )
        static let whirlpoolSpin = NumberControl(
            key: Key.spin, displayName: "Spin", start: Start.whirlpoolSpin, range: Range.either
        )
        static let masterZoom = NumberControl(
            key: Key.masterZoom, displayName: "Master Zoom", start: Start.masterZoom, range: Range.masterZoom
        )
        static let zoomRed = NumberControl(
            key: Key.zoomRed, displayName: "Zoom Red", start: Start.zoomRed, range: Range.channelZoom
        )
        static let zoomGreen = NumberControl(
            key: Key.zoomGreen, displayName: "Zoom Green", start: Start.zoomGreen, range: Range.channelZoom
        )
        static let zoomBlue = NumberControl(
            key: Key.zoomBlue, displayName: "Zoom Blue", start: Start.zoomBlue, range: Range.channelZoom
        )
        static let frost = NumberControl(key: Key.amount, displayName: "Amount", start: Start.frost, range: Range.frost)
        static let fine = SwitchControl(key: Key.fine, displayName: "Fine")
        static let frostScale = NumberControl(
            key: Key.scale, displayName: "Scale", start: Start.frostScale, range: Range.frostScale
        )
        static let gooColor = ColorControl(key: Key.color, displayName: "Color", red: 0, green: Start.gooGreen, blue: 0)
        static let fireLength = NumberControl(
            key: Key.length, displayName: "Length", start: Start.fireLength, range: Range.fireLength
        )
        static let flicker = NumberControl(
            key: Key.flicker, displayName: "Flicker", start: Start.flicker, range: Range.flicker
        )
        static let firePower = NumberControl(
            key: Key.power, displayName: "Power", start: Start.firePower, range: Range.firePower
        )
        static let liquidMetalHeight = NumberControl(
            key: Key.height, displayName: "Height", start: Start.liquidMetalHeight, range: Range.liquidMetalHeight
        )
    }

    /// How strong each look is, in the units Core Image takes.
    private enum Tuning {
        static let sobelIntensity = 60.0
        static let comicBlurPerStep = 0.8
        static let comicContrast = 1.6
        static let comicTones = 4.0
        static let comicLineStrength = 1.0
        static let comicLineThreshold = 0.1
        static let comicLineContrast = 50.0
        static let watercolorBlur = 2.0
        static let watercolorPasses = 4
        static let watercolorLevels = 20.0
        static let watercolorSaturation = 0.85
        static let watercolorBrightness = 0.04
        /// How faint the paper's texture is, and how coarse.
        static let paperStrength = 0.12
        /// The brightness of mid grey, which the paper texture is centred on.
        static let midBrightness = 0.5
        static let paperCell: CGFloat = 3
        /// The troll's bulge at full value, and how far it pulses either way.
        static let trollScale = 1.0
        static let trollPulse = 0.25
        static let trollPulseRate = 2.0
        /// The share of the picture's height the troll's bulge covers.
        static let trollReach: CGFloat = 0.6
        /// The whirlpool: turns at full spin, how far the picture is scaled at
        /// full zoom, and the share of the picture's width it covers.
        static let whirlpoolTurns = 16.0
        static let whirlpoolZoomShare = 0.5
        static let whirlpoolReach: CGFloat = 0.35
        /// Pixels the frost moves the picture by for each step of its amount,
        /// at a picture a thousand points wide.
        static let frostPerStep = 0.5
        static let frostReferenceWidth: CGFloat = 1000
        static let frostBlurShare = 0.05
        static let frostFineCell: CGFloat = 1
        static let frostCoarseCell: CGFloat = 3
        static let gooBlur = 5.0
        static let gooContrast = 1.8
        static let gooBrightness = 0.15
        static let gooGlossRadius = 10.0
        static let gooGlossAmount = 1.6
        static let fireDark = CIColor(red: 0.08, green: 0, blue: 0)
        static let fireBright = CIColor(red: 1, green: 0.55, blue: 0.05)
        static let fireBloomRadius = 12.0
        static let fireBloomIntensity = 0.8
        /// How far a flame streaks up the picture at full length, as a share of its height.
        static let fireStreakShare = 0.25
        static let fireFlickerStops = 0.35
        static let fireGlowStops = 0.7
        static let fireFlickerRate = 23.0
        static let fireContrast = 1.4
        static let upDegrees = 90.0
        static let liquidMetalBlurShare = 0.04
        static let liquidMetalCell: CGFloat = 40
        static let liquidMetalSpeed = 30.0
        static let liquidMetalSaturation = 0.12
        static let liquidMetalContrast = 1.25
        static let liquidMetalDisplacementShare = 0.4
        static let liquidMetalReferenceWidth: CGFloat = 1000
        static let liquidMetalGloss = 0.8
        static let liquidMetalGlossRadius = 6.0
    }

    private static func effect(
        _ name: String, _ controls: [EffectParameter], _ recipe: @escaping RecipeEffect.Recipe
    ) -> NativeEffect {
        NativeEffect(name: name, kind: .filter, parameters: controls) { RecipeEffect(canvas: $0, recipe: recipe) }
    }

    private static func middle(of canvas: CGSize) -> CIVector {
        CIVector(x: canvas.width / 2, y: canvas.height / 2)
    }

    private static func scaled(_ image: CIImage, by factor: CGFloat, about canvas: CGSize) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: canvas.width / 2, y: canvas.height / 2)
            .scaledBy(x: factor, y: factor).translatedBy(x: -canvas.width / 2, y: -canvas.height / 2))
    }

    private static func grey(_ image: CIImage) -> CIImage {
        image.applyingFilter(CIFilterName.colorControls, parameters: [kCIInputSaturationKey: 0])
    }

    /// One of a picture's colour channels.
    private enum Channel {
        case red, green, blue

        /// What each output colour takes from the input colours, so the
        /// others come out black.
        var vectors: (red: CIVector, green: CIVector, blue: CIVector) {
            let kept = (red: CIVector(x: 1, y: 0, z: 0, w: 0), green: CIVector(x: 0, y: 1, z: 0, w: 0),
                        blue: CIVector(x: 0, y: 0, z: 1, w: 0))
            let none = CIVector(x: 0, y: 0, z: 0, w: 0)
            switch self {
            case .red: return (kept.red, none, none)
            case .green: return (none, kept.green, none)
            case .blue: return (none, none, kept.blue)
            }
        }
    }

    /// One colour channel of a picture, scaled about the middle.
    private static func channel(_ kept: Channel, of image: CIImage, zoom: Double, canvas: CGSize) -> CIImage {
        let vectors = kept.vectors
        let only = image.applyingFilter(CIFilterName.colorMatrix, parameters: [
            CIInputKey.redVector: vectors.red,
            CIInputKey.greenVector: vectors.green,
            CIInputKey.blueVector: vectors.blue,
            CIInputKey.alphaVector: CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        return scaled(only, by: CGFloat(zoom), about: canvas)
    }

    static let all: [NativeEffect] = [
        effect(Name.glowingEdges, [Controls.edgeRadius.parameter]) { image, values, _, _ in
            image.clampedToExtent().applyingFilter(CIFilterName.edgeWork, parameters: [
                kCIInputRadiusKey: Controls.edgeRadius.value(in: values),
            ])
        },
        effect(Name.edges, [Controls.edgeIntensity.parameter]) { image, values, _, _ in
            image.clampedToExtent().applyingFilter(CIFilterName.edges, parameters: [
                kCIInputIntensityKey: Controls.edgeIntensity.value(in: values),
            ])
        },
        effect(Name.sobel, [Controls.sobelColor.parameter]) { image, values, _, _ in
            // Edges found in the brightness, then lit in the colour chosen.
            grey(image.clampedToExtent()).applyingFilter(CIFilterName.edges, parameters: [
                kCIInputIntensityKey: Tuning.sobelIntensity,
            ]).applyingFilter(CIFilterName.monochrome, parameters: [
                kCIInputColorKey: CIColor(cgColor: Controls.sobelColor.value(in: values)),
                kCIInputIntensityKey: 1,
            ])
        },
        effect(Name.monochrome, [Controls.monochromeColor.parameter, Controls.monochromeIntensity.parameter]) { image, values, _, _ in
            image.applyingFilter(CIFilterName.monochrome, parameters: [
                kCIInputColorKey: CIColor(cgColor: Controls.monochromeColor.value(in: values)),
                kCIInputIntensityKey: Controls.monochromeIntensity.value(in: values),
            ])
        },
        effect(Name.watercolor, []) { image, _, canvas, _ in
            // Colours pooled into flat washes with soft edges, a little
            // paler, on paper with a faint texture.
            let softened = image.clampedToExtent().applyingGaussianBlur(sigma: Tuning.watercolorBlur)
            // Each pass of the median filter rounds the shapes a little more.
            let rounded = (0..<Tuning.watercolorPasses).reduce(softened) { picture, _ in
                picture.applyingFilter(CIFilterName.medianFilter)
            }
            let wash = rounded
                .applyingFilter(CIFilterName.posterize, parameters: [CIInputKey.levels: Tuning.watercolorLevels])
                .applyingFilter(CIFilterName.colorControls, parameters: [
                    kCIInputSaturationKey: Tuning.watercolorSaturation,
                    kCIInputBrightnessKey: Tuning.watercolorBrightness,
                ])
            let paper = NoiseField.image(canvas: canvas, cell: Tuning.paperCell)
                .applyingFilter(CIFilterName.colorControls, parameters: [
                    kCIInputContrastKey: Tuning.paperStrength, kCIInputBrightnessKey: Tuning.midBrightness - Tuning.paperStrength / 2,
                ])
            return wash.applyingFilter(CIFilterName.multiplyBlend, parameters: [kCIInputBackgroundImageKey: paper])
        },
        effect(Name.inkNoir, [Controls.blobbiness.parameter]) { image, values, _, _ in
            // Flat black, grey and white shapes, with ink lines over them.
            let source = image.clampedToExtent()
            let tones = grey(source)
                .applyingFilter(CIFilterName.colorControls, parameters: [kCIInputContrastKey: Tuning.comicContrast])
                .applyingGaussianBlur(sigma: Controls.blobbiness.value(in: values) * Tuning.comicBlurPerStep)
                .applyingFilter(CIFilterName.posterize, parameters: [CIInputKey.levels: Tuning.comicTones])
            let lines = source.applyingFilter(CIFilterName.lineOverlay, parameters: [
                CIInputKey.edgeIntensity: Tuning.comicLineStrength,
                CIInputKey.threshold: Tuning.comicLineThreshold,
                CIInputKey.contrast: Tuning.comicLineContrast,
            ])
            return lines.composited(over: tones)
        },
        effect(Name.troll, [Controls.troll.parameter]) { image, values, canvas, time in
            // The middle of the picture swells, and breathes.
            let breath = 1 + Tuning.trollPulse * sin(time * Tuning.trollPulseRate)
            let value = Controls.troll.value(in: values) / Range.troll.upperBound
            return image.clampedToExtent().applyingFilter(CIFilterName.bumpDistortion, parameters: [
                kCIInputCenterKey: middle(of: canvas),
                kCIInputRadiusKey: Tuning.trollReach * canvas.height,
                kCIInputScaleKey: value * Tuning.trollScale * breath,
            ])
        },
        effect(Name.whirlpool, [Controls.whirlpoolZoom.parameter, Controls.whirlpoolSpin.parameter]) { image, values, canvas, _ in
            let zoomed = scaled(
                image.clampedToExtent(), by: CGFloat(1 + Controls.whirlpoolZoom.value(in: values) * Tuning.whirlpoolZoomShare),
                about: canvas
            )
            return zoomed.applyingFilter(CIFilterName.vortex, parameters: [
                kCIInputCenterKey: middle(of: canvas),
                kCIInputRadiusKey: Tuning.whirlpoolReach * canvas.width,
                kCIInputAngleKey: Controls.whirlpoolSpin.value(in: values) * Tuning.whirlpoolTurns * 2 * Double.pi,
            ])
        },
        effect(Name.colourBurst, [
            Controls.masterZoom.parameter, Controls.zoomRed.parameter, Controls.zoomGreen.parameter,
            Controls.zoomBlue.parameter,
        ]) { image, values, canvas, _ in
            // Each colour is magnified by its own amount, as a cheap lens does.
            let master = Controls.masterZoom.value(in: values)
            let black = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: canvas))
            func added(_ kept: Channel, _ control: NumberControl, over base: CIImage) -> CIImage {
                channel(kept, of: image, zoom: control.value(in: values) * master, canvas: canvas)
                    .applyingFilter(CIFilterName.additionCompositing, parameters: [kCIInputBackgroundImageKey: base])
            }
            let withRed = added(.red, Controls.zoomRed, over: black)
            let withGreen = added(.green, Controls.zoomGreen, over: withRed)
            return added(.blue, Controls.zoomBlue, over: withGreen)
        },
        effect(Name.frostedGlass, [
            Controls.frost.parameter, Controls.fine.parameter, Controls.frostScale.parameter,
        ]) { image, values, canvas, _ in
            // The picture seen through rough glass: softened, then every
            // part of it nudged by noise.
            let amount = Controls.frost.value(in: values)
            let cell = (Controls.fine.isOn(in: values) ? Tuning.frostFineCell : Tuning.frostCoarseCell)
                * CGFloat(Controls.frostScale.value(in: values))
            let reach = amount * Tuning.frostPerStep * Double(canvas.width / Tuning.frostReferenceWidth)
            return image.clampedToExtent()
                .applyingGaussianBlur(sigma: amount * Tuning.frostBlurShare)
                .applyingFilter(CIFilterName.displacementDistortion, parameters: [
                    CIInputKey.displacementImage: NoiseField.image(canvas: canvas, cell: cell),
                    kCIInputScaleKey: reach,
                ])
        },
        effect(Name.goo, [Controls.gooColor.parameter]) { image, values, _, _ in
            // The picture as one glossy, blobby colour.
            image.clampedToExtent()
                .applyingGaussianBlur(sigma: Tuning.gooBlur)
                .applyingFilter(CIFilterName.colorControls, parameters: [
                    kCIInputSaturationKey: 0, kCIInputContrastKey: Tuning.gooContrast,
                    kCIInputBrightnessKey: Tuning.gooBrightness,
                ])
                .applyingFilter(CIFilterName.monochrome, parameters: [
                    kCIInputColorKey: CIColor(cgColor: Controls.gooColor.value(in: values)),
                    kCIInputIntensityKey: 1,
                ])
                .applyingFilter(CIFilterName.unsharpMask, parameters: [
                    kCIInputRadiusKey: Tuning.gooGlossRadius, kCIInputIntensityKey: Tuning.gooGlossAmount,
                ])
        },
        effect(Name.ablaze, [
            Controls.fireLength.parameter, Controls.flicker.parameter, Controls.firePower.parameter,
        ]) { image, values, canvas, time in
            // Brightness turned into flame colours and smeared upwards.
            let length = Controls.fireLength.value(in: values) / Range.fireLength.upperBound
            let flicker = Controls.flicker.value(in: values) / Range.flicker.upperBound
            let stops = flicker * Tuning.fireFlickerStops * sin(time * Tuning.fireFlickerRate)
            let power = Controls.firePower.value(in: values)
            return grey(image.clampedToExtent())
                .applyingFilter(CIFilterName.colorControls, parameters: [
                    kCIInputContrastKey: Tuning.fireContrast * power,
                ])
                .applyingFilter(CIFilterName.motionBlur, parameters: [
                    kCIInputRadiusKey: length * Tuning.fireStreakShare * canvas.height,
                    kCIInputAngleKey: Tuning.upDegrees * Double.pi / 180,
                ])
                .applyingFilter(CIFilterName.falseColor, parameters: [
                    CIInputKey.color0: Tuning.fireDark, CIInputKey.color1: Tuning.fireBright,
                ])
                .applyingFilter(CIFilterName.exposureAdjust, parameters: [kCIInputEVKey: stops + Tuning.fireGlowStops])
                .applyingFilter(CIFilterName.bloom, parameters: [
                    kCIInputRadiusKey: Tuning.fireBloomRadius, kCIInputIntensityKey: Tuning.fireBloomIntensity,
                ])
        },
        effect(Name.liquidMetal, [Controls.liquidMetalHeight.parameter]) { image, values, canvas, time in
            // Liquid metal: the picture drained of colour and polished, and
            // moved about by slow, soft ripples.
            let ripples = NoiseField.image(
                canvas: canvas, cell: Tuning.liquidMetalCell, offset: CGPoint(x: time * Tuning.liquidMetalSpeed, y: 0)
            ).applyingGaussianBlur(sigma: Double(canvas.width) * Tuning.liquidMetalBlurShare)
            let reach = Controls.liquidMetalHeight.value(in: values) * Tuning.liquidMetalDisplacementShare
                * Double(canvas.width / Tuning.liquidMetalReferenceWidth)
            return image.clampedToExtent()
                .applyingFilter(CIFilterName.colorControls, parameters: [
                    kCIInputSaturationKey: Tuning.liquidMetalSaturation, kCIInputContrastKey: Tuning.liquidMetalContrast,
                ])
                .applyingFilter(CIFilterName.displacementDistortion, parameters: [
                    CIInputKey.displacementImage: ripples, kCIInputScaleKey: reach,
                ])
                .applyingFilter(CIFilterName.unsharpMask, parameters: [
                    kCIInputRadiusKey: Tuning.liquidMetalGlossRadius, kCIInputIntensityKey: Tuning.liquidMetalGloss,
                ])
        },
    ]
}

public extension NativeEffect {
    /// Edges, monochrome, watercolour, ink noir, troll, whirlpool, colour
    /// burst, frosted glass, goo, fire and liquid metal.
    static var classicFilters: [NativeEffect] { ClassicFilter.all }
}
