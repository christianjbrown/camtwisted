import Foundation

/// A supply of random numbers. Injected so the effects that use chance can
/// be run with a fixed seed in tests.
public protocol RandomSource {
    mutating func next() -> UInt32
}

/// A small, fast generator: plenty for visual noise.
public struct XorShiftRandom: RandomSource {
    /// A seed of zero would produce nothing but zeros.
    private static let fallbackSeed: UInt32 = 0x9E37_79B9

    /// The xorshift32 shift amounts: left, right, left.
    private static let firstShift: UInt32 = 13
    private static let secondShift: UInt32 = 17
    private static let thirdShift: UInt32 = 5

    private var state: UInt32

    public init(seed: UInt32) {
        state = seed == 0 ? Self.fallbackSeed : seed
    }

    public mutating func next() -> UInt32 {
        state ^= state << Self.firstShift
        state ^= state >> Self.secondShift
        state ^= state << Self.thirdShift
        return state
    }
}

extension RandomSource {
    /// A number from zero up to, but not including, `bound`.
    mutating func below(_ bound: Int) -> Int {
        bound > 0 ? Int(next() % UInt32(bound)) : 0
    }
}
