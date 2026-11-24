import Foundation

/// The numbers somebody might want to turn in how quickly things are tried
/// again, polled, read and buffered. They are settings, not laws: each
/// process reads them from its configuration and hands them in, so one can
/// be changed without changing the code. It lives here so the camera
/// extension can read its own too.
public struct Pacing: Equatable, Sendable {
    /// Seconds before a screen or window capture tries again after it fails.
    public var screenRetryDelay: TimeInterval
    /// Seconds before a remote screen over VNC reconnects after it drops.
    public var remoteScreenRetryDelay: TimeInterval
    /// Seconds before AirPlay tries again when the stream cannot be played yet.
    public var airPlayRetryDelay: TimeInterval
    /// Seconds before a Cast device is tried again after it fails.
    public var castRetryDelay: TimeInterval
    /// Seconds between pings to a Cast device, which drops a sender it has not heard from.
    public var castPingInterval: TimeInterval
    /// Seconds between tries to reach the virtual camera.
    public var cameraReconnectInterval: TimeInterval
    /// Seconds the app may be silent before the virtual camera shows its placeholder.
    public var cameraSilenceTimeout: TimeInterval
    /// Seconds the virtual camera waits before asking the app for a frame again after an empty answer.
    public var cameraRetryDelay: TimeInterval
    /// Seconds between looks for the virtual microphone.
    public var microphoneLookInterval: TimeInterval
    /// Seconds a web stream waits to hear sound before it goes out without.
    public var longestWaitForSound: TimeInterval
    /// Seconds an effect thumbnail runs before its picture is taken.
    public var thumbnailWarmUp: TimeInterval
    /// Frames a second the clock of an effect thumbnail ticks at.
    public var thumbnailFramesPerSecond: TimeInterval
    /// How many times a second a website source takes a new picture.
    public var websiteSnapshotsPerSecond: TimeInterval
    /// Seconds between looks in a watched folder for new videos.
    public var hotFolderInterval: TimeInterval
    /// How many pieces of a live stream a player can still fetch.
    public var streamPiecesKept: Int
    /// Bytes in each chunk a live stream is sent in, which suits video better than the default.
    public var streamChunkSize: Int
    /// The most bytes read from a remote screen at a time.
    public var remoteScreenLargestRead: Int
    /// The most bytes read from a live stream server at a time.
    public var streamLargestRead: Int
    /// The most bytes of a request the web stream server reads at a time.
    public var webLargestRequest: Int
    /// The most bytes read from a Cast device at a time.
    public var castLargestRead: Int
    /// How many frames of sound each look at the sound engine takes.
    public var soundTapFrames: Int
    /// How many frames the virtual camera lets be in use before it stops handing out more.
    public var framePoolThreshold: Int
    /// Samples a second in the sound of a recording.
    public var recordingSoundRate: Int
    /// Bits a second for each pixel of a recording's picture, when its bit rate is left to the app.
    public var recordingBitsPerPixelPerSecond: Int

    public init(
        screenRetryDelay: TimeInterval,
        remoteScreenRetryDelay: TimeInterval,
        airPlayRetryDelay: TimeInterval,
        castRetryDelay: TimeInterval,
        castPingInterval: TimeInterval,
        cameraReconnectInterval: TimeInterval,
        cameraSilenceTimeout: TimeInterval,
        cameraRetryDelay: TimeInterval,
        microphoneLookInterval: TimeInterval,
        longestWaitForSound: TimeInterval,
        thumbnailWarmUp: TimeInterval,
        thumbnailFramesPerSecond: TimeInterval,
        websiteSnapshotsPerSecond: TimeInterval,
        hotFolderInterval: TimeInterval,
        streamPiecesKept: Int,
        streamChunkSize: Int,
        remoteScreenLargestRead: Int,
        streamLargestRead: Int,
        webLargestRequest: Int,
        castLargestRead: Int,
        soundTapFrames: Int,
        framePoolThreshold: Int,
        recordingSoundRate: Int,
        recordingBitsPerPixelPerSecond: Int
    ) {
        self.screenRetryDelay = screenRetryDelay
        self.remoteScreenRetryDelay = remoteScreenRetryDelay
        self.airPlayRetryDelay = airPlayRetryDelay
        self.castRetryDelay = castRetryDelay
        self.castPingInterval = castPingInterval
        self.cameraReconnectInterval = cameraReconnectInterval
        self.cameraSilenceTimeout = cameraSilenceTimeout
        self.cameraRetryDelay = cameraRetryDelay
        self.microphoneLookInterval = microphoneLookInterval
        self.longestWaitForSound = longestWaitForSound
        self.thumbnailWarmUp = thumbnailWarmUp
        self.thumbnailFramesPerSecond = thumbnailFramesPerSecond
        self.websiteSnapshotsPerSecond = websiteSnapshotsPerSecond
        self.hotFolderInterval = hotFolderInterval
        self.streamPiecesKept = streamPiecesKept
        self.streamChunkSize = streamChunkSize
        self.remoteScreenLargestRead = remoteScreenLargestRead
        self.streamLargestRead = streamLargestRead
        self.webLargestRequest = webLargestRequest
        self.castLargestRead = castLargestRead
        self.soundTapFrames = soundTapFrames
        self.framePoolThreshold = framePoolThreshold
        self.recordingSoundRate = recordingSoundRate
        self.recordingBitsPerPixelPerSecond = recordingBitsPerPixelPerSecond
    }

