import Foundation

/// Whether the streams carry sound: the mix of whatever in the scene on
/// air makes any.
public struct SoundSettings: Codable, Equatable, Sendable {
    public var isOn: Bool

    /// Sound is carried unless switched off.
    public init(isOn: Bool = true) {
        self.isOn = isOn
    }
}

/// What the sound in a stream is like.
public struct SoundFormat: Equatable, Sendable {
    public let sampleRate: Int
    public let channels: Int
    public let bitsPerSecond: Int

    /// Samples in one packet of AAC.
    public static let samplesPerPacket = 1024
    public static let standard = SoundFormat(sampleRate: 48000, channels: 2, bitsPerSecond: 128_000)

    public init(sampleRate: Int, channels: Int, bitsPerSecond: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSecond = bitsPerSecond
    }

    /// Seconds one packet of sound lasts.
    public var packetSeconds: Double { Double(Self.samplesPerPacket) / Double(sampleRate) }
}

/// Builds the pieces of sound RTMP carries, which are FLV audio tags
/// holding AAC.
public enum FLVAudio {
    /// AAC, at the format's nominal rate, 16 bits, stereo: the one byte
    /// every AAC tag starts with, whatever the sound really is.
    private static let aacTag: UInt8 = 0xAF
    private static let sequenceHeaderPacket: UInt8 = 0
    private static let framePacket: UInt8 = 1
    /// The kind of AAC nearly everything plays: low complexity.
    private static let lowComplexity = 2
    /// The rates AAC has a short code for, in the order of their codes.
    private static let sampleRates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000]
    private static let objectTypeShift = 11
    private static let sampleRateShift = 7
    private static let channelShift = 3
    private static let configurationLength = 2

    /// The tag that tells a player how to decode the sound that follows.
    /// Nil for a sample rate AAC has no code for.
    public static func sequenceHeader(for format: SoundFormat) -> Data? {
        guard let rate = sampleRates.firstIndex(of: format.sampleRate) else { return nil }
        let configuration = lowComplexity << objectTypeShift | rate << sampleRateShift | format.channels << channelShift
        return Data([aacTag, sequenceHeaderPacket])
            + ByteOrder.bigEndian(UInt64(configuration), bytes: configurationLength)
    }

    /// One packet of AAC as a tag.
    public static func frame(_ packet: Data) -> Data {
        Data([aacTag, framePacket]) + packet
    }
}

/// Works out how loud each source in a scene is in the streams.
public enum SceneSound {
    public static let silent = 0.0
    public static let full = 1.0
    public static let range: ClosedRange<Double> = silent...full

    /// Whether any of some scenes has a source that would be heard. With
    /// none, a stream is better sent without a sound track at all.
    public static func isHeard(in scenes: [SceneConfiguration]) -> Bool {
        scenes.contains { levels(in: $0).values.contains { $0 > silent } }
    }

    /// How loud a source whose volume is set on its step starts out, or
    /// nil for a source with no such volume. A camera and a microphone
    /// start at full volume. A screen and a window start silent: they
    /// carry everything the Mac or an app is playing, a call's other
    /// voices included, so that is only sent on when asked for.
    public static func startingVolume(for spec: SourceSpec) -> Double? {
        spec.kind.startingVolume
    }

    /// The level of every switched-on source that makes sound, by step.
    /// A camera, a microphone, a screen or a window is as loud as its step
    /// says; a video or a stream is as loud as its own volume, unless muted.
    public static func levels(in scene: SceneConfiguration) -> [UUID: Double] {
        var levels: [UUID: Double] = [:]
        for (id, spec) in scene.sourcesInUse {
            levels[id] = spec.kind.level(stepVolume: scene.item(id: id)?.volume)
        }
        return levels
    }
}
