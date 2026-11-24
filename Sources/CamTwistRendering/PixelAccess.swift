import CoreImage
import Foundation

/// Reads pictures into plain bytes and makes pictures out of bytes, for the
/// effects that work pixel by pixel.
public protocol PixelAccess {
    /// The image shrunk or stretched to a size, as red, green, blue, alpha
    /// bytes with the first row at the top.
    func rgba(of image: CIImage, width: Int, height: Int) -> [UInt8]
    /// A picture from such bytes. Colours are taken as premultiplied.
    func image(rgba: [UInt8], width: Int, height: Int) -> CIImage
}

public final class CoreImagePixelAccess: PixelAccess {
    private static let bytesPerPixel = 4

    private let context: CIContext
    private let colorSpace = SRGBColorSpace.shared

    public init(context: CIContext) {
        self.context = context
    }

    public func rgba(of image: CIImage, width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * Self.bytesPerPixel)
        let extent = image.extent
        guard width > 0, height > 0, extent.width > 0, extent.height > 0, !extent.isInfinite else { return bytes }
        // Clamping first stops the picture's edge fading to clear when it is shrunk.
        let scaled = image
            .clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(
                scaleX: CGFloat(width) / extent.width, y: CGFloat(height) / extent.height
            ))
        context.render(
            scaled,
            toBitmap: &bytes,
            rowBytes: width * Self.bytesPerPixel,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        return bytes
    }

    public func image(rgba: [UInt8], width: Int, height: Int) -> CIImage {
        CIImage(
            bitmapData: Data(rgba),
            bytesPerRow: width * Self.bytesPerPixel,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }
}

extension CIImage {
    /// The image stretched to cover a canvas exactly.
    func stretched(to canvas: CGSize, smooth: Bool) -> CIImage {
        guard extent.width > 0, extent.height > 0 else { return self }
        let source = smooth ? self : samplingNearest()
        return source.transformed(by: CGAffineTransform(
            scaleX: canvas.width / extent.width, y: canvas.height / extent.height
        ))
    }
}
