import CamTwistCore
import Foundation

/// What has been said lately, and when the words last changed.
public struct HeardSpeech: Equatable, Sendable {
    public var words: String
    public var when: Date

    public init(words: String, when: Date) {
        self.words = words
        self.when = when
    }

    /// Before anything has been said.
    public static let nothing = HeardSpeech(words: "", when: .distantPast)
}

/// Turns sound it is sent into words, on this Mac.
public protocol SpeechTranscribing: SoundSink {
    /// The words heard lately. Safe to read from any thread.
    var heard: HeardSpeech { get }
    func start()
    func stop()
}

/// The sources a captions step hears, each with how loud it is. A source
/// turned right down is not heard at all.
public struct HeardSources: Hashable, Sendable {
    public let levels: [UUID: Double]

    public init(levels: [UUID: Double]) {
        self.levels = levels.filter { $0.value > SceneSound.silent }
    }

    /// Nothing to hear.
    public static let none = HeardSources(levels: [:])

    var isEmpty: Bool { levels.isEmpty }
}

/// What captions listen through: the words said in some sources.
public protocol CaptionsListening: AnyObject {
    /// Starts hearing some sources, for one more captions step.
    func join(_ sources: HeardSources)
    /// Only for sources that were joined.
    func leave(_ sources: HeardSources)
    /// The words heard lately in sources that were joined. Each call also
    /// connects any of them that have started since.
    func heard(from sources: HeardSources) -> HeardSpeech
}

/// Writing down what is said in one set of sources: their sound, mixed at
/// their levels, turned into words.
public protocol CaptionSession: AnyObject {
    var heard: HeardSpeech { get }
    func start()
    /// Connects any of the sources that have started since.
    func refresh()
    func stop()
}

/// Shares one session between every captions step hearing the same
/// sources at the same levels, so a scene on air and the same scene in a
/// preview are written down only once. A session runs while anything has
/// joined it and stops when the last one leaves.
public final class CaptionsHub: CaptionsListening {
    private struct Shared {
        let session: CaptionSession
        var listeners: Int
    }

    private let makeSession: (HeardSources) -> CaptionSession
    private let lock = NSLock()
    private var sessions: [HeardSources: Shared] = [:]

    public init(makeSession: @escaping (HeardSources) -> CaptionSession) {
        self.makeSession = makeSession
    }

    /// Hears nothing, for anything with no sound to listen to.
    public static let silent = CaptionsHub { _ in SilentCaptionSession() }

    public func join(_ sources: HeardSources) {
        lock.withLock {
            if var shared = sessions[sources] {
                shared.listeners += 1
                sessions[sources] = shared
                return
            }
            let session = makeSession(sources)
            sessions[sources] = Shared(session: session, listeners: 1)
            session.start()
        }
    }

    public func leave(_ sources: HeardSources) {
        lock.withLock {
            guard var shared = sessions[sources] else { return }
            shared.listeners -= 1
            guard shared.listeners == 0 else {
                sessions[sources] = shared
                return
            }
            sessions[sources] = nil
            shared.session.stop()
        }
    }

    public func heard(from sources: HeardSources) -> HeardSpeech {
        guard let session = lock.withLock({ sessions[sources]?.session }) else { return .nothing }
        session.refresh()
        return session.heard
    }
}

/// Hears nothing, ever.
final class SilentCaptionSession: CaptionSession {
    let heard = HeardSpeech.nothing
    func start() {}
    func refresh() {}
    func stop() {}
}

/// Mixes the sources' sound at their levels and sends the mix to be
/// written down.
public final class MixedCaptionSession: CaptionSession {
    private let sources: HeardSources
    private let taps: SoundTapping
    private let mixer: SoundMixing
    private let transcriber: SpeechTranscribing

    /// - Parameter mixer: mixes for this session alone, and sends what it
    ///   mixes to the transcriber.
    public init(sources: HeardSources, taps: SoundTapping, mixer: SoundMixing, transcriber: SpeechTranscribing) {
        self.sources = sources
        self.taps = taps
        self.mixer = mixer
        self.transcriber = transcriber
    }

    public var heard: HeardSpeech { transcriber.heard }

    public func start() {
        transcriber.start()
        for (id, level) in sources.levels {
            mixer.setLevel(level, for: id)
        }
        refresh()
    }

    public func refresh() {
        for id in sources.levels.keys {
            taps.listen(to: id, as: ObjectIdentifier(self)) { [weak mixer] in mixer?.feed($0, from: id) }
        }
    }

    public func stop() {
        for id in sources.levels.keys {
            taps.stopListening(to: id, as: ObjectIdentifier(self))
            mixer.remove(id)
        }
        transcriber.stop()
    }
}
