import CoreVideo

/// Somewhere finished frames go.
public protocol FrameSink: AnyObject {
    func send(_ pixelBuffer: CVPixelBuffer)
}
