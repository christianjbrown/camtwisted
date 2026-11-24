import AVFoundation
import CamTwistCore
import CoreMedia
import CoreVideo
import Foundation

/// Writes a recording: pictures, sound, and a chapter for each scene.
protocol MovieWriting: AnyObject {
    /// Adds a frame, at a time in seconds since the recording began.
    func append(_ pixelBuffer: CVPixelBuffer, at seconds: Double)
    /// Adds sound. `origin` is when the recording began, on the clock the
    /// sound is timed by.
    func appendSound(_ sound: CMSampleBuffer, startingFrom origin: Double)
    /// Starts a chapter, which runs until the next one or the end.
    func startChapter(named name: String, at seconds: Double)
    /// Ends the recording at a time, and calls back once the file is whole.
    func finish(at seconds: Double, completion: @escaping () -> Void)
}

/// The names AVFoundation knows a recording's formats by. Each mapping is
/// written here once.
enum RecordingFormats {
    /// Bits in each sample of uncompressed sound.
    static let uncompressedBitDepth = 24

    static func fileType(for container: RecordingContainer) -> AVFileType {
        switch container {
        case .quickTime: .mov
        case .mpeg4: .mp4
        }
    }

    static func videoCodec(for codec: RecordingPictureCodec) -> AVVideoCodecType {
        switch codec {
        case .h264: .h264
        case .hevc: .hevc
        case .proRes422: .proRes422
        }
    }

    /// How the picture is encoded: its size, and its bit rate when it has one.
    static func pictureSettings(for plan: RecordingPlan) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: videoCodec(for: plan.pictureCodec),
            AVVideoWidthKey: plan.width,
            AVVideoHeightKey: plan.height,
        ]
        if let bitsPerSecond = plan.pictureBitsPerSecond {
            settings[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: bitsPerSecond]
        }
        return settings
    }

    /// How the sound is encoded, in stereo at so many samples a second.
    static func soundSettings(for plan: RecordingPlan, soundRate: Int, channels: Int) -> [String: Any] {
        var settings: [String: Any] = [AVSampleRateKey: soundRate, AVNumberOfChannelsKey: channels]
        switch plan.soundCodec {
        case .aac:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
        case .linearPCM:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = uncompressedBitDepth
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false
            settings[AVLinearPCMIsNonInterleaved] = false
        }
        if let bitsPerSecond = plan.soundBitsPerSecond {
            settings[AVEncoderBitRateKey] = bitsPerSecond
        }
        return settings
    }
}

/// Writes a movie as its plan says, in the kind of file and with the
/// pictures and sound encoded the way it asks, along with a chapter track,
/// which players show as a list of places to jump to. Frames of any size
/// are scaled to the plan's.
final class ChapteredMovieWriter: MovieWriting {
    private enum Format {
        /// Times are counted in this many ticks a second.
        static let timescale: CMTimeScale = 600
        /// Fine enough to place sound to the sample.
        static let soundTimescale: CMTimeScale = 1_000_000_000
        static let soundChannels = 2
    }

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let soundInput: AVAssetWriterInput
    private let chapters: ChapterTrack

    /// Why a recording did not begin.
    enum Failure: Error {
        case cannotStart
    }

    /// Throws when a movie cannot be written at that address.
    /// - Parameter soundRate: samples a second in the recording's sound.
    init(url: URL, plan: RecordingPlan, soundRate: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: RecordingFormats.fileType(for: plan.container))
        input = AVAssetWriterInput(mediaType: .video, outputSettings: RecordingFormats.pictureSettings(for: plan))
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        soundInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: RecordingFormats.soundSettings(
                for: plan, soundRate: soundRate, channels: Format.soundChannels
            )
        )
        soundInput.expectsMediaDataInRealTime = true

        // The picture track points at the chapters, which is what makes
        // them its list of places to jump to.
        chapters = try ChapterTrack(timescale: Format.timescale)
        input.addTrackAssociation(withTrackOf: chapters.input, type: AVAssetTrack.AssociationType.chapterList.rawValue)

        writer.add(input)
        writer.add(soundInput)
        writer.add(chapters.input)
        guard writer.startWriting() else { throw Failure.cannotStart }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ pixelBuffer: CVPixelBuffer, at seconds: Double) {
        // A frame that arrives while the encoder is busy is dropped: the
        // next one is a moment away.
        if input.isReadyForMoreMediaData {
            adaptor.append(pixelBuffer, withPresentationTime: time(seconds))
        }
    }

    func appendSound(_ sound: CMSampleBuffer, startingFrom origin: Double) {
        // The sound keeps its own spacing and is moved as a whole onto the
        // recording's clock; anything from before it began is dropped.
        let moved = CMSampleBufferGetPresentationTimeStamp(sound)
            - CMTime(seconds: origin, preferredTimescale: Format.soundTimescale)
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sound), presentationTimeStamp: moved, decodeTimeStamp: .invalid
        )
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil, sampleBuffer: sound, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleBufferOut: &copy
        )
        if moved >= .zero, soundInput.isReadyForMoreMediaData, let copy {
            soundInput.append(copy)
        }
    }

    func startChapter(named name: String, at seconds: Double) {
        chapters.start(named: name, at: seconds)
    }

    func finish(at seconds: Double, completion: @escaping () -> Void) {
        chapters.finish(at: seconds)
        soundInput.markAsFinished()
        input.markAsFinished()
        writer.endSession(atSourceTime: time(seconds))
        writer.finishWriting(completionHandler: completion)
    }

    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: Format.timescale)
    }
}
