import Foundation

/// Everything the app offers without any file: the effects and transitions
/// that are its own code. Files in the effects folder come on top.
public enum BuiltInEffects {
    /// The built-in effects.
    ///
    /// - Parameters:
    ///   - directory: the folder shown to the user as the effects folder.
    ///   - supplies: what the effects need of the system.
    public static func library(directory: URL, tuning: EffectTuning, supplies: RenderingSupplies) -> NativeEffectLibrary {
        let pixels = supplies.pixels
        let seed = supplies.seed
        return NativeEffectLibrary(directory: directory, effects: [
            .bump,
            .badTV,
            .comicBook,
            .charcoalSketch,
            .clock(now: supplies.now),
            .countdown,
            .halo,
            .badConnection,
            .headline,
            .solidShape,
            .thoughtBubble,
            .pillarBox,
            .letterBox,
            .freezeFrame(pixels: pixels),
            .flame(pixels: pixels, seed: seed),
            .matrix(pixels: pixels, seed: seed),
            .liveCaptions(listener: supplies.speech, now: supplies.now),
        ]
            + NativeEffect.studioFilters + NativeEffect.looks + NativeEffect.classicFilters
            + NativeEffect.motionFilters + NativeEffect.skyEffects + NativeEffect.textEffects
            + NativeEffect.backgrounds(masker: supplies.makeMasker)
            + NativeEffect.characters(tuning: tuning, tracker: supplies.makeFaceTracker)
            + NativeEffect.timeEffects(pixels: pixels, tuning: tuning)
            + [.lut])
    }

    /// The built-in transitions, listed like effects.
    public static func transitionLibrary(directory: URL) -> NativeTransitionLibrary {
        NativeTransitionLibrary(directory: directory)
    }
}
