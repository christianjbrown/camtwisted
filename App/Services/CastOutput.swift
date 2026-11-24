import CamTwistControl
import CamTwistCore
import Foundation
import Observation
import Network

/// A Cast device found on the network.
struct CastDevice: Identifiable, Equatable {
    /// The name the device gives itself, such as "Living room TV".
    let name: String
    let endpoint: NWEndpoint

    var id: String { name }
}

/// Finds the Cast devices on the network.
protocol CastDeviceBrowsing: AnyObject {
    /// Told the devices there are, each time that changes.
    var onChange: (([CastDevice]) -> Void)? { get set }
    func start(on queue: DispatchQueue)
    func stop()
}

/// Makes the line to a Cast device.
protocol CastConnectionMaking {
    func connection(to device: CastDevice, on queue: DispatchQueue) -> NWConnection
}

/// What the views watch of the Cast output.
protocol CastWatching: AnyObject {
    var devices: [CastDevice] { get }
    var state: CastState { get }
}

/// Finds Cast devices by what they announce over Bonjour.
final class BonjourCastBrowser: CastDeviceBrowsing {
    private enum Service {
        static let type = "_googlecast._tcp"
        /// Where a device's own name is, in what it announces about itself.
        static let friendlyNameKey = "fn"
    }

    var onChange: (([CastDevice]) -> Void)?
    private var browser: NWBrowser?

    func start(on queue: DispatchQueue) {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Service.type, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let devices = results.compactMap { result -> CastDevice? in
                guard case .bonjour(let record) = result.metadata, let name = record[Service.friendlyNameKey] else {
                    return nil
                }
                return CastDevice(name: name, endpoint: result.endpoint)
            }
            self?.onChange?(CastDeviceOrder.sorted(devices, name: \.name))
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

/// Makes private lines to Cast devices.
struct TLSCastConnections: CastConnectionMaking {
    func connection(to device: CastDevice, on queue: DispatchQueue) -> NWConnection {
        // Cast devices sign their own certificates, so there is nobody to
        // check them against. The connection is still private.
        let security = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(security.securityProtocolOptions, { _, _, accept in accept(true) }, queue)
        return NWConnection(to: device.endpoint, using: NWParameters(tls: security))
    }
}

/// Plays the HLS stream this Mac serves on a Cast device, such as a
/// Chromecast: connects to the device chosen and has it fetch the stream
/// itself. Finding the devices is the browser's business and what is said
/// to one is `CastSession`'s; this carries it.
@Observable
final class CastOutput: CastSwitching, CastWatching {
    static let queueLabel = "output.cast"
    private static let connectionLost = "The connection to the device was lost."

    private(set) var devices: [CastDevice] = []
    private(set) var state = CastState.idle

    private let browser: CastDeviceBrowsing
    private let connections: CastConnectionMaking
    /// The queue everything here but the two properties above is kept to.
    private let queue: DispatchQueue
    private let main: WorkQueueing
    private let clock: () -> Date
    private var found: [CastDevice] = []
    private var connection: NWConnection?
    private var session: CastSession?
    private var reader = CastFrameReader()
    private var pings: DispatchSourceTimer?
    /// What should be playing where, when anything should.
    private var wanted: CastTarget?
    private var failedAt: Date?
    /// How long to leave a failure before trying again.
    private let retryDelay: TimeInterval
    /// Seconds between pings. A device drops a sender it has not heard from.
    private let pingInterval: TimeInterval
    /// The most bytes taken from the connection in one go.
    private let largestRead: Int

    init(
        browser: CastDeviceBrowsing, connections: CastConnectionMaking, queue: DispatchQueue, main: WorkQueueing,
        clock: @escaping () -> Date, retryDelay: TimeInterval, pingInterval: TimeInterval, largestRead: Int
    ) {
        self.browser = browser
        self.connections = connections
        self.queue = queue
        self.main = main
        self.clock = clock
        self.retryDelay = retryDelay
        self.pingInterval = pingInterval
        self.largestRead = largestRead
        browser.onChange = { [weak self] devices in
            self?.found = devices
            main.main { self?.devices = devices }
            self?.connectIfNeeded()
        }
    }

    func apply(isOn: Bool, address: String?, deviceName: String?) {
        queue.async { [weak self] in
            guard let self else { return }
            if isOn {
                self.browser.start(on: self.queue)
            } else {
                self.browser.stop()
            }
            let target = CastTarget.wanted(isOn: isOn, address: address, deviceName: deviceName)
            if target != self.wanted {
                self.wanted = target
                self.failedAt = nil
                self.disconnect(sayingGoodbye: true)
                self.publish(.idle)
            }
            self.connectIfNeeded()
        }
    }

    // MARK: The connection

    /// Connects when something should be playing and nothing is, leaving a
    /// failure a little while before trying again.
    private func connectIfNeeded() {
        guard connection == nil, let wanted, let device = found.first(where: { $0.name == wanted.device }) else { return }
        guard CastRetry.mayTry(failedAt: failedAt, now: clock(), delay: retryDelay) else { return }
        let connection = connections.connection(to: device, on: queue)
        self.connection = connection
        session = CastSession(streamAddress: wanted.address)
        reader = CastFrameReader()
        connection.stateUpdateHandler = { [weak self, weak connection] update in
            guard let self, let connection, self.connection === connection else { return }
            switch update {
            case .ready:
                self.send(self.session?.connected() ?? [])
                self.publishSessionState()
                self.startPings()
                self.read(from: connection)
            case .failed, .cancelled:
                self.lost()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func read(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: self.largestRead) { [weak self] data, _, isDone, error in
            guard let self, self.connection === connection else { return }
            for message in self.reader.append(data ?? Data()) {
                self.send(self.session?.received(message) ?? [])
            }
            self.publishSessionState()
            var sessionFailed = false
            if case .failed = self.session?.state { sessionFailed = true }
            switch CastReadOutcome.after(
                sessionFailed: sessionFailed, connectionEnded: isDone || error != nil, readerBroken: self.reader.isBroken
            ) {
            case .refused:
                // The device has said no: there is nothing more to say to it.
                self.failedAt = clock()
                self.disconnect(sayingGoodbye: false)
            case .lost:
                self.lost()
            case .keepReading:
                self.read(from: connection)
            }
        }
    }

    private func send(_ messages: [CastMessage]) {
        for message in messages {
            connection?.send(content: message.framed(), completion: .contentProcessed { _ in })
        }
    }

    private func startPings() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        timer.setEventHandler { [weak self] in
            guard let self, let session = self.session else { return }
            self.send([session.ping()])
        }
        timer.resume()
        pings = timer
    }

    private func lost() {
        session?.lost(Self.connectionLost)
        publishSessionState()
        failedAt = clock()
        disconnect(sayingGoodbye: false)
    }

    private func disconnect(sayingGoodbye: Bool) {
        pings?.cancel()
        pings = nil
        if sayingGoodbye, connection != nil {
            send(session?.stop() ?? [])
        }
        let closing = connection
        connection = nil
        session = nil
        closing?.cancel()
    }

    private func publishSessionState() {
        if let state = session?.state {
            publish(state)
        }
    }

    private func publish(_ state: CastState) {
        main.main { [weak self] in
            if self?.state != state {
                self?.state = state
            }
        }
    }
}
