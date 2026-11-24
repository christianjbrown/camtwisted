import Foundation

/// How a stream's picture is compressed.
public enum StreamCodec: String, Codable, CaseIterable, Sendable {
    /// Plays on everything.
    case h264
    /// The same picture in about half the data, for players that take it:
    /// Apple's, and newer ones elsewhere.
    case hevc

    /// What the encoding is called in a list of them.
    public var title: String {
        switch self {
        case .h264: PictureCodecWording.h264.title
        case .hevc: PictureCodecWording.hevc.title
        }
    }
}

/// How a stream is encoded: how big its picture is, how much data its
/// picture and sound take, and what its sound is like.
public struct StreamOptions: Codable, Equatable, Sendable {
    /// The usual steps, from a small picture on a slow line to the most a
    /// streaming service takes.
    public static let videoKilobitChoices: [Double] = [500, 1000, 1500, 2500, 3000, 4000, 4500, 6000, 8000, 10000, 12000]
    public static let keyFrameSecondsRange: ClosedRange<Double> = 0.5...6
    public static let soundKilobitChoices = [64, 96, 128, 192, 256]
    public static let sampleRates = [44100, 48000]
    public static let channelChoices = [1, 2]

    private static let bitsPerKilobit = 1000

    /// The picture's height in pixels, one of `PictureHeight.all`; its width
    /// follows from its shape.
    public var height: Int
    /// Thousands of bits a second for the picture.
    public var videoKilobits: Double
    /// Seconds between key frames, which is also how long each piece of
    /// an HLS stream is. Shorter means less delay and more data.
    public var keyFrameSeconds: Double
    /// Thousands of bits a second for the sound.
    public var soundKilobits: Int
    public var soundChannels: Int
    public var sampleRate: Int
    /// Whether a marker with the scene's name goes into the stream each
    /// time the scene on air changes. Optional so options saved before it
    /// existed still load.
    public var sceneMarkers: Bool?
    /// How the picture is compressed. Optional so options saved before it
    /// existed still load.
    public var videoCodec: StreamCodec?

    /// How the picture is compressed: H.264 unless something else is chosen.
    public var codec: StreamCodec {
        get { videoCodec ?? .h264 }
        set { videoCodec = newValue }
    }

    /// Whether scene changes are marked in the stream.
    public var marksScenes: Bool {
        get { sceneMarkers ?? false }
        set { sceneMarkers = newValue }
    }

    public init(
        height: Int = PictureHeight.hd, videoKilobits: Double = 4000, keyFrameSeconds: Double = 2,
        soundKilobits: Int = 128, soundChannels: Int = 2, sampleRate: Int = 48000, marksScenes: Bool = false,
        codec: StreamCodec = .h264
    ) {
        self.height = height
        self.videoKilobits = videoKilobits
        self.keyFrameSeconds = keyFrameSeconds
        self.soundKilobits = soundKilobits
        self.soundChannels = soundChannels
        self.sampleRate = sampleRate
        sceneMarkers = marksScenes
        videoCodec = codec
    }

    /// What a stream watched over the local network starts with: short
    /// pieces, to keep the delay down.
    public static let web = StreamOptions(keyFrameSeconds: 1)
    /// What a stream to a server starts with: a key frame every two
    /// seconds, as streaming services ask.
    public static let server = StreamOptions(videoKilobits: 4500, keyFrameSeconds: 2)

    /// The same options with anything out of range brought back in, and
    /// anything not on offer swapped for what a new stream has.
    public var usable: StreamOptions {
        func choice<Value: Equatable>(_ value: Value, among choices: [Value], else fallback: Value) -> Value {
            choices.contains(value) ? value : fallback
        }
        func held(_ value: Double, to range: ClosedRange<Double>) -> Double {
            min(max(value, range.lowerBound), range.upperBound)
        }
        let fresh = StreamOptions()
        return StreamOptions(
            height: choice(height, among: PictureHeight.all, else: fresh.height),
            videoKilobits: choice(videoKilobits, among: Self.videoKilobitChoices, else: fresh.videoKilobits),
            keyFrameSeconds: held(keyFrameSeconds, to: Self.keyFrameSecondsRange),
            soundKilobits: choice(soundKilobits, among: Self.soundKilobitChoices, else: fresh.soundKilobits),
            soundChannels: choice(soundChannels, among: Self.channelChoices, else: fresh.soundChannels),
            sampleRate: choice(sampleRate, among: Self.sampleRates, else: fresh.sampleRate),
            marksScenes: marksScenes, codec: codec
        )
    }

    /// The picture's size for a canvas of some shape. The width is made
    /// even, as video encoders need.
    public func pictureSize(canvasAspect: Double) -> (width: Int, height: Int) {
        PictureHeight.size(height: usable.height, canvasAspect: canvasAspect)
    }

    public var videoBitsPerSecond: Int { Int(usable.videoKilobits) * Self.bitsPerKilobit }

    /// What the stream's sound is like.
    public var sound: SoundFormat {
        let options = usable
        return SoundFormat(
            sampleRate: options.sampleRate, channels: options.soundChannels,
            bitsPerSecond: options.soundKilobits * Self.bitsPerKilobit
        )
    }
}

/// The two streams served to players on the local network.
public enum WebStreamKind: Sendable {
    /// An HLS stream, with a page that plays it.
    case hls
    /// One endless MP4.
    case movie

}
