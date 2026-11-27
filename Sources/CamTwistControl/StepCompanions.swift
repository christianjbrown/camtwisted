import CamTwistCore
import CamTwistRendering
import Foundation

/// Steps that come along with a new one, so it works as soon as it is added.
protocol StepCompanions {
    /// What goes in just above a new step, given the steps that would sit
    /// above it in its list.
    func companions(for content: ChainItem.Content, above: [ChainItem]) -> [ChainItem.Content]
}

/// Live Captions write down what the sources above them say. Added where
/// nothing above them is heard, they bring a Microphone along, just above
/// them, so there is something to write down. A camera does not count: the
/// Mac's own camera has no microphone of its own.
struct CaptionsMicrophone: StepCompanions {
    func companions(for content: ChainItem.Content, above: [ChainItem]) -> [ChainItem.Content] {
        guard case .effect(let name, _) = content, name == LiveCaptionsEffect.name,
              !above.contains(where: Self.isHeard) else { return [] }
        return [.source(.microphone(deviceID: nil))]
    }

    private static func isHeard(_ item: ChainItem) -> Bool {
        guard item.isEnabled, let spec = item.source else { return false }
        if case .camera = spec { return false }
        return (SceneSound.level(of: item) ?? SceneSound.silent) > SceneSound.silent
    }
}
