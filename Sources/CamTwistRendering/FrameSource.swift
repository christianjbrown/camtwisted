import CamTwistCore
import CoreImage

/// Something that produces pictures: a camera, a display, a movie.
public protocol FrameSource: AnyObject {
    func start()
    func stop()
    /// The most recent picture, or nil when there is nothing to show.
    var latestFrame: CIImage? { get }
    /// Adopts changed settings while running. Returns false when the change
    /// needs a fresh source instead, such as a different camera.
    func update(to spec: SourceSpec) -> Bool
}

/// Makes the sources of one kind. Returns nil for specs that are not its kind.
public protocol SourceProvider {
    func makeSource(for spec: SourceSpec) -> FrameSource?
}

/// Holds the latest frame behind a lock: capture callbacks write it on their
/// own queues and the render loop reads it on another.
final class LatestFrameBox {
    private let lock = NSLock()
    private var frame: CIImage?

    func store(_ frame: CIImage?) {
        lock.lock()
        self.frame = frame
        lock.unlock()
    }

    func load() -> CIImage? {
        lock.lock()
        defer { lock.unlock() }
        return frame
    }
}

/// A value shared between threads.
final class Locked<Value> {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: Value) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    /// Changes the value in one step, so that two threads changing it at
    /// once cannot undo each other, and hands back whatever the change makes.
    func update<Result>(_ change: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return change(&value)
    }
}
