import CoreMedia
import Foundation

/// A source that makes sound as well as pictures.
public protocol SoundSource: AnyObject {
    /// Where the source hands its sound, as it is made. Nil when nobody is listening.
    var onSound: ((CMSampleBuffer) -> Void)? { get set }
}

/// Mixes sound from several places into one.
public protocol SoundMixing: AnyObject {
    /// Takes sound from a source in the scene, named by its step.
    func feed(_ sound: CMSampleBuffer, from input: UUID)
    /// Sets how loud an input is, from 0 to 1.
    func setLevel(_ level: Double, for input: UUID)
    func remove(_ input: UUID)
}

/// Sets which sources are heard and how loud.
public protocol SoundRouting {
    func apply(levels: [UUID: Double])
}

/// Decides which sources are heard and how loud, and connects their sound
/// to the mix.
public final class SoundRouter: SoundRouting {
    private let mixer: SoundMixing
    private let source: (UUID) -> SoundSource?
    private let lock = NSLock()
    private var connected: Set<UUID> = []
    private var wanted: [UUID: Double] = [:]

    /// - Parameter source: finds the running source for a step, when it is
    ///   one that makes sound.
    public init(mixer: SoundMixing, source: @escaping (UUID) -> SoundSource?) {
        self.mixer = mixer
        self.source = source
    }

    /// Sets the levels of the sources that should be heard. Any other
    /// source falls silent. It is safe to call again with the same levels:
    /// a source that was not running yet is connected once it is.
    public func apply(levels: [UUID: Double]) {
        lock.lock()
        defer { lock.unlock() }
        for id in wanted.keys where levels[id] == nil {
            source(id)?.onSound = nil
            mixer.remove(id)
            connected.remove(id)
        }
        wanted = levels
        for (id, level) in levels {
            mixer.setLevel(level, for: id)
            guard !connected.contains(id), let sounding = source(id) else { continue }
            sounding.onSound = { [weak mixer] in mixer?.feed($0, from: id) }
            connected.insert(id)
        }
    }
}
