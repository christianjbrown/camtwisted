import CamTwistCore
import CoreImage
import Foundation

/// Grades the picture with a colour look-up table from a `.cube` file, the
/// format colour grading tools and other streaming software share.
public final class LUTEffect: ImageEffect {
    public static let name = "Apply LUT"
    public static let fileKey = "File"
    public static let amountKey = "Amount"
    public static let fileTypes = ["cube"]

    private static let cubeFilter = CIFilterName.colorCube
    private static let cubeDimensionKey = CIInputKey.cubeDimension
    private static let cubeDataKey = CIInputKey.cubeData
    private static let mixFilter = CIFilterName.dissolveTransition
    private static let fullAmount = 1.0

    public static let parameters = [
        EffectParameter(
            key: fileKey, displayName: "LUT file", kind: .string, defaultValue: .string(""), fileTypes: fileTypes
        ),
        EffectParameter(
            key: amountKey, displayName: "Amount", kind: .number, defaultValue: .number(fullAmount), range: 0...fullAmount
        ),
    ]

    private let read: (String) -> String?
    private var values: [String: EffectValue] = [:]
    /// The table for the file it was read from, or nil when that file is no table.
    private var loaded: (path: String, cube: (size: Int, data: Data)?)?

    /// - Parameter read: reads a file's text, or nil when it cannot be read.
    public init(read: @escaping (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }) {
        self.read = read
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        let path = values.string(Self.fileKey, default: "")
        // The file is only read again when another is chosen.
        if loaded?.path != path {
            let table = read(path).flatMap(CubeLUT.init(text:))?.fittingCoreImage
            loaded = (path, table.map { table in
                (table.size, table.values.withUnsafeBufferPointer { Data(buffer: $0) })
            })
        }
        guard let cube = loaded?.cube else { return image }
        let graded = image.applyingFilter(Self.cubeFilter, parameters: [
            Self.cubeDimensionKey: cube.size, Self.cubeDataKey: cube.data,
        ])
        let amount = values.number(Self.amountKey, default: Self.fullAmount)
        guard amount < Self.fullAmount else { return graded }
        // Part way, the graded picture is mixed with the one that came in.
        return image.applyingFilter(Self.mixFilter, parameters: [
            kCIInputTargetImageKey: graded, kCIInputTimeKey: max(amount, 0),
        ])
    }
}

public extension NativeEffect {
    /// A colour grade from a `.cube` look-up table.
    static var lut: NativeEffect {
        NativeEffect(name: LUTEffect.name, kind: .filter, parameters: LUTEffect.parameters) { _ in LUTEffect() }
    }
}
