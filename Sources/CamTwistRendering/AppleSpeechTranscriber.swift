import AVFoundation
import Foundation
import Speech

/// Writes down what is said in the sound it is sent, with the system's
/// older speech recognition, for Macs before macOS 26. It needs Siri and
/// Dictation switched on. Recognition is held to this Mac, so nothing
/// that is said leaves it. A recognition ends by itself after a pause or a
/// minute or so; a fresh one follows on while still listening.
public final class AppleSpeechTranscriber: SpeechTranscribing {
    private enum Listening {
        /// A pause before a recognition that ended is followed by another,
        /// so one that fails at once does not spin.
        static let restartDelay: TimeInterval = 1
    }

    private let now: () -> Date
    private let queue = DispatchQueue(label: "camtwisted.captions")
    private let lock = NSLock()
    // Made only once listening starts: making one asks for permission.
    private lazy var recognizer = SFSpeechRecognizer()
    private var latest = HeardSpeech.nothing
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isListening = false

    public init(now: @escaping () -> Date) {
        self.now = now
    }

    public var heard: HeardSpeech { lock.withLock { latest } }

    public func send(_ sound: CMSampleBuffer) {
        guard let request = lock.withLock({ request }), let buffer = SoundBuffers.pcmBuffer(from: sound) else { return }
        request.append(buffer)
    }

    public func start() {
        queue.async {
            self.isListening = true
            SFSpeechRecognizer.requestAuthorization { status in
                self.queue.async {
                    guard status == .authorized, self.isListening else { return }
                    self.beginRecognition()
                }
            }
        }
    }

    public func stop() {
        queue.async {
            guard self.isListening else { return }
            self.isListening = false
            self.endRecognition()
            self.lock.withLock { self.latest = .nothing }
        }
    }

    private func beginRecognition() {
        guard isListening, let recognizer, recognizer.isAvailable else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        lock.withLock { self.request = request }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let words = result.bestTranscription.formattedString
                self.lock.withLock { self.latest = HeardSpeech(words: words, when: self.now()) }
            }
            guard error != nil || result?.isFinal == true else { return }
            self.queue.asyncAfter(deadline: .now() + Listening.restartDelay) {
                guard self.isListening, self.lock.withLock({ self.request === request }) else { return }
                self.endRecognition()
                self.beginRecognition()
            }
        }
    }

    private func endRecognition() {
        lock.withLock { request }?.endAudio()
        task?.cancel()
        task = nil
        lock.withLock { request = nil }
    }
}
