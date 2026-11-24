import CamTwistControl
import CamTwistCore
import CamTwistRendering
import CoreImage
import Foundation

/// Takes small pictures of scenes with the render loop and shrinks them
/// to the size a tile needs.
final class SceneThumbnailCapture: SceneThumbnailCapturing {
    private let renderLoop: ThumbnailRendering
    private let context: CIContext

    init(renderLoop: ThumbnailRendering, context: CIContext) {
        self.renderLoop = renderLoop
        self.context = context
    }

    func captureThumbnail(of scene: SceneConfiguration, completion: @escaping (CGImage?) -> Void) -> Bool {
        renderLoop.captureThumbnail(of: scene) { [context] buffer in
            guard let buffer else { return completion(nil) }
            let image = CIImage(cvPixelBuffer: buffer)
            let scale = ThumbnailScale.factor(forWidth: image.extent.width)
            let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            completion(context.createCGImage(small, from: small.extent))
        }
    }
}
