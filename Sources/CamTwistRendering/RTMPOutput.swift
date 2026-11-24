import CamTwistCore
import CoreMedia
import CoreVideo
import Foundation

/// Sends the picture on air to an RTMP server, while switched on.
public final class RTMPOutput: FrameSink, SoundSink {
    private struct State {
        var settings = RTMPSettings()
        var wantsSound = false
        var soundEncoder: SoundEncoding?
        /// Whether the sound decoder's details have gone out.
        var hasSentSoundHeader = false
        /// When the next packet of sound belongs, in seconds since the stream began.
        var soundClock: Double?
        /// What the stream's sound is like, when it has any.
        var soundFormat: SoundFormat?
        var status = RTMPState.idle
        var session: RTMPSession?
        var connection: StreamConnecting?
        var encoder: FrameEncoding?
        var startedAt: Double?
        /// Whether the decoder's details have gone out, which must be first.
        var hasSentHeader = false
    }

    private static let badAddress = "Enter a server address that starts rtmp:// or rtmps://, and a stream key"
    private static let millisecondsPerSecond = 1000.0

    private let canvas: CGSize
    private let framesPerSecond: Int32
    private let makeConnection: () -> StreamConnecting
    private let makeEncoder: (CGSize, StreamEncoding, @escaping (EncodedFrame) -> Void) -> FrameEncoding
    private let makeSoundEncoder: (SoundFormat) -> SoundEncoding
    private let clock: () -> Double
    private let state = Locked(State())
    /// How many bytes each chunk sent to the server holds.
    private let chunkSize: Int

    /// - Parameters:
    ///   - canvas: the size the picture is drawn at, which gives the stream its shape.
    ///   - chunkSize: how many bytes each chunk sent to the server holds.
    ///   - largestRead: the most bytes taken from the network in one go.
    ///   - queues: makes the queue each connection runs on.
    ///   - clocks: what frames are timed by.
    public convenience init(
        canvas: CGSize, framesPerSecond: Int32, chunkSize: Int, largestRead: Int, queues: QueueMaking, clocks: Clocks
    ) {
        self.init(
            canvas: canvas, framesPerSecond: framesPerSecond,
            makeConnection: {
                RTMPConnection(
                    largestRead: largestRead, queue: queues.makeQueue(label: RTMPConnection.queueLabel, qos: .default)
                )
            },
            makeEncoder: { H264Encoder(size: $0, encoding: $1, output: $2) },
            makeSoundEncoder: { AACEncoder(format: $0) },
            clock: clocks.uptime,
            chunkSize: chunkSize
        )
    }

    init(
        canvas: CGSize,
        framesPerSecond: Int32,
        makeConnection: @escaping () -> StreamConnecting,
        makeEncoder: @escaping (CGSize, StreamEncoding, @escaping (EncodedFrame) -> Void) -> FrameEncoding,
        makeSoundEncoder: @escaping (SoundFormat) -> SoundEncoding,
        clock: @escaping () -> Double,
        chunkSize: Int = Pacing.usual.streamChunkSize
    ) {
        self.canvas = canvas
        self.framesPerSecond = framesPerSecond
        self.makeConnection = makeConnection
        self.makeEncoder = makeEncoder
        self.makeSoundEncoder = makeSoundEncoder
        self.clock = clock
        self.chunkSize = chunkSize
    }

    /// How far the stream has got.
    public var status: RTMPState { state.get().status }

    /// Starts, stops or moves the stream to match the settings, with or
    /// without sound from the microphone.
    public func apply(_ settings: RTMPSettings, withSound: Bool) {
        let opening: (connection: StreamConnecting, target: RTMPTarget)? = state.update { current in
            guard settings != current.settings || withSound != current.wantsSound else { return nil }
            current.connection?.close()
            current.encoder?.finish()
            current = State()
            current.settings = settings
            current.wantsSound = withSound
            guard settings.isOn else { return nil }
            guard let target = RTMPTarget(address: settings.address, streamKey: settings.streamKey) else {
                current.status = .failed(Self.badAddress)
                return nil
            }
            let options = settings.options
            let size = options.pictureSize(canvasAspect: canvas.width / canvas.height)
            let encoding = StreamEncoding(
                segmentSeconds: options.usable.keyFrameSeconds, bitsPerSecond: options.videoBitsPerSecond,
                framesPerSecond: framesPerSecond
            )
            let sound = withSound ? options.sound : nil
            let connection = makeConnection()
            current.connection = connection
            current.session = RTMPSession(
                target: target,
                details: RTMPVideoDetails(
                    width: size.width, height: size.height, framesPerSecond: Int(framesPerSecond),
                    bitsPerSecond: options.videoBitsPerSecond
                ),
                sound: sound,
                chunkSize: chunkSize
            )
            current.soundFormat = sound
            current.soundEncoder = sound.map(makeSoundEncoder)
            current.status = .connecting
            current.encoder = makeEncoder(CGSize(width: size.width, height: size.height), encoding) { [weak self] in
                self?.encoded($0)
            }
            return (connection, target)
        }
        if let opening {
            opening.connection.open(
                to: opening.target,
                onReady: { [weak self] in self?.connected() },
                onReceive: { [weak self] in self?.received($0) },
                onFailure: { [weak self] in self?.failed($0) }
            )
        }
    }

