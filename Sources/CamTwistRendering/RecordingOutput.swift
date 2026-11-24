import CamTwistCore
import CoreMedia
import CoreVideo
import Foundation

/// Records the picture on air and its sound to a movie, with a chapter
/// for each scene that goes on air.
public final class RecordingOutput: FrameSink, SoundSink {
    private struct State {
        /// The folder a recording is wanted in, while one is wanted.
        var folder: URL?
        var sceneName = ""
        /// How the recording is to be made, as it stood when it was switched on.
        var options = RecordingOptions()
        var writer: MovieWriting?
        var startedAt: Double?
        var status = RecordingStatus.off
    }

    private static let cannotStart = "The recording could not be started in that folder."

    private let makeWriter: (URL, RecordingPlan) throws -> MovieWriting
    /// Bits a second for each pixel of the picture, when its bit rate is left to the app.
    private let bitsPerPixelPerSecond: Int
    private let clock: () -> Double
    private let today: () -> Date
    private let state = Locked(State())

    /// - Parameters:
    ///   - soundRate: samples a second in the sound of a recording.
    ///   - bitsPerPixelPerSecond: bits a second for each pixel of the
    ///     picture, when its bit rate is left to the app.
    ///   - clocks: what the recording is timed and its file named by.
    public convenience init(soundRate: Int, bitsPerPixelPerSecond: Int, clocks: Clocks) {
        self.init(
            makeWriter: { try ChapteredMovieWriter(url: $0, plan: $1, soundRate: soundRate) },
            bitsPerPixelPerSecond: bitsPerPixelPerSecond,
            clock: clocks.uptime, today: clocks.today
        )
    }

    init(
        makeWriter: @escaping (URL, RecordingPlan) throws -> MovieWriting, bitsPerPixelPerSecond: Int,
        clock: @escaping () -> Double, today: @escaping () -> Date
    ) {
        self.makeWriter = makeWriter
        self.bitsPerPixelPerSecond = bitsPerPixelPerSecond
        self.clock = clock
        self.today = today
    }

    public var status: RecordingStatus { state.get().status }

    /// Starts a recording in a folder, or ends the one under way. The
    /// recording begins with the next frame, in a chapter named after the
    /// scene on air. The options are taken when it is switched on, and a
    /// recording under way keeps the ones it began with.
    public func apply(isOn: Bool, folder: URL, sceneName: String, options: RecordingOptions) {
        let now = clock()
        let ending: (writer: MovieWriting, seconds: Double)? = state.update { current in
            if isOn {
                // Already wanted: a recording under way, or one that failed, is left as it is.
                guard current.folder == nil else { return nil }
                current.folder = folder
                current.sceneName = sceneName
                current.options = options
                current.status = .off
                return nil
            }
            let ending = current.writer.flatMap { writer in current.startedAt.map { (writer, now - $0) } }
            current = State()
            return ending
        }
        if let ending {
            ending.writer.finish(at: ending.seconds) {}
        }
    }

    /// A different scene has come on air: a new chapter starts.
    public func markScene(named name: String) {
        let now = clock()
        let chapter: (writer: MovieWriting, seconds: Double)? = state.update { current in
            current.sceneName = name
            return current.writer.flatMap { writer in current.startedAt.map { (writer, now - $0) } }
        }
        if let chapter {
            chapter.writer.startChapter(named: name, at: chapter.seconds)
        }
    }

    public func send(_ pixelBuffer: CVPixelBuffer) {
        let now = clock()
        let job: (writer: MovieWriting, seconds: Double)? = state.update { current in
            guard let folder = current.folder else { return nil }
            if let writer = current.writer, let start = current.startedAt {
                return (writer, now - start)
            }
            guard current.status == .off else { return nil }
            // The recording begins with its first frame, which gives it its shape.
            let aspect = Double(CVPixelBufferGetWidth(pixelBuffer)) / Double(CVPixelBufferGetHeight(pixelBuffer))
            let plan = RecordingRules.plan(
                for: current.options, canvasAspect: aspect, automaticBitsPerPixelPerSecond: bitsPerPixelPerSecond
            )
            let name = RecordingName.fileName(startingAt: today(), as: plan.container)
            guard let writer = try? makeWriter(folder.appendingPathComponent(name), plan) else {
                current.status = .failed(Self.cannotStart)
                return nil
            }
            writer.startChapter(named: current.sceneName, at: 0)
            current.writer = writer
            current.startedAt = now
            current.status = .recording(name)
            return (writer, 0)
        }
        if let job {
            job.writer.append(pixelBuffer, at: job.seconds)
        }
    }

    public func send(_ sound: CMSampleBuffer) {
        let current = state.get()
        if let writer = current.writer, let start = current.startedAt {
            writer.appendSound(sound, startingFrom: start)
        }
    }
}
