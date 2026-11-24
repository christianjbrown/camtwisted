import CamTwistCore
import CoreImage
import Foundation
import Vision

/// Finds faces with the system's own face finder.
final class VisionFaceTracker: FaceTracking {
    private let request = VNDetectFaceLandmarksRequest()

    func face(in image: CIImage) -> FaceLandmarks? {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        // With several people in the picture, the nearest one is followed.
        guard (try? handler.perform([request])) != nil,
              let face = request.results?.max(by: { $0.boundingBox.height < $1.boundingBox.height }),
              let marks = face.landmarks,
              let leftEye = marks.leftEye, let rightEye = marks.rightEye,
              let leftBrow = marks.leftEyebrow, let rightBrow = marks.rightEyebrow,
              let nose = marks.nose, let outerLips = marks.outerLips, let innerLips = marks.innerLips
        else { return nil }

        let extent = image.extent
        func points(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
            region.pointsInImage(imageSize: extent.size).map { CGPoint(x: $0.x + extent.minX, y: $0.y + extent.minY) }
        }
        return FaceLandmarks(
            box: VNImageRectForNormalizedRect(face.boundingBox, Int(extent.width), Int(extent.height))
                .offsetBy(dx: extent.minX, dy: extent.minY),
            eyes: [points(leftEye), points(rightEye)],
            brows: [points(leftBrow), points(rightBrow)],
            nose: points(nose),
            outerLips: points(outerLips),
            innerLips: points(innerLips)
        )
    }
}
