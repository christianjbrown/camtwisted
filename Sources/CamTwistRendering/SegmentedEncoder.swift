import AVFoundation
import CamTwistCore
import CoreVideo
import Foundation

/// Turns frames into the pieces of a stream.
protocol SegmentEncoding: AnyObject {
    /// Adds a frame, at a time in seconds since the stream began.
    func append(_ pixelBuffer: CVPixelBuffer, at seconds: Double)
    /// Adds sound. `origin` is when the stream began, on the clock the
    /// sound is timed by, so the sound lands where it belongs in the stream.
    func appendSound(_ sound: CMSampleBuffer, startingFrom origin: Double)
    func finish()
}

/// Where an encoder's output goes: the header first, then each piece with
/// its length in seconds.
struct SegmentCallbacks {
    let initialization: (Data) -> Void
    let segment: (Data, Double) -> Void
}

/// How the stream is encoded.
public struct StreamEncoding: Equatable, Sendable {
    /// Seconds in each piece. Short pieces keep the delay down.
    public var segmentSeconds: Double
    public var bitsPerSecond: Int
    public var framesPerSecond: Int32
    public var codec: StreamCodec

    public static let standard = StreamEncoding(segmentSeconds: 1, bitsPerSecond: 4_000_000, framesPerSecond: 30)

    public init(segmentSeconds: Double, bitsPerSecond: Int, framesPerSecond: Int32, codec: StreamCodec = .h264) {
        self.segmentSeconds = segmentSeconds
        self.bitsPerSecond = bitsPerSecond
        self.framesPerSecond = framesPerSecond
        self.codec = codec
    }
}

/// Encodes frames as H.264 or HEVC in fragmented MP4, cut into pieces as it goes,
/// which is what both HLS and an endless MP4 are made of.
///
/// The system asks that a writer's delegate be safe to hand between
/// threads. This one is fed from one place, the stream it belongs to, and
/// the writer only calls back to pass a finished piece on.
final class SegmentedEncoder: NSObject, SegmentEncoding, AVAssetWriterDelegate, @unchecked Sendable {
    /// Times are counted in this many ticks a second.
    private static let timescale: CMTimeScale = 600
    /// Fine enough to place sound to the sample.
    private static let soundTimescale: CMTimeScale = 1_000_000_000

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let soundInput: AVAssetWriterInput?
    private let callbacks: SegmentCallbacks
    private let segmentSeconds: Double

    /// - Parameter sound: what the stream's sound is like, or nil for none.
    ///   A stream told to expect sound waits for it, so say so only when
    ///   sound is really arriving.
    init(size: CGSize, encoding: StreamEncoding, sound: SoundFormat?, callbacks: SegmentCallbacks) {
        self.callbacks = callbacks
        segmentSeconds = encoding.segmentSeconds
        writer = AVAssetWriter(contentType: .mpeg4Movie)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: Self.codecType(for: encoding.codec),
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: encoding.bitsPerSecond,
                // A key frame at the start of every piece, so each plays by itself.
                AVVideoMaxKeyFrameIntervalDurationKey: encoding.segmentSeconds,
                AVVideoExpectedSourceFrameRateKey: encoding.framesPerSecond,
                AVVideoAllowFrameReorderingKey: false,
            ] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = true
        soundInput = sound.map { format in
            AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channels,
                AVEncoderBitRateKey: format.bitsPerSecond,
            ])
        }
        soundInput?.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        super.init()
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(seconds: encoding.segmentSeconds, preferredTimescale: Self.timescale)
        writer.initialSegmentStartTime = .zero
        writer.delegate = self
        writer.add(input)
        soundInput.map(writer.add)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
    }

    private static func codecType(for codec: StreamCodec) -> AVVideoCodecType {
        switch codec {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }

    func append(_ pixelBuffer: CVPixelBuffer, at seconds: Double) {
        // A frame that arrives while the encoder is busy is dropped: the
        // stream is live, and the next one is a moment away.
        if input.isReadyForMoreMediaData {
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(seconds: seconds, preferredTimescale: Self.timescale))
        }
    }

    func appendSound(_ sound: CMSampleBuffer, startingFrom origin: Double) {
        // The sound keeps its own spacing and is moved as a whole onto the
        // stream's clock; anything from before the stream began is dropped.
        let moved = CMSampleBufferGetPresentationTimeStamp(sound)
            - CMTime(seconds: origin, preferredTimescale: Self.soundTimescale)
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sound), presentationTimeStamp: moved, decodeTimeStamp: .invalid
        )
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil, sampleBuffer: sound, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleBufferOut: &copy
        )
        if moved >= .zero, soundInput?.isReadyForMoreMediaData == true, let copy {
            soundInput?.append(copy)
        }
    }

    func finish() {
        soundInput?.markAsFinished()
        input.markAsFinished()
        writer.finishWriting {}
    }

    func assetWriter(_ writer: AVAssetWriter, didOutputSegmentData segmentData: Data, segmentType: AVAssetSegmentType) {
        if segmentType == .initialization {
            callbacks.initialization(segmentData)
        } else {
            callbacks.segment(segmentData, segmentSeconds)
        }
    }
}
