import CoreMedia
import Foundation

/// Listens to the sound the sources in a scene make, by step.
public protocol SoundTapping: AnyObject {
    /// Hands a source's sound to `handler` as it is made. Safe to call
    /// again with the same key: it replaces the handler, and connects a
    /// source that was not running before or has been started afresh.
    func listen(to source: UUID, as key: ObjectIdentifier, _ handler: @escaping (CMSampleBuffer) -> Void)
    func stopListening(to source: UUID, as key: ObjectIdentifier)
}

/// Hands each source's sound to everything listening to it, such as the
/// mix the streams carry and the captions that write it down. A source
/// takes one listener, so this is that one listener, and passes it on.
public final class SoundTaps: SoundTapping {
    /// The running source a step's sound comes from. Held weakly, so one
    /// that is replaced or gone is connected afresh.
    private struct Connection {
        weak var source: SoundSource?
    }

    private let source: (UUID) -> SoundSource?
    private let lock = NSLock()
    private var handlers: [UUID: [ObjectIdentifier: (CMSampleBuffer) -> Void]] = [:]
    private var connections: [UUID: Connection] = [:]

    /// - Parameter source: finds the running source for a step, when it is
    ///   one that makes sound.
    public init(source: @escaping (UUID) -> SoundSource?) {
        self.source = source
    }

    public func listen(to id: UUID, as key: ObjectIdentifier, _ handler: @escaping (CMSampleBuffer) -> Void) {
        let sounding = source(id)
        lock.withLock {
            handlers[id, default: [:]][key] = handler
            guard let sounding, connections[id]?.source !== sounding else { return }
            connections[id] = Connection(source: sounding)
            sounding.onSound = { [weak self] in self?.hand($0, from: id) }
        }
    }

    public func stopListening(to id: UUID, as key: ObjectIdentifier) {
        let sounding = source(id)
        lock.withLock {
            handlers[id]?[key] = nil
            // Still wanted by someone else, so it stays connected.
            guard handlers[id]?.isEmpty != false else { return }
            handlers[id] = nil
            connections[id] = nil
            sounding?.onSound = nil
        }
    }

    private func hand(_ sound: CMSampleBuffer, from id: UUID) {
        let listening = lock.withLock { handlers[id].map { Array($0.values) } ?? [] }
        listening.forEach { $0(sound) }
    }
}
