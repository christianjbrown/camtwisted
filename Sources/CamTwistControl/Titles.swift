import CamTwistCore
import Foundation

// How steps and sources are named in lists and in scripts.

extension ChainItem {
    /// What the step is called in the list.
    public var title: String {
        switch content {
        case .effect(let name, _): return EffectNaming.title(for: name)
        case .source(let spec): return spec.title
        case .script: return "AppleScript"
        }
    }
}

extension ChainItem {
    /// What scripts call the step: an effect goes by its own name, which
    /// stays the same whatever it is shown as.
    public var scriptName: String {
        if case .effect(let name, _) = content { return name }
        return title
    }
}

extension SourceSpec {
    /// What a step showing the source is called: its kind's own answer.
    public var title: String { kind.title }
}

extension ShapeKind {
    /// What the shape is called: its outline's own name.
    public var label: String { ShapeOutlines.outline(for: self).name }
}
