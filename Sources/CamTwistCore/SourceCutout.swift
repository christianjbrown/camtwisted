import Foundation

/// What is taken out of one source's own picture, leaving it clear there so
/// whatever is beneath the source shows through.
public struct SourceCutout: Codable, Equatable, Sendable {
    /// Whether everything but the people in the picture is taken away.
    public var removesBackground: Bool
    /// The colour keyed out, and how. Nil keys nothing.
    public var chromaKey: ChromaKeySettings?

    public init(removesBackground: Bool = false, chromaKey: ChromaKeySettings? = nil) {
        self.removesBackground = removesBackground
        self.chromaKey = chromaKey
    }

    /// Whether the picture comes out exactly as it went in.
    public var isNeutral: Bool { self == SourceCutout() }
}

public extension SourceSpec {
    /// Whether the source brings a picture from outside that can have a
    /// background to take away. What the app draws itself, and a
    /// microphone, cannot.
    var canBeCutOut: Bool {
        kind.canBeCutOut
    }
}

public extension SceneConfiguration {
    /// Whether a camera is anywhere in the scene, branches included.
    var hasCamera: Bool {
        allItems.contains { $0.source?.kind.isCamera == true }
    }
}
