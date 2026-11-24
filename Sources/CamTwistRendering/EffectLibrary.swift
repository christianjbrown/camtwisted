import CamTwistCore
import Foundation

/// An effect the user can switch on.
public struct EffectListing: Identifiable, Equatable {
    public let name: String
    public let kind: EffectKind

    public init(name: String, kind: EffectKind) {
        self.name = name
        self.kind = kind
    }

    public var id: String { name }
}

/// What the interface needs to know about the installed effects.
public protocol EffectLibrary {
    var directory: URL { get }
    func availableEffects() -> [EffectListing]
    func parameters(forEffectNamed name: String) -> [EffectParameter]
}
