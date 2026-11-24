import CamTwistCore
import CoreImage
import Network
import XCTest
@testable import CamTwistRendering

private struct NoPasswords: PasswordKeeping {
    func password(for account: String) -> String? { nil }
    func setPassword(_ password: String, for account: String) {}
}

/// A VNC server small enough to read: no password, a two by two screen,
/// and one update that paints it red.
private final class TinyVNCServer {
    let listener: NWListener
    private let queue = DispatchQueue(label: "test.vnc.server")
    private var received = Data()
    private var stage = 0

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start(ready: @escaping (UInt16) -> Void) {
        listener.stateUpdateHandler = { [listener] state in
            if case .ready = state, let port = listener.port { ready(port.rawValue) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            connection.send(content: Data("RFB 003.008\n".utf8), completion: .contentProcessed { _ in })
            self.read(connection)
        }
        listener.start(queue: queue)
    }

    private func read(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else { return }
            self.received.append(data)
            self.answer(connection)
            self.read(connection)
        }
    }

    /// Each stage waits for what the viewer says next, then says its own piece.
    private func answer(_ connection: NWConnection) {
        func send(_ bytes: [UInt8]) { connection.send(content: Data(bytes), completion: .contentProcessed { _ in }) }
        if stage == 0, received.count >= 12 {
            received.removeFirst(12)
            stage = 1
            send([1, 1])
        }
        if stage == 1, received.count >= 1 {
            received.removeFirst(1)
            stage = 2
            send([0, 0, 0, 0])
        }
        if stage == 2, received.count >= 1 {
            received.removeFirst(1)
            stage = 3
            // Two by two, a pixel format the viewer will replace, and the name "T".
            send([0, 2, 0, 2] + [UInt8](repeating: 0, count: 16) + [0, 0, 0, 1, 0x54])
        }
        // The pixel format (20 bytes), the encodings (16) and the first request (10).
        if stage == 3, received.count >= 46 {
            stage = 4
            let red: [UInt8] = [0, 0, 255, 0]
            send([0, 0, 0, 1, 0, 0, 0, 0, 0, 2, 0, 2, 0, 0, 0, 0] + red + red + red + red)
        }
    }
}

final class VNCSourceTests: XCTestCase {
    func testAScreenServedOverVNCBecomesAPicture() throws {
        let server = try TinyVNCServer()
        let listening = expectation(description: "the server is up")
        var port: UInt16 = 0
        server.start { port = $0; listening.fulfill() }
        wait(for: [listening], timeout: 5)

        let source = VNCSource(settings: VNCSettings(address: "127.0.0.1:\(port)"), passwords: NoPasswords(),
            retryDelay: Pacing.usual.remoteScreenRetryDelay, largestRead: Pacing.usual.remoteScreenLargestRead,
            queue: DispatchQueue(label: VNCSource.queueLabel)
        )
        XCTAssertTrue(source.update(to: .vnc(VNCSettings(address: "127.0.0.1:\(port)"))))
        XCTAssertFalse(source.update(to: .vnc(VNCSettings(address: "elsewhere"))))
        source.start()
        let deadline = Date().addingTimeInterval(10)
        while source.latestFrame == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let frame = try XCTUnwrap(source.latestFrame)
        XCTAssertEqual(frame.extent.size, CGSize(width: 2, height: 2))
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            frame, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        XCTAssertGreaterThan(pixel[0], 240, "the screen is red")
        XCTAssertLessThan(pixel[1], 20)
        source.stop()
        server.listener.cancel()

        XCTAssertNil(VNCSourceProvider(
            passwords: NoPasswords(), retryDelay: Pacing.usual.remoteScreenRetryDelay,
            largestRead: Pacing.usual.remoteScreenLargestRead, queues: DispatchQueues()
        ).makeSource(for: .colorBars))
        XCTAssertNotNil(VNCSourceProvider(
            passwords: NoPasswords(), retryDelay: Pacing.usual.remoteScreenRetryDelay,
            largestRead: Pacing.usual.remoteScreenLargestRead, queues: DispatchQueues()
        ).makeSource(for: .vnc(VNCSettings())))
    }
}
