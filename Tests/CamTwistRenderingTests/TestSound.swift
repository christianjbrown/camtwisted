import AVFoundation
import CoreMedia
import XCTest

/// Makes buffers of sound like the ones a microphone gives: a steady tone,
/// one channel, timed on the host clock.
enum TestSound {
    static let rate = 48000.0

    static func buffer(samples: Int = 1024, at seconds: Double) -> CMSampleBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples))!
        pcm.frameLength = AVAudioFrameCount(samples)
        for index in 0..<samples {
            pcm.floatChannelData![0][index] = Float(sin(Double(index) * 2 * .pi * 440 / rate)) * 0.5
        }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(rate)),
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: format.formatDescription, sampleCount: samples, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample
        )
        CMSampleBufferSetDataBufferFromAudioBufferList(
            sample!, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
            bufferList: pcm.audioBufferList
        )
        return sample!
    }
}
