import CamTwistCore
import Foundation
import Network

/// What a request is answered with.
enum StreamReply {
    /// A whole answer, after which the connection closes.
    case whole(HTTPResponse)
    /// The start of an answer that carries on: whatever is broadcast
    /// afterwards is sent down the same connection.
    case live(Data)
}

/// Listens for players on the local network.
protocol StreamServing: AnyObject {
    func start(port: Int, handler: @escaping (HTTPRequest) -> StreamReply, onFailure: @escaping (String) -> Void)
    func stop()
    /// Sends data to every connection that was answered with `.live`.
    func broadcast(_ data: Data)
}

/// A very small HTTP server: enough to hand a stream to browsers and
/// players. It reads a request, asks its handler, and sends the answer.
final class WebStreamServer: StreamServing {
    /// The label of the queue the web stream server runs on.
    static let queueLabel = "output.webstream.server"
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var live: [ObjectIdentifier: NWConnection] = [:]
    /// A request line and its headers fit well inside this.
    private let largestRequest: Int

    init(largestRequest: Int, queue: DispatchQueue) {
        self.queue = queue
        self.largestRequest = largestRequest
    }

    func start(port: Int, handler: @escaping (HTTPRequest) -> StreamReply, onFailure: @escaping (String) -> Void) {
        queue.async { [weak self] in
            guard let self, let port = NWEndpoint.Port(rawValue: UInt16(clamping: port)),
                  let listener = try? NWListener(using: .tcp, on: port)
            else {
                onFailure("The port could not be opened")
                return
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    onFailure(error.localizedDescription)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection, handler: handler)
            }
            self.listener = listener
            listener.start(queue: self.queue)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            self.live.values.forEach { $0.cancel() }
            self.live = [:]
        }
    }

    func broadcast(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            for (id, connection) in self.live {
                connection.send(content: data, completion: .contentProcessed { [weak self] error in
                    // A player that has gone away is forgotten.
                    if error != nil {
                        self?.queue.async { self?.live[id]?.cancel(); self?.live[id] = nil }
                    }
                })
            }
        }
    }

    private func accept(_ connection: NWConnection, handler: @escaping (HTTPRequest) -> StreamReply) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: self.largestRequest) { [weak self] data, _, _, _ in
            guard let self, let request = data.flatMap(HTTPRequest.init) else {
                connection.cancel()
                return
            }
            switch handler(request) {
            case .whole(let response):
                connection.send(content: response.data, completion: .contentProcessed { _ in connection.cancel() })
            case .live(let start):
                self.live[ObjectIdentifier(connection)] = connection
                connection.send(content: start, completion: .contentProcessed { _ in })
            }
        }
    }
}
