import AppKit
import CamTwistRendering
import CoreVideo
import SwiftUI

/// Shows finished frames in the window.
final class PreviewSink: FrameSink {
    /// A scale of minus one turns the picture over, left to right.
    private static let flipped: CGFloat = -1
    private static let unscaled: CGFloat = 1

    /// The queue the layer is changed on, which must be the main one.
    private let main: DispatchQueue

    init(main: DispatchQueue) {
        self.main = main
    }

    let layer: CALayer = {
        let layer = CALayer()
        layer.contentsGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }()

    /// Flips the picture left to right, as a mirror would. Only the monitor
    /// is flipped; what the camera sends is unchanged.
    var isMirrored = false {
        didSet {
            layer.setAffineTransform(isMirrored ? CGAffineTransform(scaleX: Self.flipped, y: Self.unscaled) : .identity)
        }
    }

    func send(_ pixelBuffer: CVPixelBuffer) {
        guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return }
        main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer.contents = surface
            CATransaction.commit()
        }
    }
}

struct PreviewView: NSViewRepresentable {
    let sink: PreviewSink

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.addSublayer(sink.layer)
        sink.layer.frame = view.bounds
        sink.layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        sink.layer.frame = nsView.bounds
    }
}
