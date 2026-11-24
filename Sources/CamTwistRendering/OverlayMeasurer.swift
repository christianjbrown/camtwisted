import CamTwistCore
import CoreImage
import Foundation

/// Finds the part of the picture an effect draws on, by running it over
/// nothing and seeing what is no longer clear. The box round a selected
/// overlay is drawn from this, so it fits a clock or a headline as shown.
public final class OverlayMeasurer {
    private enum Tuning {
        /// The width the picture is read at: enough to place a box.
        static let sampleWidth = 320
        /// Anything fainter than this counts as clear.
        static let faintestAlpha: UInt8 = 8
    }

    private let factory: ImageEffectFactory
    private let pixels: PixelAccess
    private let canvas: CGSize
    /// The last answer for each effect, kept until its controls change.
    private var kept: [String: (values: [String: EffectValue], bounds: CGRect?)] = [:]

    public init(factory: ImageEffectFactory, pixels: PixelAccess, canvas: CGSize) {
        self.factory = factory
        self.pixels = pixels
        self.canvas = canvas
    }

    /// Where the effect draws, in fractions of the picture with its origin
    /// at the bottom left, or nil when it draws nothing of its own.
    public func bounds(ofEffectNamed name: String, values: [String: EffectValue]) -> CGRect? {
        if let known = kept[name], known.values == values { return known.bounds }
        let bounds = measured(name: name, values: values)
        kept[name] = (values, bounds)
        return bounds
    }

    private func measured(name: String, values: [String: EffectValue]) -> CGRect? {
        guard let effect = factory.makeEffect(named: name, canvas: canvas) else { return nil }
        effect.setValues(values)
        let frame = CGRect(origin: .zero, size: canvas)
        let nothing = CIImage(color: .clear).cropped(to: frame)
        let drawn = effect.apply(to: nothing, time: 0).cropped(to: frame).composited(over: nothing)
        let width = Tuning.sampleWidth
        let height = Int((CGFloat(width) * canvas.height / canvas.width).rounded())
        return AlphaBounds.unitRect(
            rgba: pixels.rgba(of: drawn, width: width, height: height), width: width, height: height,
            faintestAlpha: Tuning.faintestAlpha
        )
    }
}

/// The box round everything in a picture that is not clear.
enum AlphaBounds {
    private static let bytesPerPixel = 4
    private static let alphaOffset = 3

    /// - Parameter rgba: red, green, blue, alpha bytes with the first row at the top.
    /// - Returns: the box in fractions of the picture with its origin at the
    ///   bottom left, or nil when the whole picture is clear.
    static func unitRect(rgba: [UInt8], width: Int, height: Int, faintestAlpha: UInt8) -> CGRect? {
        var columns: ClosedRange<Int>?
        var rows: ClosedRange<Int>?
        for row in 0..<height {
            for column in 0..<width where rgba[(row * width + column) * bytesPerPixel + alphaOffset] >= faintestAlpha {
                columns = columns.map { min($0.lowerBound, column)...max($0.upperBound, column) } ?? column...column
                rows = rows.map { $0.lowerBound...row } ?? row...row
            }
        }
        guard let columns, let rows else { return nil }
        return CGRect(
            x: CGFloat(columns.lowerBound) / CGFloat(width),
            y: 1 - CGFloat(rows.upperBound + 1) / CGFloat(height),
            width: CGFloat(columns.count) / CGFloat(width), height: CGFloat(rows.count) / CGFloat(height)
        )
    }
}
