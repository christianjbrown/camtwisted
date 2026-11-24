import Foundation

/// The picture heights on offer to every output that encodes a picture:
/// the streams and the recording all choose from this one list.
public enum PictureHeight {
    public static let all = [360, 480, 540, hd, fullHD, 1440, ultraHD]

    /// The height of an HD picture, which a new stream starts at.
    public static let hd = 720
    /// The height of a Full HD picture, which is what the app draws unless
    /// something asks for more. The heights the app can draw at are its
    /// drawing sizes', so the two lists cannot drift apart.
    public static let fullHD = DrawingSize.fullHD.height
    public static let ultraHD = DrawingSize.ultraHD.height

    /// The heights that go by a name of their own.
    private static let named = [fullHD: "1080p (Full HD)", ultraHD: "4K"]
    private static let suffix = "p"

    /// What a height is called in a list of them, such as "720p".
    public static func label(for height: Int) -> String {
        named[height] ?? "\(height)\(suffix)"
    }

    /// The size of a picture so many pixels high on a canvas of some shape.
    /// The width is made even, as video encoders need.
    public static func size(height: Int, canvasAspect: Double) -> (width: Int, height: Int) {
        let width = Int((Double(height) * canvasAspect).rounded())
        return (width + width % 2, height)
    }
}

/// A picture an output encodes: whether the output is switched on, and
/// how many pixels high it wants its picture.
public struct PictureDemand: Equatable, Sendable {
    public var isOn: Bool
    public var height: Int

    public init(isOn: Bool, height: Int) {
        self.isOn = isOn
        self.height = height
    }
}

/// Decides how much detail the picture is drawn with from what the
/// outputs ask for, so nobody has to choose it.
public struct DrawingSizeRule: Sendable {
    /// The sizes the picture can be drawn at, smallest first.
    private let ladder: [DrawingSize]

    public init(sizes: [DrawingSize] = DrawingSize.allCases) {
        ladder = sizes.sorted { $0.height < $1.height }
    }

    /// The smallest size at least as tall as the tallest picture any output
    /// that is switched on wants, or the largest when none is tall enough.
    /// With nothing switched on, the smallest.
    public func size(for demands: [PictureDemand]) -> DrawingSize {
        let tallest = demands.filter(\.isOn).map(\.height).max() ?? .zero
        return ladder.first { $0.height >= tallest } ?? ladder.last ?? .fullHD
    }
}
