import CamTwistCore
import CamTwistRendering
import Foundation

/// The controls of each effect, asked of the library once and remembered.
final class EffectParameters {
    private let library: EffectLibrary
    private var cache: [String: [EffectParameter]] = [:]

    init(library: EffectLibrary) {
        self.library = library
    }

    func parameters(forEffectNamed name: String) -> [EffectParameter] {
        if let cached = cache[name] { return cached }
        let parameters = library.parameters(forEffectNamed: name)
        // An empty answer may only mean the effect was not found yet.
        if !parameters.isEmpty {
            cache[name] = parameters
        }
        return parameters
    }
}
