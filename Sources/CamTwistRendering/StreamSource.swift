import AVFoundation
import CamTwistCore
import CoreImage

/// A stream from an address as a source: an HLS live stream, or a video
/// file played from a server or from disk.
public final class StreamSource: FrameSource, SoundSource {
    private let listener = Locked<((CMSampleBuffer) -> Void)?>(nil)

    /// Where the stream's sound is heard. A video file's is; a live
    /// stream's cannot be listened to this way, and is only played.
    public var onSound: ((CMSampleBuffer) -> Void)? {
        get { listener.get() }
        set { listener.set(newValue) }
    }

    private let settings: Locked<StreamSettings>
    private let player = AVPlayer()
    private let frames = LatestFrameBox()
    private var output: AVPlayerItemVideoOutput?

    public init(settings: StreamSettings) {
        self.settings = Locked(settings)
    }

    public var latestFrame: CIImage? {
        if let output {
            let time = player.currentTime()
            if output.hasNewPixelBuffer(forItemTime: time),
               let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                frames.store(CIImage(cvPixelBuffer: buffer))
            }
        }
        return frames.load()
    }

    public func start() {
        let settings = settings.get()
        guard output == nil, let url = StreamAddress.url(from: settings.address) else { return }
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        self.output = output
        PlayerSoundTap.attach(to: item) { [weak self] in self?.listener.get()?($0) }
        player.volume = Float(settings.volume)
        player.replaceCurrentItem(with: item)
        player.play()
    }

    public func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        output = nil
        frames.store(nil)
    }

    /// A change of volume is taken as it plays; a new address needs a new source.
    public func update(to spec: SourceSpec) -> Bool {
        guard case .stream(let new) = spec, new.address == settings.get().address else { return false }
        settings.set(new)
        player.volume = Float(new.volume)
        return true
    }
}

public struct StreamSourceProvider: SourceProvider {
    public init() {}

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .stream(let settings) = spec else { return nil }
        return StreamSource(settings: settings)
    }
}
