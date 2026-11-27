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

/// Turns what the microphone hears into words, on this Mac.
public protocol SpeechTranscribing: AnyObject {
    /// The words heard lately. Safe to read from any thread.
    var heard: HeardSpeech { get }
    func start()
    func stop()
}

/// One transcriber shared by every captions effect showing at once, so a
/// scene on air and the same scene in a preview listen only once. It
/// listens while anything has joined and stops when the last one leaves.
public final class SharedSpeechListener {
    private let transcriber: SpeechTranscribing
    private let lock = NSLock()
    private var listeners = 0

    public init(transcriber: SpeechTranscribing) {
        self.transcriber = transcriber
    }

    var heard: HeardSpeech { transcriber.heard }

    /// A listener that never hears anything, for anything that has no
    /// microphone to listen to.
    public static let silent = SharedSpeechListener(transcriber: SilentTranscriber())

    /// What listens on this Mac, with the system's speech recognition.
    public static func onThisMac(now: @escaping () -> Date) -> SharedSpeechListener {
        SharedSpeechListener(transcriber: AppleSpeechTranscriber(now: now))
    }

    func join() {
        lock.withLock {
            listeners += 1
            if listeners == 1 { transcriber.start() }
        }
    }

    /// Only for something that has joined.
    func leave() {
        lock.withLock {
            listeners -= 1
            if listeners == 0 { transcriber.stop() }
        }
    }
}

/// Hears nothing, ever.
final class SilentTranscriber: SpeechTranscribing {
    let heard = HeardSpeech.nothing
    func start() {}
    func stop() {}
}
