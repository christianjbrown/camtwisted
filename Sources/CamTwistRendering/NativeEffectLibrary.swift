import CamTwistCore
import CoreImage
import Foundation

/// An effect built into the app rather than loaded from a file.
public struct NativeEffect {
    public let name: String
    public let kind: EffectKind
    public let parameters: [EffectParameter]
    public let make: (CGSize) -> ImageEffect

    public init(
        name: String,
        kind: EffectKind,
        parameters: [EffectParameter],
        make: @escaping (CGSize) -> ImageEffect
    ) {
        self.name = name
        self.kind = kind
        self.parameters = parameters
        self.make = make
    }
}

/// The built-in effects, presented like any other effect library.
public final class NativeEffectLibrary: EffectLibrary, ImageEffectFactory {
    public let directory: URL
    private let effects: [NativeEffect]

    public init(directory: URL, effects: [NativeEffect]) {
        self.directory = directory
        self.effects = effects
    }

    public func availableEffects() -> [EffectListing] {
        effects.map { EffectListing(name: $0.name, kind: $0.kind) }
    }

    public func parameters(forEffectNamed name: String) -> [EffectParameter] {
        effects.first { $0.name == name }?.parameters ?? []
    }

    public func makeEffect(named name: String, canvas: CGSize) -> ImageEffect? {
        effects.first { $0.name == name }?.make(canvas)
    }
}

public extension NativeEffect {
    /// Fire rising from the edges in the picture.
    static func flame(pixels: PixelAccess, seed: @escaping () -> UInt32) -> NativeEffect {
        NativeEffect(name: FlameEffect.name, kind: .filter, parameters: FlameEffect.parameters) {
            FlameEffect(canvas: $0, pixels: pixels, seed: seed())
        }
    }

    /// The picture as falling green code.
    static func matrix(pixels: PixelAccess, seed: @escaping () -> UInt32) -> NativeEffect {
        // The glyphs are drawn once and shared: they never change.
        let font = DrawnMatrixFont.make()
        return NativeEffect(name: MatrixEffect.name, kind: .filter, parameters: MatrixEffect.parameters) {
            MatrixEffect(canvas: $0, pixels: pixels, font: font, seed: seed())
        }
    }
}
