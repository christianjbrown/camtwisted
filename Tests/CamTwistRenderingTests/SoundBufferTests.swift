import AVFoundation
import CoreMedia
import XCTest
@testable import CamTwistRendering

final class SoundBufferTests: XCTestCase {
    func testASampleBufferBecomesAnEngineBufferOfTheSameLength() throws {
        let sound = TestSound.buffer(samples: 256, at: 1)
        let pcm = try XCTUnwrap(SoundBuffers.pcmBuffer(from: sound))
        XCTAssertEqual(pcm.frameLength, 256)
        XCTAssertEqual(pcm.format.sampleRate, TestSound.rate)
        XCTAssertNotEqual(pcm.floatChannelData?[0][1], 0)
    }

    func testASampleBufferWithNoSamplesGivesNothing() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
        var sample: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: nil, dataBuffer: nil, dataReady: true, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: format.formatDescription, sampleCount: 0, sampleTimingEntryCount: 0,
            sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample
        )
        XCTAssertNil(SoundBuffers.pcmBuffer(from: try XCTUnwrap(sample)))
    }

    func testASampleBufferWithNoFormatGivesNothing() throws {
        var sample: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: nil, dataBuffer: nil, dataReady: true, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: nil, sampleCount: 0, sampleTimingEntryCount: 0,
            sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample
        )
        XCTAssertNil(SoundBuffers.pcmBuffer(from: try XCTUnwrap(sample)))
    }

    func testASampleBufferWhoseSoundCannotBeCopiedGivesNothing() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
        var sample: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: format.formatDescription, sampleCount: 10, sampleTimingEntryCount: 0,
            sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample
        )
        XCTAssertNil(SoundBuffers.pcmBuffer(from: try XCTUnwrap(sample)))
    }

    func testAMixThatCannotBeWrappedGivesNothing() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
        let empty = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16))
        XCTAssertNil(SoundBuffers.sampleBuffer(from: empty, atSeconds: 1))
    }

    func testAMixIsTimedAtTheSecondsItIsGiven() throws {
        let pcm = try XCTUnwrap(SoundBuffers.pcmBuffer(from: TestSound.buffer(samples: 128, at: 0)))
        let sample = try XCTUnwrap(SoundBuffers.sampleBuffer(from: pcm, atSeconds: 12.5))
        XCTAssertEqual(sample.presentationTimeStamp.seconds, 12.5, accuracy: 0.0001)
        XCTAssertEqual(sample.numSamples, 128)
    }

    func testATimeWithAHostTimeIsReadAsItIsAndOneWithoutIsTakenAsNow() {
        let hosted = AVAudioTime(hostTime: 1_000_000)
        XCTAssertEqual(
            SoundBuffers.seconds(of: hosted, now: { 99 }), AVAudioTime.seconds(forHostTime: 1_000_000)
        )
        let unhosted = AVAudioTime(sampleTime: 100, atRate: 48000)
        XCTAssertEqual(SoundBuffers.seconds(of: unhosted, now: { 99 }), 99)
    }
}
