import AVFoundation
import Foundation
import Speech

/// Listens to the Mac's microphone and writes down what is said with the
/// system's own speech recognition. Recognition is held to this Mac, so
/// nothing that is said leaves it. A recognition ends by itself after a
/// pause or a minute or so; a fresh one follows on while still listening.
final class AppleSpeechTranscriber: SpeechTranscribing {
    private enum Listening {
        static let bus: AVAudioNodeBus = 0
        static let bufferFrames: AVAudioFrameCount = 1024
        /// A pause before a recognition that ended is followed by another,
        /// so one that fails at once does not spin.
        static let restartDelay: TimeInterval = 1
    }

    private let now: () -> Date
    private let queue = DispatchQueue(label: "camtwisted.captions")
    private let lock = NSLock()
    private let engine = AVAudioEngine()
    // Made only once listening starts: making one asks for permission.
    private lazy var recognizer = SFSpeechRecognizer()
    private var latest = HeardSpeech.nothing
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isListening = false

    init(now: @escaping () -> Date) {
        self.now = now
    }

    var heard: HeardSpeech { lock.withLock { latest } }

    func start() {
        queue.async {
            self.isListening = true
            SFSpeechRecognizer.requestAuthorization { status in
                self.queue.async {
                    guard status == .authorized, self.isListening else { return }
                    self.beginHearing()
                }
            }
        }
    }

    func stop() {
        queue.async {
            // Never started, so nothing to stop, and the microphone is not touched.
            guard self.isListening else { return }
            self.isListening = false
            self.engine.inputNode.removeTap(onBus: Listening.bus)
            self.engine.stop()
            self.endRecognition()
            self.lock.withLock { self.latest = .nothing }
        }
    }

    private func beginHearing() {
        guard !engine.isRunning else { return }
        let input = engine.inputNode
        input.installTap(
            onBus: Listening.bus, bufferSize: Listening.bufferFrames, format: input.outputFormat(forBus: Listening.bus)
        ) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.withLock { self.request }?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: Listening.bus)
            return
        }
        beginRecognition()
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
