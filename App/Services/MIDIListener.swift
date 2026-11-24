import CamTwistCore
import CoreMIDI
import Foundation

/// Listens to every MIDI input and reports each note that is pressed.
final class MIDIListener {
    private static let clientName = CameraContract.deviceName as CFString
    private static let portName = "\(CameraContract.deviceName) Input" as CFString

    var onNote: ((Int) -> Void)?

    /// The queue whoever listens is told on: the notes arrive on the MIDI system's own thread.
    private let main: DispatchQueue

    init(main: DispatchQueue) {
        self.main = main
    }

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()

    func start() {
        MIDIClientCreateWithBlock(Self.clientName, &client) { [weak self] _ in
            // Devices came or went: connect to whatever is there now.
            self?.connectSources()
        }
        MIDIInputPortCreateWithBlock(client, Self.portName, &port) { [weak self] packetList, _ in
            self?.read(packetList)
        }
        connectSources()
    }

    private func connectSources() {
        for index in 0..<MIDIGetNumberOfSources() {
            MIDIPortConnectSource(port, MIDIGetSource(index), nil)
        }
    }

    private func read(_ packetList: UnsafePointer<MIDIPacketList>) {
        for packet in packetList.unsafeSequence() {
            let length = Int(packet.pointee.length)
            let bytes = withUnsafeBytes(of: packet.pointee.data) { Array($0.prefix(length)) }
            guard let note = MIDINoteMessage.notePressed(in: bytes) else { continue }
            main.async { self.onNote?(note) }
        }
    }
}
