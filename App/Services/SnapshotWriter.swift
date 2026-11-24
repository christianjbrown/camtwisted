import AppKit
import CamTwistControl
import CamTwistCore
import CoreImage
import CoreVideo

/// Writes the picture to a PNG file named for the moment it was taken.
struct PNGSnapshotWriter: SnapshotWriting {
    /// What turns the picture into a file.
    let context: CIContext
    /// The disk, for making the folder the file goes in.
    let files: FileManager
    /// The time now, which the file is named for.
    let clock: () -> Date

    func write(_ pixelBuffer: CVPixelBuffer, to directory: URL) -> URL? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let url = directory
            .appendingPathComponent(SnapshotName.baseName(at: clock()))
            .appendingPathExtension(SnapshotName.fileExtension)
        do {
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            try context.writePNGRepresentation(of: image, to: url, format: .RGBA8, colorSpace: colorSpace)
            return url
        } catch {
            return nil
        }
    }
}
