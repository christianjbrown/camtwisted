import CamTwistCore
import CoreMedia
import CoreVideo
import Foundation

/// Serves the picture on air to other devices on the local network, as an
/// HLS stream or as one endless MP4, while switched on.
public final class WebStreamOutput: FrameSink, SoundSink {
    private struct State {
        var settings = WebStreamSettings()
        var status = WebStreamStatus.off
        var window: SegmentWindow
        var encoder: SegmentEncoding?
        var startedAt: Double?
        /// Whether sound is wanted, has been heard, and is in the stream.
        var wantsSound = false
        var hasHeardSound = false
        var carriesSound = false
        /// When the first frame came while still waiting to hear sound.
        var waitingSince: Double?
        /// How many scene changes have been marked.
        var markerCount = 0

        init(piecesKept: Int) {
            window = SegmentWindow(capacity: piecesKept)
        }
    }

    /// What an encoder is made from: the picture's size, how it is
    /// encoded, and what its sound is like when it has any.
    typealias EncoderPlan = (size: CGSize, encoding: StreamEncoding, sound: SoundFormat?)

    private let kind: WebStreamKind
    private let title: String
    private let canvas: CGSize
    private let framesPerSecond: Int32
    private let server: StreamServing
    private let makeEncoder: (EncoderPlan, SegmentCallbacks) -> SegmentEncoding
    private let clock: () -> Double
    /// The time by the clock on the wall, which markers are placed by.
    private let today: () -> Date
    private let state: Locked<State>
    /// How many pieces of the stream a player can still fetch.
    private let piecesKept: Int
    /// How long a stream that wants sound waits to hear some before it
    /// starts without. A stream told to expect sound that never comes
    /// would never start at all.
    private let longestWaitForSound: TimeInterval

    /// - Parameters:
    ///   - title: the name shown on the page that plays the stream.
    ///   - canvas: the size the picture is drawn at, which gives a stream its shape.
    ///   - piecesKept: how many pieces of the stream a player can still fetch.
    ///   - longestWaitForSound: seconds a stream that wants sound waits to hear some.
    ///   - largestRequest: the most bytes of a request the server reads at a time.
    ///   - queues: makes the queue the server listens on.
    ///   - clocks: what frames are timed and markers placed by.
    public convenience init(
        kind: WebStreamKind, title: String, canvas: CGSize, framesPerSecond: Int32,
        piecesKept: Int, longestWaitForSound: TimeInterval, largestRequest: Int, queues: QueueMaking, clocks: Clocks
    ) {
        self.init(
            kind: kind, title: title, canvas: canvas, framesPerSecond: framesPerSecond,
            server: WebStreamServer(
                largestRequest: largestRequest, queue: queues.makeQueue(label: WebStreamServer.queueLabel, qos: .default)
            ),
            makeEncoder: { SegmentedEncoder(size: $0.size, encoding: $0.encoding, sound: $0.sound, callbacks: $1) },
            clock: clocks.uptime, today: clocks.today,
            piecesKept: piecesKept, longestWaitForSound: longestWaitForSound
        )
    }

    init(
        kind: WebStreamKind, title: String, canvas: CGSize, framesPerSecond: Int32, server: StreamServing,
        makeEncoder: @escaping (EncoderPlan, SegmentCallbacks) -> SegmentEncoding,
        clock: @escaping () -> Double, today: @escaping () -> Date,
        piecesKept: Int = Pacing.usual.streamPiecesKept,
        longestWaitForSound: TimeInterval = Pacing.usual.longestWaitForSound
    ) {
        self.kind = kind
        self.title = title
        self.canvas = canvas
        self.framesPerSecond = framesPerSecond
        self.server = server
        self.makeEncoder = makeEncoder
        self.clock = clock
        self.today = today
        self.piecesKept = piecesKept
        self.longestWaitForSound = longestWaitForSound
        self.state = Locked(State(piecesKept: piecesKept))
    }

    public var status: WebStreamStatus { state.get().status }

    /// Starts, stops or moves the stream to match the settings, with or
    /// without sound from the microphone.
    public func apply(_ settings: WebStreamSettings, withSound: Bool) {
        let changed: (wasServing: Bool, old: SegmentEncoding?)? = state.update { current in
            guard settings != current.settings || withSound != current.wantsSound else { return nil }
            let before = (current.settings.isOn, current.encoder)
            // What is being listened to carries over; everything else starts afresh.
            let hasHeardSound = current.hasHeardSound
            current = State(piecesKept: piecesKept)
            current.hasHeardSound = hasHeardSound
            current.settings = settings
            current.wantsSound = withSound
            current.status = settings.isOn ? .running : .off
            return before
        }
        guard let changed else { return }
        if changed.wasServing {
            server.stop()
            changed.old?.finish()
        }
        if settings.isOn {
            server.start(
                port: settings.usablePort,
                handler: { [weak self] in self?.reply(to: $0) ?? .whole(.missing) },
                onFailure: { [weak self] in self?.failed($0) }
            )
        }
    }