    public func send(_ pixelBuffer: CVPixelBuffer) {
        let now = clock()
        // Nothing is compressed until the server is taking the stream.
        let job: (encoder: FrameEncoding, milliseconds: UInt32)? = state.update { current in
            guard current.status == .live, let encoder = current.encoder else { return nil }
            let start = current.startedAt ?? now
            current.startedAt = start
            return (encoder, UInt32((now - start) * Self.millisecondsPerSecond))
        }
        if let job {
            job.encoder.encode(pixelBuffer, atMilliseconds: job.milliseconds)
        }
    }

    public func send(_ sound: CMSampleBuffer) {
        let job: (connection: StreamConnecting?, data: Data)? = state.update { current in
            // Sound joins once the picture has started, so the two share a clock.
            guard current.status == .live, let session = current.session, let encoder = current.soundEncoder,
                  let soundFormat = current.soundFormat, let start = current.startedAt,
                  let header = FLVAudio.sequenceHeader(for: soundFormat)
            else { return nil }
            var output = Data()
            for packet in encoder.encode(sound) {
                // The first packet is placed by when its sound was made; each
                // after it follows on by a packet's length, which keeps them even.
                let time = current.soundClock ?? max(SoundTiming.seconds(of: sound) - start, 0)
                let milliseconds = UInt32(time * Self.millisecondsPerSecond)
                if !current.hasSentSoundHeader {
                    output += session.audio(header, atMilliseconds: milliseconds)
                    current.hasSentSoundHeader = true
                }
                output += session.audio(FLVAudio.frame(packet), atMilliseconds: milliseconds)
                current.soundClock = time + soundFormat.packetSeconds
            }
            return (current.connection, output)
        }
        if let job {
            job.connection?.send(job.data)
        }
    }

    /// Marks a scene coming on air, when the stream is set to and is live.
    public func markScene(named name: String) {
        let now = clock()
        let job: (connection: StreamConnecting?, data: Data)? = state.update { current in
            guard current.settings.options.marksScenes, let session = current.session, let start = current.startedAt
            else { return nil }
            let marker = session.marker(
                scene: name, atMilliseconds: UInt32((now - start) * Self.millisecondsPerSecond)
            )
            return (current.connection, marker)
        }
        if let job {
            job.connection?.send(job.data)
        }
    }

    private func connected() {
        let job: (connection: StreamConnecting?, data: Data?) = state.update { current in
            (current.connection, current.session?.start())
        }
        job.data.map { job.connection?.send($0) }
    }

    private func received(_ data: Data) {
        let job: (connection: StreamConnecting?, data: Data?) = state.update { current in
            let reply = current.session?.received(data)
            // A failure already reported stands; otherwise the session's word is the status.
            if case .failed = current.status {} else {
                current.status = current.session?.state ?? current.status
            }
            return (current.connection, reply)
        }
        job.data.map { job.connection?.send($0) }
    }

    private func failed(_ message: String) {
        state.update { $0.status = .failed(message) }
    }

    /// A compressed frame is ready. The first thing sent is a key frame's
    /// decoder details; frames before that would be no use to anybody.
    private func encoded(_ frame: EncodedFrame) {
        let job: (connection: StreamConnecting?, data: Data)? = state.update { current in
            guard let session = current.session else { return nil }
            var output = Data()
            if !current.hasSentHeader {
                guard let sets = frame.parameterSets,
                      let header = FLVVideo.sequenceHeader(
                          sequenceParameters: sets.sequence, pictureParameters: sets.picture
                      )
                else { return nil }
                output += session.video(header, atMilliseconds: frame.milliseconds)
                current.hasSentHeader = true
            }
            output += session.video(
                FLVVideo.frame(frame.data, isKeyFrame: frame.isKeyFrame), atMilliseconds: frame.milliseconds
            )
            return (current.connection, output)
        }
        if let job {
            job.connection?.send(job.data)
        }
    }
}
