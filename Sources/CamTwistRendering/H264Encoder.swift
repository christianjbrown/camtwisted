import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// One compressed frame, each unit of it with its length in front.
struct EncodedFrame {
    let data: Data
    let isKeyFrame: Bool
    let milliseconds: UInt32
    /// The sets a decoder needs before anything else, which come with key frames.
    let parameterSets: (sequence: Data, picture: Data)?
}

/// Compresses frames one at a time, for sending as they are made.
protocol FrameEncoding: AnyObject {
    func encode(_ pixelBuffer: CVPixelBuffer, atMilliseconds milliseconds: UInt32)
    func finish()
}

/// Compresses frames as H.264 with the system's encoder, which uses the
/// graphics hardware where it can.
final class H264Encoder: FrameEncoding {
    private static let millisecondsPerSecond: Int32 = 1000
    private static let sequenceSetIndex = 0
    private static let pictureSetIndex = 1

    private var session: VTCompressionSession?
    private let output: (EncodedFrame) -> Void

    init(size: CGSize, encoding: StreamEncoding, output: @escaping (EncodedFrame) -> Void) {
        self.output = output
        VTCompressionSessionCreate(
            allocator: nil, width: Int32(size.width), height: Int32(size.height), codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session
        )
        guard let session else { return }
        let properties: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_AutoLevel,
            kVTCompressionPropertyKey_AverageBitRate: encoding.bitsPerSecond,
            kVTCompressionPropertyKey_ExpectedFrameRate: encoding.framesPerSecond,
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: encoding.segmentSeconds,
        ]
        VTSessionSetProperties(session, propertyDictionary: properties as CFDictionary)
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    func encode(_ pixelBuffer: CVPixelBuffer, atMilliseconds milliseconds: UInt32) {
        guard let session else { return }
        let time = CMTime(value: CMTimeValue(milliseconds), timescale: Self.millisecondsPerSecond)
        let output = self.output
        VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer, presentationTimeStamp: time, duration: .invalid,
            frameProperties: nil, infoFlagsOut: nil
        ) { status, _, sample in
            guard status == noErr, let sample, let frame = Self.frame(from: sample, milliseconds: milliseconds) else {
                return
            }
            output(frame)
        }
    }

    func finish() {
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
    }

    private static func frame(from sample: CMSampleBuffer, milliseconds: UInt32) -> EncodedFrame? {
        guard let block = sample.dataBuffer, let data = try? block.dataBytes() else { return nil }
        // A frame is a key frame unless it says it depends on another.
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let dependsOnOthers = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        var sets: (Data, Data)?
        if !dependsOnOthers, let format = sample.formatDescription,
           let sequence = parameterSet(sequenceSetIndex, of: format),
           let picture = parameterSet(pictureSetIndex, of: format) {
            sets = (sequence, picture)
        }
        return EncodedFrame(data: data, isKeyFrame: !dependsOnOthers, milliseconds: milliseconds, parameterSets: sets)
    }

    private static func parameterSet(_ index: Int, of format: CMFormatDescription) -> Data? {
        var pointer: UnsafePointer<UInt8>?
        var size = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format, parameterSetIndex: index, parameterSetPointerOut: &pointer, parameterSetSizeOut: &size,
            parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil
        )
        guard status == noErr, let pointer else { return nil }
        return Data(bytes: pointer, count: size)
    }
}