    public func send(_ pixelBuffer: CVPixelBuffer) {
        let now = clock()
        let job: (encoder: SegmentEncoding, seconds: Double)? = state.update { current in
            guard current.settings.isOn else { return nil }
            if let encoder = current.encoder, let start = current.startedAt {
                return (encoder, now - start)
            }
            // The stream begins with its first frame. One that wants sound
            // holds on a moment to hear some, so it knows whether it has any.
            let waitingSince = current.waitingSince ?? now
            if current.wantsSound, !current.hasHeardSound, now - waitingSince < longestWaitForSound {
                current.waitingSince = waitingSince
                return nil
            }
            current.carriesSound = current.wantsSound && current.hasHeardSound
            let options = current.settings.options
            let size = options.pictureSize(canvasAspect: canvas.width / canvas.height)
            let plan: EncoderPlan = (
                CGSize(width: size.width, height: size.height),
                StreamEncoding(
                    segmentSeconds: options.usable.keyFrameSeconds, bitsPerSecond: options.videoBitsPerSecond,
                    framesPerSecond: framesPerSecond, codec: options.codec
                ),
                current.carriesSound ? options.sound : nil
            )
            let encoder = makeEncoder(plan, SegmentCallbacks(
                initialization: { [weak self] in self?.received(initialization: $0) },
                segment: { [weak self] in self?.received(segment: $0, duration: $1) }
            ))
            current.encoder = encoder
            current.startedAt = now
            return (encoder, 0)
        }
        if let job {
            job.encoder.append(pixelBuffer, at: job.seconds)
        }
    }

    public func send(_ sound: CMSampleBuffer) {
        let job: (encoder: SegmentEncoding, start: Double)? = state.update { current in
            current.hasHeardSound = true
            guard current.carriesSound, let encoder = current.encoder, let start = current.startedAt else { return nil }
            return (encoder, start)
        }
        if let job {
            job.encoder.appendSound(sound, startingFrom: job.start)
        }
    }

    /// Marks a scene coming on air, when the stream is set to. An HLS
    /// stream notes it in its playlist; an endless MP4 carries it as an
    /// event between its pieces.
    public func markScene(named name: String) {
        let now = clock()
        let moment = today()
        let event: Data? = state.update { current in
            guard current.settings.isOn, current.settings.options.marksScenes else { return nil }
            current.markerCount += 1
            guard kind == .movie else {
                current.window.mark(scene: name, at: moment)
                return nil
            }
            // An event in an MP4 is placed in the stream's own time, which
            // has only begun once there has been a frame.
            return current.startedAt.map {
                EventMessageBox.data(scene: name, number: current.markerCount, atSeconds: now - $0)
            }
        }
        if let event {
            server.broadcast(event)
        }
    }

    /// What a player asking for an address gets.
    func reply(to request: HTTPRequest) -> StreamReply {
        let current = state.get()
        let window = current.window
        // An HLS stream and an endless MP4 each answer their own addresses.
        switch (kind, WebStreamRoute(path: request.path)) {
        case (.hls, .page):
            return .whole(HTTPResponse(contentType: .page, body: Data(WebStreamPage.html(title: title).utf8)))
        case (.hls, .playlist):
            return .whole(HTTPResponse(contentType: .playlist, body: Data(HLSPlaylist.text(for: window).utf8)))
        case (.hls, .initialization):
            return window.initialization.map { .whole(HTTPResponse(contentType: .video, body: $0)) } ?? .whole(.missing)
        case (.hls, .segment(let sequence)):
            return window.segment(numbered: sequence).map { .whole(HTTPResponse(contentType: .video, body: $0.data)) }
                ?? .whole(.missing)
        case (.movie, .movie):
            // The header now, then every piece as it is made.
            return .live(HTTPResponse.head(contentType: .video, length: nil) + (window.initialization ?? Data()))
        default:
            return .whole(.missing)
        }
    }

    private func received(initialization data: Data) {
        state.update { $0.window.setInitialization(data) }
        server.broadcast(data)
    }

    private func received(segment data: Data, duration: Double) {
        let moment = today()
        state.update { current in
            // The first piece to arrive has just ended, which says when the stream began.
            current.window.setOrigin(moment.addingTimeInterval(-duration))
            current.window.append(data, duration: duration)
        }
        server.broadcast(data)
    }

    private func failed(_ message: String) {
        state.update { $0.status = .failed(message) }
    }
}
