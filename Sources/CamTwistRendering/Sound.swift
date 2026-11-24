import AVFoundation
import CamTwistCore
import CoreMedia
import Foundation

/// Somewhere the mixed sound goes.
public protocol SoundSink: AnyObject {
    func send(_ sound: CMSampleBuffer)
}

/// A microphone the user can pick.
public struct MicrophoneChoice: Identifiable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Compresses sound a buffer at a time, for sending as it is made.
protocol SoundEncoding: AnyObject {
    /// The packets of compressed sound a buffer completes, which may be
    /// none: packets are a fixed length and buffers are not.
    func encode(_ sound: CMSampleBuffer) -> [Data]
}

/// When a sound buffer was made, in seconds on the clock video frames are timed by.
enum SoundTiming {
    static func seconds(of sound: CMSampleBuffer) -> Double {
        CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sound))
    }
}
