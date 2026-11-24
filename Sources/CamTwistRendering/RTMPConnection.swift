import CamTwistCore
import Foundation
import Network

/// The line to an RTMP server.
protocol StreamConnecting: AnyObject {
    /// Opens the line. `onReady` is called once it is up, `onReceive` with
    /// whatever arrives, and `onFailure` when it fails or drops.
    func open(
        to target: RTMPTarget,
        onReady: @escaping () -> Void,
        onReceive: @escaping (Data) -> Void,
        onFailure: @escaping (String) -> Void
    )
    func send(_ data: Data)
    func close()
}

/// A TCP connection, encrypted when the address asks for it.
final class RTMPConnection: StreamConnecting {
    private static let closedMessage = "The server closed the connection"

    /// The label of the queue the stream connection runs on.
    static let queueLabel = "output.rtmp.connection"
    private let queue: DispatchQueue
    private var connection: NWConnection?
    /// The most taken from the network in one go.
    private let largestRead: Int

    init(largestRead: Int, queue: DispatchQueue) {
        self.queue = queue
        self.largestRead = largestRead
    }

    func open(
        to target: RTMPTarget,
        onReady: @escaping () -> Void,
        onReceive: @escaping (Data) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        let port = NWEndpoint.Port(rawValue: UInt16(clamping: target.port)) ?? .init(integerLiteral: UInt16(RTMPTarget.defaultPort))
        let connection = NWConnection(
            host: NWEndpoint.Host(target.host), port: port, using: target.isSecure ? .tls : .tcp
        )
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                onReady()
                self?.receive(onReceive: onReceive, onFailure: onFailure)
            case .failed(let error), .waiting(let error):
                onFailure(error.localizedDescription)
            default:
                break
            }
        }
        self.connection = connection
        connection.start(queue: queue)
    }

    func send(_ data: Data) {
        guard !data.isEmpty else { return }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    func close() {
        connection?.cancel()
        connection = nil
    }

    private func receive(onReceive: @escaping (Data) -> Void, onFailure: @escaping (String) -> Void) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: self.largestRead) { [weak self] data, _, isDone, error in
            if let data, !data.isEmpty {
                onReceive(data)
            }
            if isDone || error != nil {
                onFailure(error?.localizedDescription ?? Self.closedMessage)
                return
            }
            self?.receive(onReceive: onReceive, onFailure: onFailure)
        }
    }
}