    /// What each is when nobody has set it. This is the one place the usual numbers are written.
    public static let usual = Pacing(
        screenRetryDelay: 2,
        remoteScreenRetryDelay: 3,
        airPlayRetryDelay: 2,
        castRetryDelay: 5,
        castPingInterval: 5,
        cameraReconnectInterval: 2,
        cameraSilenceTimeout: 1,
        cameraRetryDelay: 0.01,
        microphoneLookInterval: 1,
        longestWaitForSound: 2,
        thumbnailWarmUp: 0.7,
        thumbnailFramesPerSecond: 30,
        websiteSnapshotsPerSecond: 10,
        hotFolderInterval: 3,
        streamPiecesKept: 6,
        streamChunkSize: 4096,
        remoteScreenLargestRead: 1 << 20,
        streamLargestRead: 64 * 1024,
        webLargestRequest: 16 * 1024,
        castLargestRead: 65536,
        soundTapFrames: 1024,
        framePoolThreshold: 5,
        recordingSoundRate: 48000,
        recordingBitsPerPixelPerSecond: 6
    )

    /// The names the settings go by.
    public enum Key {
        public static let screenRetryDelay = "ScreenRetryDelay"
        public static let remoteScreenRetryDelay = "RemoteScreenRetryDelay"
        public static let airPlayRetryDelay = "AirPlayRetryDelay"
        public static let castRetryDelay = "CastRetryDelay"
        public static let castPingInterval = "CastPingInterval"
        public static let cameraReconnectInterval = "CameraReconnectInterval"
        public static let cameraSilenceTimeout = "CameraSilenceTimeout"
        public static let cameraRetryDelay = "CameraRetryDelay"
        public static let microphoneLookInterval = "MicrophoneLookInterval"
        public static let longestWaitForSound = "LongestWaitForSound"
        public static let thumbnailWarmUp = "ThumbnailWarmUp"
        public static let thumbnailFramesPerSecond = "ThumbnailFramesPerSecond"
        public static let websiteSnapshotsPerSecond = "WebsiteSnapshotsPerSecond"
        public static let hotFolderInterval = "HotFolderInterval"
        public static let streamPiecesKept = "StreamPiecesKept"
        public static let streamChunkSize = "StreamChunkSize"
        public static let remoteScreenLargestRead = "RemoteScreenLargestRead"
        public static let streamLargestRead = "StreamLargestRead"
        public static let webLargestRequest = "WebLargestRequest"
        public static let castLargestRead = "CastLargestRead"
        public static let soundTapFrames = "SoundTapFrames"
        public static let framePoolThreshold = "FramePoolThreshold"
        public static let recordingSoundRate = "RecordingSoundRate"
        public static let recordingBitsPerPixelPerSecond = "RecordingBitsPerPixelPerSecond"
    }

    /// The settings that are lengths of time or rates, by name.
    static let numbers: [(key: String, value: WritableKeyPath<Pacing, TimeInterval>)] = [
        (Key.screenRetryDelay, \.screenRetryDelay),
        (Key.remoteScreenRetryDelay, \.remoteScreenRetryDelay),
        (Key.airPlayRetryDelay, \.airPlayRetryDelay),
        (Key.castRetryDelay, \.castRetryDelay),
        (Key.castPingInterval, \.castPingInterval),
        (Key.cameraReconnectInterval, \.cameraReconnectInterval),
        (Key.cameraSilenceTimeout, \.cameraSilenceTimeout),
        (Key.cameraRetryDelay, \.cameraRetryDelay),
        (Key.microphoneLookInterval, \.microphoneLookInterval),
        (Key.longestWaitForSound, \.longestWaitForSound),
        (Key.thumbnailWarmUp, \.thumbnailWarmUp),
        (Key.thumbnailFramesPerSecond, \.thumbnailFramesPerSecond),
        (Key.websiteSnapshotsPerSecond, \.websiteSnapshotsPerSecond),
        (Key.hotFolderInterval, \.hotFolderInterval),
    ]

    /// The settings that are counts or sizes, by name.
    static let counts: [(key: String, value: WritableKeyPath<Pacing, Int>)] = [
        (Key.streamPiecesKept, \.streamPiecesKept),
        (Key.streamChunkSize, \.streamChunkSize),
        (Key.remoteScreenLargestRead, \.remoteScreenLargestRead),
        (Key.streamLargestRead, \.streamLargestRead),
        (Key.webLargestRequest, \.webLargestRequest),
        (Key.castLargestRead, \.castLargestRead),
        (Key.soundTapFrames, \.soundTapFrames),
        (Key.framePoolThreshold, \.framePoolThreshold),
        (Key.recordingSoundRate, \.recordingSoundRate),
        (Key.recordingBitsPerPixelPerSecond, \.recordingBitsPerPixelPerSecond),
    ]

    /// Each setting that has been set, or its usual value. Nought and below
    /// are never usable here, so they count as not set.
    public static func load(defaults: UserDefaults) -> Pacing {
        var pacing = usual
        for (key, value) in numbers {
            let set = defaults.double(forKey: key)
            if set > 0 { pacing[keyPath: value] = set }
        }
        for (key, value) in counts {
            let set = defaults.integer(forKey: key)
            if set > 0 { pacing[keyPath: value] = set }
        }
        return pacing
    }
}
