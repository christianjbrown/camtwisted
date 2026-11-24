import CoreGraphics
import Foundation

/// Places content of one size inside a canvas of another, keeping its shape.
/// What a source that covers the picture does when its shape is not the
/// picture's own.
public enum SourceFit: String, Codable, CaseIterable, Sendable {
    /// Covers the whole picture; what overflows on two sides is cropped.
    case fill
    /// Shows all of itself, with bars on two sides.
    case fit
    /// Is pulled out of shape to cover the picture exactly.
    case stretch
}

public enum AspectFitter {
    /// Where content goes in a canvas it is to cover, in the way asked.
    public static func frame(for content: CGSize, in canvas: CGSize, fit: SourceFit) -> CGRect {
        switch fit {
        case .fill: return fill(content, in: canvas)
        case .fit: return self.fit(content, in: canvas)
        case .stretch: return CGRect(origin: .zero, size: canvas)
        }
    }

    /// The largest rectangle with the content's shape that fits inside the
    /// canvas, centred. Bars appear on two sides when the shapes differ.
    public static func fit(_ content: CGSize, in canvas: CGSize) -> CGRect {
        place(content, in: canvas, choosing: min)
    }

    /// The smallest rectangle with the content's shape that covers the whole
    /// canvas, centred. The overflow on two sides is cropped by the canvas.
    public static func fill(_ content: CGSize, in canvas: CGSize) -> CGRect {
        place(content, in: canvas, choosing: max)
    }

    private static func place(
        _ content: CGSize,
        in canvas: CGSize,
        choosing pick: (CGFloat, CGFloat) -> CGFloat
    ) -> CGRect {
        guard content.width > 0, content.height > 0 else {
            return CGRect(origin: .zero, size: canvas)
        }
        let scale = pick(canvas.width / content.width, canvas.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        let origin = CGPoint(
            x: (canvas.width - size.width) / halvingDivisor,
            y: (canvas.height - size.height) / halvingDivisor
        )
        return CGRect(origin: origin, size: size)
    }

    private static let halvingDivisor: CGFloat = 2
}
