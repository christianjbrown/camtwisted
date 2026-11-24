import AVFoundation
import CamTwistCore
import CoreMedia
import Foundation

/// Compresses sound as AAC with the system's encoder.
final class AACEncoder: SoundEncoding {
    /// Packets taken from the encoder in one go.
    private static let packetsPerPass: AVAudioPacketCount = 8

    private let format: SoundFormat
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    init(format: SoundFormat) {
        self.format = format
    }

    func encode(_ sound: CMSampleBuffer) -> [Data] {
        guard let description = sound.formatDescription else { return [] }
        let incoming = AVAudioFormat(cmAudioFormatDescription: description)
        // The encoder is made for the first sound heard, and again if the
        // microphone changes to one that sounds different.
        if incoming != inputFormat {
            inputFormat = incoming
            converter = Self.makeConverter(from: incoming, to: format)
        }
        let frames = AVAudioFrameCount(sound.numSamples)
        guard let converter, let buffer = AVAudioPCMBuffer(pcmFormat: incoming, frameCapacity: frames) else {
            return []
        }
        // The length is set first: until it is, the buffer says it has room for nothing.
        buffer.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sound, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
        ) == noErr else { return [] }

        var packets: [Data] = []
        var isOffered = false
        while true {
            let output = AVAudioCompressedBuffer(
                format: converter.outputFormat, packetCapacity: Self.packetsPerPass,
                maximumPacketSize: converter.maximumOutputPacketSize
            )
            let status = converter.convert(to: output, error: nil) { _, inputStatus in
                // The buffer is handed over once; after that there is no more for now.
                if isOffered {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                isOffered = true
                inputStatus.pointee = .haveData
                return buffer
            }
            packets += Self.packets(in: output)
            if status != .haveData { break }
        }
        return packets
    }

    private static func makeConverter(from input: AVAudioFormat, to format: SoundFormat) -> AVAudioConverter? {
        var description = AudioStreamBasicDescription(
            mSampleRate: Double(format.sampleRate), mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: UInt32(SoundFormat.samplesPerPacket), mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(format.channels), mBitsPerChannel: 0, mReserved: 0
        )
        guard let output = AVAudioFormat(streamDescription: &description),
              let converter = AVAudioConverter(from: input, to: output)
        else { return nil }
        converter.bitRate = format.bitsPerSecond
        return converter
    }

    private static func packets(in buffer: AVAudioCompressedBuffer) -> [Data] {
        guard let descriptions = buffer.packetDescriptions else { return [] }
        return (0..<Int(buffer.packetCount)).map { index in
            let packet = descriptions[index]
            return Data(bytes: buffer.data + Int(packet.mStartOffset), count: Int(packet.mDataByteSize))
        }
    }
}
