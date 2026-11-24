import CamTwistCore
import CoreImage
import CoreVideo
import Foundation

/// Draws the program picture at the camera's frame rate and hands every
/// finished frame to the program sinks. While a preview scene is set, draws
/// that too for the preview sinks.
public final class RenderLoop {
    private let sources: SourceSupplying
    private let transitionFactory: TransitionFactory
    /// What an unknown transition name is drawn as.
    private let fallbackTransition: TransitionEffect
    private let programSinks: [FrameSink]
    /// Sinks that only take the camera's own size, whatever is being drawn.
    private let contractSinks: [FrameSink]
    private let previewSinks: [FrameSink]
    private let programRenderer: SceneRenderer
    private let incomingRenderer: SceneRenderer
    private let previewRenderer: SceneRenderer
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    /// The label of the queue the render loop runs on.
    public static let queueLabel = "render.loop"
    private let queue: DispatchQueue
    private let onMain: MainHop
    private var timer: DispatchSourceTimer?
    private let pixelBuffers: PixelBufferProviding
    private let makeDetailBuffers: (Int, Int) -> PixelBufferProviding
    /// Frames of the larger size, and how much larger, while one is chosen.
    private var detail: (buffers: PixelBufferProviding, scale: Int)?
    private let clock: () -> Date
    private let startTime: Date

    private let lock = NSLock()
    private var program = SceneConfiguration()
    private var preview: SceneConfiguration?
    private var transition: RunningTransition?
    private var onTransitionFinished: ((SceneConfiguration) -> Void)?
    private var lastProgramBuffer: CVPixelBuffer?
    /// A scene waiting to have its picture taken, once its sources have
    /// had a moment to start.
    private var thumbnailJob: (scene: SceneConfiguration, readyAt: TimeInterval, completion: (CVPixelBuffer?) -> Void)?
    private let thumbnailRenderer: SceneRenderer
    /// How long a scene's sources are given to start before its picture is taken.
    private let thumbnailWarmUp: TimeInterval

    public init(
        sources: SourceSupplying,
        makeRenderer: () -> SceneRenderer,
        transitionFactory: TransitionFactory,
        fallbackTransition: TransitionEffect,
        programSinks: [FrameSink],
        contractSinks: [FrameSink] = [],
        previewSinks: [FrameSink] = [],
        pixelBuffers: PixelBufferProviding,
        makeDetailBuffers: @escaping (Int, Int) -> PixelBufferProviding,
        clock: @escaping () -> Date,
        context: CIContext,
        queue: DispatchQueue,
        onMain: @escaping MainHop,
        thumbnailWarmUp: TimeInterval = Pacing.usual.thumbnailWarmUp
    ) {
        self.thumbnailWarmUp = thumbnailWarmUp
        self.context = context
        self.queue = queue
        self.onMain = onMain
        self.clock = clock
        startTime = clock()
        self.pixelBuffers = pixelBuffers
        self.makeDetailBuffers = makeDetailBuffers
        self.contractSinks = contractSinks
        self.sources = sources
        self.transitionFactory = transitionFactory
        self.fallbackTransition = fallbackTransition
        self.programSinks = programSinks
        self.previewSinks = previewSinks
        programRenderer = makeRenderer()
        incomingRenderer = makeRenderer()
        previewRenderer = makeRenderer()
        thumbnailRenderer = makeRenderer()
    }

    /// Takes a picture of a scene that need not be on air or in the
    /// preview: its sources are started, given a moment, drawn once and let
    /// go again. One at a time: false when another is under way. The
    /// picture comes back on the render queue, or nil when it could not be drawn.
    public func captureThumbnail(of scene: SceneConfiguration, completion: @escaping (CVPixelBuffer?) -> Void) -> Bool {
        lock.lock()
        guard thumbnailJob == nil else {
            lock.unlock()
            return false
        }
        thumbnailJob = (scene, now + thumbnailWarmUp, completion)
        lock.unlock()
        syncSources()
        return true
    }

    /// Chooses how much detail the program picture is drawn with. The
    /// preview, and the sinks that only take the camera's size, stay as they are.
    public func setDrawingSize(_ size: DrawingSize) {
        lock.lock()
        defer { lock.unlock() }
        guard size.scale != detail?.scale ?? CameraContract.unitScale else { return }
        detail = size.scale > CameraContract.unitScale
            ? (makeDetailBuffers(size.width, size.height), size.scale) : nil
    }

    /// Called on the main queue with the new program scene when a transition ends.
    public func onTransitionFinished(_ handler: @escaping (SceneConfiguration) -> Void) {
        lock.lock()
        onTransitionFinished = handler
        lock.unlock()
    }

