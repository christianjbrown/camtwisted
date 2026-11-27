import Foundation

/// What the built-in effects and the renderers need of the system: its
/// pixels, its clock, its dice, and its finders of people and faces. They
/// are handed in, so no effect reaches for one itself.
public struct RenderingSupplies {
    /// Reads and writes a picture's pixels, for the effects that need to.
    public let pixels: PixelAccess
    /// A fresh non-zero seed for each effect that draws at random.
    let seed: () -> UInt32
    /// The time now, for the effects that show it.
    let now: () -> Date
    /// Makes what finds the person in a picture.
    let makeMasker: () -> PersonMasking
    /// Makes what finds the face in a picture.
    let makeFaceTracker: () -> FaceTracking
    /// Writes down what is said, for captions. One for the whole app.
    let speech: SharedSpeechListener

    /// Zero is not a usable seed for the generators, so the range starts at one.
    private static let seeds: ClosedRange<UInt32> = 1...UInt32.max

    init(
        pixels: PixelAccess, seed: @escaping () -> UInt32, now: @escaping () -> Date,
        makeMasker: @escaping () -> PersonMasking, makeFaceTracker: @escaping () -> FaceTracking,
        speech: SharedSpeechListener
    ) {
        self.pixels = pixels
        self.seed = seed
        self.now = now
        self.makeMasker = makeMasker
        self.makeFaceTracker = makeFaceTracker
        self.speech = speech
    }

    /// The system's own, which is what the app runs with.
    ///
    /// - Parameter speech: what captions listen through. The app hands in
    ///   the Mac's own; left out, captions hear nothing.
    public static func system(speech: SharedSpeechListener = .silent) -> RenderingSupplies {
        RenderingSupplies(
            pixels: CoreImagePixelAccess(context: RenderingSystem.makeContext()),
            seed: { UInt32.random(in: seeds) },
            now: Date.init,
            makeMasker: { VisionPersonMasker() },
            makeFaceTracker: { VisionFaceTracker() },
            speech: speech
        )
    }
}
