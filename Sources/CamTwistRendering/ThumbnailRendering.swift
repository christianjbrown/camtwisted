import CamTwistCore
import CoreVideo

/// Something that can draw one frame of a scene to the side, for a small
/// picture of it.
public protocol ThumbnailRendering: AnyObject {
    /// Asks for a frame of a scene. False when one is already being drawn.
    func captureThumbnail(of scene: SceneConfiguration, completion: @escaping (CVPixelBuffer?) -> Void) -> Bool
}

extension RenderLoop: ThumbnailRendering {}
