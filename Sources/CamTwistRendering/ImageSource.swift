import CamTwistCore
import CoreImage
import Foundation

/// One picture file as a source. Clear parts of the picture stay clear, so
/// a logo with a transparent background sits over whatever is behind it.
public final class ImageSource: FrameSource {
    private let path: String
    private let image: CIImage?

    public init(path: String) {
        self.path = path
        image = path.isEmpty
            ? nil
            : CIImage(contentsOf: URL(fileURLWithPath: path), options: [.applyOrientationProperty: true])
    }

    public func start() {}
    public func stop() {}
    public var latestFrame: CIImage? { image }
    public func update(to spec: SourceSpec) -> Bool { spec == .image(path: path) }
}

public struct ImageSourceProvider: SourceProvider {
    public init() {}

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .image(let path) = spec else { return nil }
        return ImageSource(path: path)
    }
}
