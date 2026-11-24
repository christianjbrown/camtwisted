import CamTwistCore
import CoreGraphics
import CoreVideo
import Foundation

/// Draws what the camera shows while the host app is not sending frames.
protocol PlaceholderFrameProvider {
    func draw(into pixelBuffer: CVPixelBuffer)
}

/// Colour bars, the way a camera with nothing to show says it is there.
struct TestBarsFrameProvider: PlaceholderFrameProvider {
    private static let bitsPerComponent = 8
    private static let opaque: CGFloat = 1

    func draw(into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: Self.bitsPerComponent,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return }

        let canvas = CGSize(width: width, height: height)
        for bar in ColorBars.bars(in: canvas) {
            context.setFillColor(
                red: bar.color.red, green: bar.color.green, blue: bar.color.blue, alpha: Self.opaque
            )
            context.fill(bar.frame)
        }
    }
}
