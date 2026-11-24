import CamTwistCore
import CoreGraphics
import CoreImage

/// Freehand drawing over the picture, as a source with a clear background.
public final class TelestratorSource: FrameSource {
    private static let bitsPerComponent = 8
    private static let opaque: CGFloat = 1

    private let canvas: CGSize
    private let lock = NSLock()
    private var settings: TelestratorSettings
    private var rendered: CIImage?

    public init(settings: TelestratorSettings, canvas: CGSize = CameraContract.size) {
        self.settings = settings
        self.canvas = canvas
    }

    public func start() {}
    public func stop() {}

    public var latestFrame: CIImage? {
        lock.lock()
        defer { lock.unlock() }
        if rendered == nil {
            rendered = Self.draw(settings.strokes, canvas: canvas)
        }
        return rendered
    }

    public func update(to spec: SourceSpec) -> Bool {
        guard case .telestrator(let new) = spec else { return false }
        lock.lock()
        if new.strokes != settings.strokes {
            rendered = nil
        }
        settings = new
        lock.unlock()
        return true
    }

    private static func draw(_ strokes: [DrawingStroke], canvas: CGSize) -> CIImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(canvas.width),
            height: Int(canvas.height),
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: SRGBColorSpace.shared,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            context.setStrokeColor(
                red: stroke.color.red, green: stroke.color.green, blue: stroke.color.blue, alpha: opaque
            )
            context.setLineWidth(stroke.width * canvas.width)
            context.move(to: CGPoint(x: first.x * canvas.width, y: first.y * canvas.height))
            // A single point still leaves a dot.
            for point in stroke.points.count > 1 ? Array(stroke.points.dropFirst()) : [first] {
                context.addLine(to: CGPoint(x: point.x * canvas.width, y: point.y * canvas.height))
            }
            context.strokePath()
        }
        return context.makeImage().map { CIImage(cgImage: $0) }
    }
}

public struct TelestratorSourceProvider: SourceProvider {
    public init() {}

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .telestrator(let settings) = spec else { return nil }
        return TelestratorSource(settings: settings)
    }
}
