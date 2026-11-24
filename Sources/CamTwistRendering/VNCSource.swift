import CamTwistCore
import CoreImage
import Foundation
import Network

/// Keeps passwords somewhere safe, by what they are for.
public protocol PasswordKeeping {
    func password(for account: String) -> String?
    func setPassword(_ password: String, for account: String)
}

/// Another computer's screen, watched over VNC. What is said to the
/// server is `RFBSession`'s business; this carries it and makes pictures
/// of the screen it builds up.
public final class VNCSource: FrameSource {
    private static let connectionLost = "The connection was lost."

    private let settings: VNCSettings
    private let passwords: PasswordKeeping
    /// How long to leave it before trying again after the connection goes.
    private let retryDelay: TimeInterval
    /// The most bytes taken from the connection in one go.
    private let largestRead: Int
    /// The label of the queue the remote screen connection runs on.
    static let queueLabel = "source.vnc"
    private let queue: DispatchQueue
    private let frames = LatestFrameBox()
    private var connection: NWConnection?
    private var session = RFBSession(password: "")
    private var drawnUpdate = 0
    private var isWanted = false

    public init(
        settings: VNCSettings, passwords: PasswordKeeping, retryDelay: TimeInterval, largestRead: Int,
        queue: DispatchQueue
    ) {
        self.queue = queue
        self.settings = settings
        self.passwords = passwords
        self.retryDelay = retryDelay
        self.largestRead = largestRead
    }

    public var latestFrame: CIImage? { frames.load() }

    public func start() {
        queue.async {
            self.isWanted = true
            self.connect()
        }
    }

    public func stop() {
        queue.async {
            self.isWanted = false
            self.connection?.cancel()
            self.connection = nil
            self.frames.store(nil)
        }
    }

    public func update(to spec: SourceSpec) -> Bool {
        spec == .vnc(settings)
    }

    private func connect() {
        guard isWanted, connection == nil, !settings.host.isEmpty,
              let port = NWEndpoint.Port(rawValue: UInt16(clamping: settings.port))
        else { return }
        session = RFBSession(password: passwords.password(for: settings.account) ?? "")
        drawnUpdate = 0
        let connection = NWConnection(host: NWEndpoint.Host(settings.host), port: port, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.connection === connection else { return }
            switch state {
            case .ready: self.read(from: connection)
            case .failed, .cancelled: self.lost(Self.connectionLost)
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func read(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: self.largestRead) { [weak self] data, _, isDone, error in
            guard let self, self.connection === connection else { return }
            for reply in self.session.receive(data ?? Data()) {
                connection.send(content: reply, completion: .contentProcessed { _ in })
            }
            self.drawIfChanged()
            if case .failed(let reason) = self.session.state {
                self.lost(reason)
            } else if isDone || error != nil {
                self.lost(Self.connectionLost)
            } else {
                self.read(from: connection)
            }
        }
    }

    /// Makes a picture of the screen when an update has changed it.
    private func drawIfChanged() {
        guard session.updateCount != drawnUpdate else { return }
        drawnUpdate = session.updateCount
        let screen = session.framebuffer
        guard screen.width > 0, screen.height > 0 else { return }
        frames.store(CIImage(
            bitmapData: Data(screen.pixels), bytesPerRow: screen.width * RFBFramebuffer.bytesPerPixel,
            size: CGSize(width: screen.width, height: screen.height), format: .BGRA8,
            colorSpace: SRGBColorSpace.shared
        ))
    }

    /// The connection has gone: the last picture stays up, and it is tried again shortly.
    private func lost(_ reason: String) {
        connection?.cancel()
        connection = nil
        queue.asyncAfter(deadline: .now() + self.retryDelay) { [weak self] in self?.connect() }
    }
}

public struct VNCSourceProvider: SourceProvider {
    private let passwords: PasswordKeeping
    private let retryDelay: TimeInterval
    private let largestRead: Int
    private let queues: QueueMaking

    public init(passwords: PasswordKeeping, retryDelay: TimeInterval, largestRead: Int, queues: QueueMaking) {
        self.passwords = passwords
        self.queues = queues
        self.retryDelay = retryDelay
        self.largestRead = largestRead
    }

    public func makeSource(for spec: SourceSpec) -> FrameSource? {
        guard case .vnc(let settings) = spec else { return nil }
        return VNCSource(
            settings: settings, passwords: passwords, retryDelay: retryDelay, largestRead: largestRead,
            queue: queues.makeQueue(label: VNCSource.queueLabel, qos: .default)
        )
    }
}
