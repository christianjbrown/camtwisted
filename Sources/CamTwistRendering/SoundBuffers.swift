import AVFoundation
import CoreMedia
import Foundation

/// Converts sound between the buffer types the capture side and the audio
/// engine each speak.
enum SoundBuffers {
    private static let nanosecondsPerSecond: CMTimeScale = 1_000_000_000

    /// The sound in a buffer, as the audio engine plays it.
    static func pcmBuffer(from sound: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = sound.formatDescription else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(sound.numSamples)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sound, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }

    /// When a buffer plays, in seconds on the clock video frames are timed
    /// by. A time with no host time is taken to be now.
    static func seconds(of time: AVAudioTime, now: () -> TimeInterval) -> TimeInterval {
        time.isHostTimeValid ? AVAudioTime.seconds(forHostTime: time.hostTime) : now()
    }

    /// The mix as a buffer timed at the given seconds.
    static func sampleBuffer(from buffer: AVAudioPCMBuffer, atSeconds seconds: TimeInterval) -> CMSampleBuffer? {
        sampleBuffer(
            buffers: buffer.audioBufferList, frames: CMItemCount(buffer.frameLength), format: buffer.format,
            atSeconds: seconds
        )
    }

    /// Sound held in an audio buffer list, as a sample buffer timed at the
    /// given seconds.
    static func sampleBuffer(
        buffers: UnsafePointer<AudioBufferList>, frames: CMItemCount, format: AVAudioFormat, atSeconds seconds: TimeInterval
    ) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(format.sampleRate)),
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: nanosecondsPerSecond),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: format.formatDescription, sampleCount: frames,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &sample
        )
        guard let sample, CMSampleBufferSetDataBufferFromAudioBufferList(
            sample, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, bufferList: buffers
        ) == noErr else { return nil }
        return sample
    }
}
