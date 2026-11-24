import CamTwistCore
import CoreImage
import Foundation

/// Holds the picture still while the Freeze switch is on.
public final class FreezeFrameEffect: ImageEffect {
    public static let name = "Freeze Frame"
    public static let freezeKey = "Freeze"

    private static let freeze = SwitchControl(key: freezeKey, displayName: "Freeze")

    public static let parameters = [freeze.parameter]

    private let canvas: CGSize
    private let pixels: PixelAccess
    private var frozen: CIImage?
    private var isFrozen = false

    public init(canvas: CGSize, pixels: PixelAccess) {
        self.canvas = canvas
        self.pixels = pixels
    }

    public func setValues(_ values: [String: EffectValue]) {
        isFrozen = Self.freeze.isOn(in: values)
        if !isFrozen { frozen = nil }
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        guard isFrozen else { return image }
        if let frozen { return frozen }
        // The frame is copied out into plain bytes, because the camera
        // reuses its own buffers and would otherwise change it.
        let width = Int(canvas.width), height = Int(canvas.height)
        let held = pixels.image(rgba: pixels.rgba(of: image, width: width, height: height), width: width, height: height)
        frozen = held
        return held
    }
}

public extension NativeEffect {
    /// A switch that holds the picture still.
    static func freezeFrame(pixels: PixelAccess) -> NativeEffect {
        NativeEffect(name: FreezeFrameEffect.name, kind: .filter, parameters: FreezeFrameEffect.parameters) {
            FreezeFrameEffect(canvas: $0, pixels: pixels)
        }
    }
}
