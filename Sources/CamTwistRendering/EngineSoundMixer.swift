import AVFoundation
import CamTwistCore
import CoreMedia
import Foundation

/// Mixes with the system's audio engine: each input plays into a mixer
/// that nobody hears, and what comes out of that mixer goes to the outputs
/// that carry sound.
public final class EngineSoundMixer: SoundMixing {
    private struct Input {
        let node: AVAudioPlayerNode
        var format: AVAudioFormat?
    }

    private let sinks: [SoundSink]
    /// The label of the queue the sound mixer runs on.
    public static let queueLabel = "output.sound.mixer"
    private let queue: DispatchQueue
    private let makeNode: () -> AVAudioPlayerNode
    private let engine = AVAudioEngine()
    private let bus = AVAudioMixerNode()
    private var inputs: [UUID: Input] = [:]
    private var levels: [UUID: Double] = [:]
    private var isTapped = false
    /// Samples handed on in one go.
    private let tapSize: AVAudioFrameCount

    public init(
        sinks: [SoundSink], tapFrames: Int, queue: DispatchQueue, makeNode: @escaping () -> AVAudioPlayerNode
    ) {
        self.queue = queue
        self.makeNode = makeNode
        self.sinks = sinks
        tapSize = AVAudioFrameCount(tapFrames)
    }

    public func feed(_ sound: CMSampleBuffer, from input: UUID) {
        guard let buffer = SoundBuffers.pcmBuffer(from: sound) else { return }
        queue.async { [weak self] in self?.play(buffer, from: input) }
    }

    public func setLevel(_ level: Double, for input: UUID) {
        queue.async { [weak self] in
            self?.levels[input] = level
            self?.inputs[input]?.node.volume = Float(level)
        }
    }

    public func remove(_ input: UUID) {
        queue.async { [weak self] in
            guard let self, let removed = self.inputs.removeValue(forKey: input) else { return }
            self.levels[input] = nil
            removed.node.stop()
            self.engine.detach(removed.node)
            if self.inputs.isEmpty {
                self.engine.stop()
            }
        }
    }

    private func play(_ buffer: AVAudioPCMBuffer, from input: UUID) {
        prepareEngine()
        var entry = inputs[input] ?? Input(node: makeNode(), format: nil)
        if entry.format != buffer.format {
            // New here, or it has changed how it sounds: it is wired in to match.
            if entry.format == nil {
                engine.attach(entry.node)
            } else {
                engine.disconnectNodeOutput(entry.node)
            }
            engine.connect(entry.node, to: bus, format: buffer.format)
            entry.format = buffer.format
            entry.node.volume = Float(levels[input] ?? SceneSound.full)
            inputs[input] = entry
        }
        if !engine.isRunning {
            try? engine.start()
        }
        if !entry.node.isPlaying {
            entry.node.play()
        }
        entry.node.scheduleBuffer(buffer)
    }

    /// Wires the hidden mixer in and starts listening to what comes out of it.
    private func prepareEngine() {
        guard !isTapped else { return }
        isTapped = true
        engine.attach(bus)
        engine.connect(bus, to: engine.mainMixerNode, format: nil)
        // The mix is for the streams, not for the room.
        engine.mainMixerNode.outputVolume = 0
        let sinks = self.sinks
        bus.installTap(onBus: 0, bufferSize: tapSize, format: nil) { buffer, time in
            guard let sound = SoundBuffers.sampleBuffer(from: buffer, atSeconds: SoundBuffers.seconds(of: time, now: SteadyClock.uptime)) else { return }
            sinks.forEach { $0.send(sound) }
        }
    }
}
