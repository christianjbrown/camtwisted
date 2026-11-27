import AVFoundation
import Foundation
import Speech

/// Writes down what is said in the sound it is sent, with the system's
/// newer speech analysis. It runs on this Mac whether or not Siri and
/// Dictation are switched on, and fetches the words for the Mac's language
/// the first time, if they are not there yet.
@available(macOS 26, *)
public final class AnalyzerSpeechTranscriber: SpeechTranscribing {
    private let now: () -> Date
    private let lock = NSLock()
    private var latest = HeardSpeech.nothing
    private var tail = TranscriptTail()
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var format: AVAudioFormat?
    private var work: Task<Void, Never>?
    private var analyzer: SpeechAnalyzer?

    public init(now: @escaping () -> Date) {
        self.now = now
    }

    public var heard: HeardSpeech { lock.withLock { latest } }

    public func send(_ sound: CMSampleBuffer) {
        guard let buffer = SoundBuffers.pcmBuffer(from: sound),
              let (input, format) = lock.withLock({ self.input.flatMap { input in self.format.map { (input, $0) } } })
        else { return }
        guard let converted = convert(buffer, to: format) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    public func start() {
        lock.withLock {
            guard work == nil else { return }
            work = Task { [weak self] in await self?.listen() }
        }
    }

    public func stop() {
        let (work, input, analyzer) = lock.withLock { () -> (Task<Void, Never>?, AsyncStream<AnalyzerInput>.Continuation?, SpeechAnalyzer?) in
            defer {
                self.work = nil
                self.input = nil
                self.analyzer = nil
                self.converter = nil
                self.latest = .nothing
                self.tail = TranscriptTail()
            }
            return (self.work, self.input, self.analyzer)
        }
        input?.finish()
        work?.cancel()
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private func listen() async {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else { return }
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        do {
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await installation.downloadAndInstall()
            }
            guard !Task.isCancelled,
                  let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { return }
            let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
            let analyzer = SpeechAnalyzer(modules: [module])
            lock.withLock {
                self.format = format
                self.input = input
                self.analyzer = analyzer
            }
            try await analyzer.start(inputSequence: stream)
            for try await result in module.results {
                let text = String(result.text.characters)
                lock.withLock {
                    tail.take(text, isFinal: result.isFinal)
                    latest = HeardSpeech(words: tail.words, when: now())
                }
            }
        } catch {
            // Nothing more is heard; captions stay clear rather than failing the picture.
        }
    }

    /// The sound in the shape the analysis wants it.
    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.format != format else { return buffer }
        let converter = lock.withLock { () -> AVAudioConverter? in
            if self.converter?.inputFormat != buffer.format {
                self.converter = AVAudioConverter(from: buffer.format, to: format)
            }
            return self.converter
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var handedOver = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if handedOver {
                status.pointee = .noDataNow
                return nil
            }
            handedOver = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }
}
