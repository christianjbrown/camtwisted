import AVFoundation
import CamTwistCore
import CoreAudio
import CoreMedia
import Foundation

/// Plays the mix to the virtual microphone's hidden feed, so that whatever
/// app has the microphone picked hears it. Does nothing until the audio
/// driver is installed.
public final class VirtualMicrophoneSink: SoundSink {
    /// The label of the queue that feeds the virtual microphone.
    public static let queueLabel = "output.microphone"
    private let queue: DispatchQueue
    private let wanted = Locked(false)
    private var engine: AVAudioEngine?
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var looks: AttemptThrottle
    private let clock: () -> TimeInterval

    /// - Parameter lookInterval: how long to leave it before looking for the feed again when it
    ///   is not there, rather than asking the system on every buffer.
    public init(lookInterval: TimeInterval, clock: @escaping () -> TimeInterval, queue: DispatchQueue) {
        self.queue = queue
        self.looks = AttemptThrottle(interval: lookInterval)
        self.clock = clock
    }

    /// Whether the system has the microphone: whether the driver is installed.
    public static var isInstalled: Bool { feedDevice() != nil }

    public var isEnabled: Bool {
        get { wanted.get() }
        set {
            wanted.update { $0 = newValue }
            if !newValue {
                queue.async { [weak self] in self?.stop() }
            }
        }
    }

    public func send(_ sound: CMSampleBuffer) {
        guard wanted.get(), let buffer = SoundBuffers.pcmBuffer(from: sound) else { return }
        queue.async { [weak self] in self?.play(buffer) }
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        guard wanted.get(), let engine = runningEngine() else { return }
        if format != buffer.format {
            // New here, or the mix has changed how it sounds: wired in to match.
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            format = buffer.format
        }
        if !engine.isRunning {
            try? engine.start()
        }
        guard engine.isRunning else { return }
        if !player.isPlaying {
            player.play()
        }
        player.scheduleBuffer(buffer)
    }

    /// The engine that plays to the feed, made the first time the feed is found.
    private func runningEngine() -> AVAudioEngine? {
        if let engine {
            return engine
        }
        guard looks.permits(at: clock()) else { return nil }
        guard let device = Self.feedDevice() else { return nil }
        let made = AVAudioEngine()
        guard (try? made.outputNode.auAudioUnit.setDeviceID(device)) != nil else { return nil }
        made.attach(player)
        engine = made
        return made
    }

    private func stop() {
        guard let engine else { return }
        player.stop()
        engine.stop()
        engine.detach(player)
        self.engine = nil
        format = nil
        looks.reset()
    }

    /// The feed device, when the driver is installed.
    private static func feedDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid = MicrophoneContract.feedUID as CFString
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        // The name is handed over as a pointer to the reference itself,
        // which is what this property asks for.
        let status = withUnsafePointer(to: &uid) { name in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), name, &size,
                &device
            )
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
}
