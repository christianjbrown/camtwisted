import AppKit
import CamTwistCore
import CoreImage
import WebKit

/// Loads a web page off screen and photographs it a few times a second.
final class WebPageCamera {
    private let url: URL
    private let canvas: CGSize
    private let isTransparent: Bool
    /// Pages change slowly compared with video, and snapshots are costly.
    private let snapshotsPerSecond: TimeInterval
    private let frames = LatestFrameBox()
    private var webView: WKWebView?
    private var window: NSWindow?
    private var timer: Cancelling?
    private let timers: RepeatingTimers
    private let onMain: MainHop
    private let makeHost: WebPageHostMaker

    /// - Parameter isTransparent: leave the page's own background clear, so
    ///   the page can sit on top of a picture.
    init(
        url: URL, canvas: CGSize, isTransparent: Bool, snapshotsPerSecond: TimeInterval, timers: RepeatingTimers,
        onMain: @escaping MainHop, makeHost: @escaping WebPageHostMaker
    ) {
        self.onMain = onMain
        self.makeHost = makeHost
        self.timers = timers
        self.snapshotsPerSecond = snapshotsPerSecond
        self.url = url
        self.canvas = canvas
        self.isTransparent = isTransparent
    }

    var latestFrame: CIImage? { frames.load() }

    func start() {
        onMain { [self] in
            guard self.webView == nil else { return }
            let host = self.makeHost(CGRect(origin: .zero, size: self.canvas), self.isTransparent)
            let webView = host.webView
            if self.url.isFileURL {
                webView.loadFileURL(self.url, allowingReadAccessTo: self.url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: self.url))
            }
            self.webView = webView
            self.window = host.window
            self.timer = self.timers.every(1 / self.snapshotsPerSecond) { [weak self] in self?.takeSnapshot() }
        }
    }

    func stop() {
        onMain {
            self.timer?.cancel()
            self.timer = nil
            self.webView?.stopLoading()
            self.webView = nil
            self.window = nil
            self.frames.store(nil)
        }
    }

    private func takeSnapshot() {
        webView?.takeSnapshot(with: nil) { [weak self] image, _ in
            if let frame = Self.frame(from: image) {
                self?.frames.store(frame)
            }
        }
    }

    /// The snapshot as a picture, or nil when the web view gave none.
    static func frame(from snapshot: NSImage?) -> CIImage? {
        snapshot?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { CIImage(cgImage: $0) }
    }
}

/// A web page as a source.
public final class WebsiteSource: FrameSource {
    private let address: String
    private let camera: WebPageCamera?

    public init(
        address: String, snapshotsPerSecond: TimeInterval, timers: RepeatingTimers, onMain: @escaping MainHop,
        makeHost: @escaping WebPageHostMaker, canvas: CGSize = CameraContract.size
    ) {
        self.address = address
        camera = Self.url(from: address).map {
            WebPageCamera(
                url: $0, canvas: canvas, isTransparent: false, snapshotsPerSecond: snapshotsPerSecond, timers: timers,
                onMain: onMain, makeHost: makeHost
            )
        }
    }

    public var latestFrame: CIImage? { camera?.latestFrame }

    public func start() { camera?.start() }
    public func stop() { camera?.stop() }

    public func update(to spec: SourceSpec) -> Bool {
        spec == .website(url: address)
    }

    /// Accepts a full address, a bare host, or a path to a local HTML file.
    static func url(from address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix(pathPrefix) { return URL(fileURLWithPath: trimmed) }
        if trimmed.contains(schemeSeparator) { return URL(string: trimmed) }
        return URL(string: defaultScheme + trimmed)
    }

    private static let pathPrefix = "/"
    private static let schemeSeparator = "://"
    private static let defaultScheme = "https://"
}

public struct WebsiteSourceProvider: SourceProvider {
    private let snapshotsPerSecond: TimeInterval
    private let timers: RepeatingTimers
    private let onMain: MainHop
    private let makeHost: WebPageHostMaker

    public init(
        snapshotsPerSecond: TimeInterval, timers: RepeatingTimers, onMain: @escaping MainHop,
        makeHost: @escaping WebPageHostMaker
    ) {
        self.snapshotsPerSecond = snapshotsPerSecond
        self.timers = timers
        self.onMain = onMain
        self.makeHost = makeHost
    }

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .website(let address) = spec else { return nil }
        return WebsiteSource(
            address: address, snapshotsPerSecond: snapshotsPerSecond, timers: timers, onMain: onMain, makeHost: makeHost
        )
    }
}
