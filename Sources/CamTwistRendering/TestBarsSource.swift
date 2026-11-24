import CamTwistCore
import CoreImage

/// The colour bar test pattern as a source.
public final class TestBarsSource: FrameSource {
    private let image: CIImage

    public init(canvas: CGSize = CameraContract.size) {
        image = ColorBars.bars(in: canvas).reduce(CIImage.empty()) { result, bar in
            let color = CIColor(red: bar.color.red, green: bar.color.green, blue: bar.color.blue)
            return CIImage(color: color).cropped(to: bar.frame).composited(over: result)
        }
    }

    public func start() {}
    public func stop() {}
    public var latestFrame: CIImage? { image }
    public func update(to spec: SourceSpec) -> Bool { spec == .colorBars }
}

public struct ColorBarsSourceProvider: SourceProvider {
    public init() {}

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        spec == .colorBars ? TestBarsSource() : nil
    }
}
