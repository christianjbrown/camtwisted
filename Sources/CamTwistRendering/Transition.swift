import CamTwistCore
import CoreImage

/// Blends from one picture to another as progress goes from 0 to 1.
public protocol TransitionEffect: AnyObject {
    func blend(from: CIImage, to: CIImage, progress: Double, time: TimeInterval) -> CIImage
}

/// Makes transitions by name. Nil means the name is unknown.
public protocol TransitionFactory {
    func makeTransition(named name: String, canvas: CGSize) -> TransitionEffect?
}

/// A plain cross fade, always available.
public final class DissolveTransition: TransitionEffect {
    public static let name = "Dissolve"
    private static let filterName = CIFilterName.dissolveTransition

    public init() {}

    public func blend(from: CIImage, to: CIImage, progress: Double, time: TimeInterval) -> CIImage {
        from.applyingFilter(Self.filterName, parameters: [
            kCIInputTargetImageKey: to,
            kCIInputTimeKey: progress,
        ])
    }
}

/// A transition under way: where it is going and how far along it is.
struct RunningTransition {
    let target: SceneConfiguration
    let effect: TransitionEffect
    let startTime: TimeInterval
    let duration: TimeInterval

    func progress(at time: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(max((time - startTime) / duration, 0), 1)
    }
}
