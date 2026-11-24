import CamTwistCore
import CoreGraphics
import CoreImage

/// A test card: a grid, a circle, colour bars and a grey scale, for lining
/// things up and checking colour. The design is this app's own.
public final class TestCardSource: FrameSource {
    private enum Design {
        static let gridLines = 16
        static let lineWidth: CGFloat = 0.0025
        static let circleRadius: CGFloat = 0.42
        static let barsWidth: CGFloat = 0.5
        static let barsHeight: CGFloat = 0.3
        static let greySteps = 8
        static let greyHeight: CGFloat = 0.1
        static let labelSize: CGFloat = 0.06
        static let fontName = "Helvetica-Bold"
        static let backgroundGrey: CGFloat = 0.35
        static let circleGrey: CGFloat = 0.5
        /// The label sits this many label heights below the grey steps, in a box this many tall.
        static let labelGap: CGFloat = 2
        static let labelBoxHeight: CGFloat = 1.5
    }

    private let image: CIImage?

    public init(canvas: CGSize = CameraContract.size, label: String = CameraContract.deviceName) {
        image = CanvasDrawing.image(size: canvas) { context in
            Self.draw(in: context, canvas: canvas, label: label)
        }
    }

    public func start() {}
    public func stop() {}
    public var latestFrame: CIImage? { image }
    public func update(to spec: SourceSpec) -> Bool { spec == .testCard }

    private static func draw(in context: CGContext, canvas: CGSize, label: String) {
        let bounds = CGRect(origin: .zero, size: canvas)
        context.setFillColor(CGColor(gray: Design.backgroundGrey, alpha: 1))
        context.fill(bounds)

        // A square grid, for checking geometry.
        let cell = canvas.width / CGFloat(Design.gridLines)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(canvas.width * Design.lineWidth)
        var x = cell / 2
        while x < canvas.width {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: canvas.height))
            x += cell
        }
        var y = canvas.height / 2 - cell * (canvas.height / 2 / cell).rounded(.down)
        while y < canvas.height {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: canvas.width, y: y))
            y += cell
        }
        context.strokePath()

        // A circle, which only looks round when the picture's shape is right.
        let radius = canvas.height * Design.circleRadius
        let circle = CGRect(x: bounds.midX - radius, y: bounds.midY - radius, width: radius * 2, height: radius * 2)
        context.saveGState()
        context.addEllipse(in: circle)
        context.clip()
        context.setFillColor(CGColor(gray: Design.circleGrey, alpha: 1))
        context.fill(circle)

        let barsWidth = canvas.width * Design.barsWidth
        let barsHeight = canvas.height * Design.barsHeight
        let bars = CGRect(x: bounds.midX - barsWidth / 2, y: bounds.midY, width: barsWidth, height: barsHeight)
        for bar in ColorBars.bars(in: bars.size) {
            context.setFillColor(CGColor(srgbRed: bar.color.red, green: bar.color.green, blue: bar.color.blue, alpha: 1))
            context.fill(bar.frame.offsetBy(dx: bars.minX, dy: bars.minY))
        }

        // Steps from black to white, for checking brightness and contrast.
        let greyHeight = canvas.height * Design.greyHeight
        let stepWidth = barsWidth / CGFloat(Design.greySteps)
        for step in 0..<Design.greySteps {
            context.setFillColor(CGColor(gray: CGFloat(step) / CGFloat(Design.greySteps - 1), alpha: 1))
            context.fill(CGRect(
                x: bars.minX + CGFloat(step) * stepWidth, y: bounds.midY - greyHeight,
                width: stepWidth, height: greyHeight
            ))
        }
        context.restoreGState()
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.strokeEllipse(in: circle)

        let labelSize = canvas.height * Design.labelSize
        CanvasDrawing.draw(
            label,
            in: CGRect(x: 0, y: bounds.midY - greyHeight - labelSize * Design.labelGap, width: canvas.width, height: labelSize * Design.labelBoxHeight),
            fontName: Design.fontName, fontSize: labelSize, color: CGColor(gray: 1, alpha: 1), context: context
        )
    }
}

public struct TestCardSourceProvider: SourceProvider {
    public init() {}

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        spec == .testCard ? TestCardSource() : nil
    }
}