    public func setProgram(_ scene: SceneConfiguration) {
        lock.lock()
        program = scene
        lock.unlock()
        syncSources()
    }

    public func setPreview(_ scene: SceneConfiguration?) {
        lock.lock()
        preview = scene
        lock.unlock()
        syncSources()
    }

    /// Blends the program into another scene over time. An unknown
    /// transition name is drawn as the fallback transition.
    public func startTransition(to scene: SceneConfiguration, named name: String, duration: TimeInterval) {
        let effect = transitionFactory.makeTransition(named: name, canvas: CameraContract.size) ?? fallbackTransition
        lock.lock()
        transition = RunningTransition(target: scene, effect: effect, startTime: now, duration: duration)
        lock.unlock()
        syncSources()
    }

    /// The most recent program frame, for snapshots.
    public var latestProgramFrame: CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return lastProgramBuffer
    }

    public func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1 / Double(CameraContract.framesPerSecond))
        timer.setEventHandler { [weak self] in self?.renderFrame() }
        timer.resume()
        self.timer = timer
    }

    private var now: TimeInterval { clock().timeIntervalSince(startTime) }

    /// A step in two scenes at once is one source, wanted once.
    private static func keepingFirst(_ first: SourceSpec, _ second: SourceSpec) -> SourceSpec { first }

    private func syncSources() {
        lock.lock()
        var wanted = program.sourcesInUse
        wanted.merge(preview?.sourcesInUse ?? [:], uniquingKeysWith: Self.keepingFirst)
        wanted.merge(transition?.target.sourcesInUse ?? [:], uniquingKeysWith: Self.keepingFirst)
        wanted.merge(thumbnailJob?.scene.sourcesInUse ?? [:], uniquingKeysWith: Self.keepingFirst)
        lock.unlock()
        sources.setSourcesInUse(wanted)
    }

    private func renderFrame() {
        lock.lock()
        let program = self.program
        let preview = self.preview
        let transition = self.transition
        let detail = self.detail
        let thumbnailJob = self.thumbnailJob
        lock.unlock()
        let time = now

        var image = programRenderer.render(program, time: time)
        if let transition {
            let progress = transition.progress(at: time)
            let incoming = incomingRenderer.render(transition.target, time: time)
            image = transition.effect.blend(from: image, to: incoming, progress: progress, time: time)
            if progress >= 1 {
                finish(transition)
            }
        }
        if let detail {
            // The larger picture goes to everything that can take it, and
            // one of the camera's own size to what cannot.
            if let buffer = draw(image, in: detail.buffers, scale: detail.scale) {
                keep(buffer)
                programSinks.forEach { $0.send(buffer) }
            }
            if !contractSinks.isEmpty, let buffer = draw(image) {
                contractSinks.forEach { $0.send(buffer) }
            }
        } else if let buffer = draw(image) {
            keep(buffer)
            (programSinks + contractSinks).forEach { $0.send(buffer) }
        }
        if let preview, !previewSinks.isEmpty, let buffer = draw(previewRenderer.render(preview, time: time)) {
            previewSinks.forEach { $0.send(buffer) }
        }
        if let thumbnailJob, time >= thumbnailJob.readyAt {
            let picture = draw(thumbnailRenderer.render(thumbnailJob.scene, time: time))
            lock.lock()
            self.thumbnailJob = nil
            lock.unlock()
            syncSources()
            thumbnailJob.completion(picture)
        }
    }

    private func finish(_ finished: RunningTransition) {
        lock.lock()
        program = finished.target
        transition = nil
        let handler = onTransitionFinished
        lock.unlock()
        syncSources()
        onMain { handler?(finished.target) }
    }

    private func keep(_ buffer: CVPixelBuffer) {
        lock.lock()
        lastProgramBuffer = buffer
        lock.unlock()
    }

    private func draw(_ image: CIImage) -> CVPixelBuffer? {
        draw(image, in: pixelBuffers, scale: CameraContract.unitScale)
    }

    /// Draws a picture laid out at the camera's size into a frame so many
    /// times larger each way.
    private func draw(_ image: CIImage, in buffers: PixelBufferProviding, scale: Int) -> CVPixelBuffer? {
        guard let pixelBuffer = buffers.makeBuffer() else { return nil }
        let factor = CGFloat(scale)
        context.render(
            image.transformed(by: CGAffineTransform(scaleX: factor, y: factor)),
            to: pixelBuffer,
            bounds: CGRect(
                x: 0, y: 0, width: CameraContract.size.width * factor, height: CameraContract.size.height * factor
            ),
            colorSpace: colorSpace
        )
        return pixelBuffer
    }
}
