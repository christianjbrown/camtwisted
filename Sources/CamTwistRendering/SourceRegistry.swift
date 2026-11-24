import CamTwistCore
import CoreImage

/// What a renderer needs to read from the running sources.
public protocol SourceFrameSupplying {
    /// The latest picture of a chain step's source, or nil when it has none.
    func latestFrame(for id: UUID) -> CIImage?
}

/// What the render loop needs to say about which sources the scenes use.
public protocol SourceSwitching {
    /// Runs exactly the sources wanted, one per chain step.
    func setSourcesInUse(_ wanted: [UUID: SourceSpec])
}

/// Everything the render loop asks of the sources: which are wanted, and their pictures.
public protocol SourceSupplying: SourceFrameSupplying, SourceSwitching {}

/// Keeps exactly the sources the scenes use running, one per chain step,
/// and hands out their latest frames.
public final class SourceRegistry: SourceSupplying {
    private struct Running {
        var spec: SourceSpec
        let source: FrameSource
    }

    private let providers: [SourceProvider]
    private let lock = NSLock()
    private var running: [UUID: Running] = [:]

    public init(providers: [SourceProvider]) {
        self.providers = providers
    }

    /// Starts sources that are newly needed, stops ones that no longer are,
    /// and passes changed settings on to the ones that stay.
    public func setSourcesInUse(_ wanted: [UUID: SourceSpec]) {
        lock.lock()
        defer { lock.unlock() }
        for (id, entry) in running where wanted[id] == nil {
            entry.source.stop()
            running[id] = nil
        }
        for (id, spec) in wanted {
            if let entry = running[id] {
                guard entry.spec != spec else { continue }
                if entry.source.update(to: spec) {
                    running[id]?.spec = spec
                    continue
                }
                entry.source.stop()
                running[id] = nil
            }
            guard let source = makeSource(for: spec) else { continue }
            source.start()
            running[id] = Running(spec: spec, source: source)
        }
    }

    public func latestFrame(for id: UUID) -> CIImage? {
        source(for: id)?.latestFrame
    }

    /// The running source for a chain step, for callers that need more than
    /// its frames.
    public func source(for id: UUID) -> FrameSource? {
        lock.lock()
        defer { lock.unlock() }
        return running[id]?.source
    }

    private func makeSource(for spec: SourceSpec) -> FrameSource? {
        for provider in providers {
            if let source = provider.makeSource(for: spec) {
                return source
            }
        }
        return nil
    }
}
