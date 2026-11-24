import CoreImage

/// Runs a built-in Core Image filter and hands back its picture.
enum FilterOutput {
    /// The filter's picture, or the fallback when the system has no filter
    /// by that name or it produces nothing.
    static func image(named name: String, parameters: [String: Any], fallback: CIImage) -> CIImage {
        CIFilter(name: name, parameters: parameters)?.outputImage ?? fallback
    }
}
