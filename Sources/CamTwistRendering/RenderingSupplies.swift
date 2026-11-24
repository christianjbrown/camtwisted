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

    /// Zero is not a usable seed for the generators, so the range starts at one.
    private static let seeds: ClosedRange<UInt32> = 1...UInt32.max

    init(
        pixels: PixelAccess, seed: @escaping () -> UInt32, now: @escaping () -> Date,
        makeMasker: @escaping () -> PersonMasking, makeFaceTracker: @escaping () -> FaceTracking
    ) {
        self.pixels = pixels
        self.seed = seed
        self.now = now
        self.makeMasker = makeMasker
        self.makeFaceTracker = makeFaceTracker
    }

    /// The system's own, which is what the app runs with.
    public static func system() -> RenderingSupplies {
        RenderingSupplies(
            pixels: CoreImagePixelAccess(context: RenderingSystem.makeContext()),
            seed: { UInt32.random(in: seeds) },
            now: Date.init,
            makeMasker: { VisionPersonMasker() },
            makeFaceTracker: { VisionFaceTracker() }
        )
    }
}
