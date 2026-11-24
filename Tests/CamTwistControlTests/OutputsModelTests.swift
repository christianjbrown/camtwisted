import CamTwistCore
import Observation
import XCTest
@testable import CamTwistRendering
@testable import CamTwistControl

/// Says the stream is wherever a test puts it.
@MainActor
private final class FakeStreamAddress: StreamAddressing {
    var webStreamLinks: [WebStreamLink] = []
}

/// Counts the changes something watched has made.
private final class ChangeCount: @unchecked Sendable {
    var count = 0
}

@MainActor
final class CameraOutputModelTests: XCTestCase {
    private let connection = FakeCameraConnection()
    private let processes = FakeProcesses()
    private let installer = FakeInstaller()

    private func makeModel() -> CameraOutputModel {
        CameraOutputModel(connection: connection, use: CameraUse(processes: processes), installer: installer)
    }

    func testTheInstallStateIsTheInstallersFromTheStartAndFollowsIt() {
        installer.state = .installing
        let model = makeModel()
        XCTAssertEqual(model.installState, .installing)
        installer.state = .installed
        XCTAssertEqual(model.installState, .installed)
        model.install()
        model.remove()
        XCTAssertEqual(installer.installCount, 1)
        XCTAssertEqual(installer.removeCount, 1)
    }

    func testARefreshSaysWhetherThePictureIsGoingOutAndWhoHasItOpen() {
        let model = makeModel()
        XCTAssertFalse(model.isSending)
        XCTAssertEqual(model.watchers, "")
        connection.isConnected = true
        connection.watcherProcessIDs = [7]
        processes.paths[7] = "/Applications/Zoom.app"
        model.refresh()
        XCTAssertTrue(model.isSending)
        XCTAssertEqual(model.watchers, "Zoom")
        XCTAssertEqual(installer.refreshCount, 1, "the installer looks again too")
    }

    func testAnIdleRefreshChangesNothingThatIsWatched() {
        let model = makeModel()
        model.refresh()
        let changes = ChangeCount()
        withObservationTracking {
            _ = (model.isSending, model.watchers)
        } onChange: {
            changes.count += 1
        }
        model.refresh()
        XCTAssertEqual(changes.count, 0)
    }

    func testAnInstallerThatOutlivesTheModelTellsNobody() {
        var model: CameraOutputModel? = makeModel()
        XCTAssertNotNil(model)
        model = nil
        installer.state = .installed
        XCTAssertNil(model)
    }
}

@MainActor
final class MicrophoneOutputModelTests: XCTestCase {
    private let installer = FakeMicrophoneInstaller()
    private let output = FakeMicrophone()

    private func makeModel() -> MicrophoneOutputModel {
        MicrophoneOutputModel(setup: MicrophoneSetup(installer: installer, output: output), queue: ImmediateQueue())
    }

    func testInstallingAndRemovingShowHowTheyWentAndSayWhenTheyAreDone() {
        let model = makeModel()
        var changes = 0
        model.onChanged = { changes += 1 }
        XCTAssertEqual(model.state, .notInstalled)
        model.install()
        XCTAssertEqual(model.state, .installing)
        installer.isInstalled = true
        installer.installs[0](nil)
        XCTAssertEqual(changes, 1)
        model.refresh()
        XCTAssertEqual(model.state, .installed)
        model.remove()
        installer.removals[0]("could not")
        XCTAssertEqual(changes, 2)
        model.refresh()
        XCTAssertEqual(model.state, .failed("could not"))
    }

    func testAnAnswerAfterTheModelHasGoneDoesNothing() {
        var model: MicrophoneOutputModel? = makeModel()
        model?.install()
        model = nil
        installer.installs[0](nil)
        XCTAssertNil(model)
    }
}

@MainActor
final class StreamsModelTests: XCTestCase {
    private let webStream = FakeWebStream()
    private let webMovie = FakeWebStream()
    private let rtmp = FakeRTMP()
    private let addresses = FakeAddresses()

    private func makeModel(_ preferences: AppPreferences = AppPreferences()) -> StreamsModel {
        StreamsModel(
            preferences: preferences, webStream: webStream, webMovie: webMovie, rtmp: rtmp,
            links: WebStreamLinkLister(), addresses: addresses
        )
    }

    func testARefreshSaysHowEachStreamIsGettingOn() {
        let model = makeModel()
        XCTAssertEqual(model.webStreamStatus, .off)
        XCTAssertEqual(model.webMovieStatus, .off)
        XCTAssertEqual(model.rtmpStatus, .idle)
        webStream.status = .failed("Port in use")
        webMovie.status = .running
        rtmp.status = .live
        model.refresh()
        XCTAssertEqual(model.webStreamStatus, .failed("Port in use"))
        XCTAssertEqual(model.webMovieStatus, .running)
        XCTAssertEqual(model.rtmpStatus, .live)
    }

    func testTheLinksFollowThisMacsAddressAndThePortsInTheSettings() {
        let model = makeModel()
        XCTAssertEqual(model.webStreamLinks.map(\.id), ["HLS", "Page that plays it"])
        XCTAssertEqual(model.webMovieLinks.map(\.id), ["MP4"])
        addresses.hosts = ["192.0.2.7"]
        var preferences = AppPreferences()
        preferences.webStream.port = 9000
        preferences.webMovie.port = 9100
        model.follow(preferences)
        XCTAssertEqual(model.webStreamLinks.first?.address, "http://192.0.2.7:9000/stream.m3u8")
        XCTAssertEqual(model.webMovieLinks.first?.address, "http://192.0.2.7:9100/stream.mp4")
    }

    func testASceneComingOnAirIsMarkedInEveryStream() {
        makeModel().markScene(named: "Wide")
        XCTAssertEqual(webStream.marked, ["Wide"])
        XCTAssertEqual(webMovie.marked, ["Wide"])
        XCTAssertEqual(rtmp.marked, ["Wide"])
    }
}

@MainActor
final class DevicesModelTests: XCTestCase {
    private static let address = "http://192.0.2.7:8090/stream.m3u8"

    private let airPlay = FakeAirPlay()
    private let cast = FakeCast()
    private let stream = FakeStreamAddress()

    func testAirPlayAndCastAreToldWhetherToPlayAndWhereTheStreamIs() {
        let model = DevicesModel(preferences: AppPreferences(), airPlay: airPlay, cast: cast, stream: stream)
        model.refresh()
        XCTAssertEqual(airPlay.applied.last?.isOn, false)
        XCTAssertNil(airPlay.applied.last?.address, "no stream to play yet")
        XCTAssertEqual(cast.applied.last?.isOn, false)

        stream.webStreamLinks = [WebStreamLink(title: "HLS", address: Self.address)]
        var preferences = AppPreferences()
        preferences.sendsToAirPlay = true
        preferences.sendsToCast = true
        preferences.castDeviceName = "Den"
        model.follow(preferences)
        XCTAssertEqual(airPlay.applied.last?.isOn, true)
        XCTAssertEqual(airPlay.applied.last?.address, Self.address)
        XCTAssertEqual(cast.applied.last?.isOn, true)
        XCTAssertEqual(cast.applied.last?.address, Self.address)
        XCTAssertEqual(cast.applied.last?.deviceName, "Den")
    }
}

@MainActor
final class OutputsModelTests: XCTestCase {
    func testWhatAllTheOutputsAreToldIsPassedOnToEachPart() {
        let connection = FakeCameraConnection()
        let microphoneInstaller = FakeMicrophoneInstaller()
        let webStream = FakeWebStream()
        let airPlay = FakeAirPlay()
        let streams = StreamsModel(
            preferences: AppPreferences(), webStream: webStream, webMovie: FakeWebStream(), rtmp: FakeRTMP(),
            links: WebStreamLinkLister(), addresses: FakeAddresses()
        )
        let model = OutputsModel(
            camera: CameraOutputModel(
                connection: connection, use: CameraUse(processes: FakeProcesses()), installer: FakeInstaller()
            ),
            microphone: MicrophoneOutputModel(
                setup: MicrophoneSetup(installer: microphoneInstaller, output: FakeMicrophone()), queue: ImmediateQueue()
            ),
            streams: streams,
            devices: DevicesModel(preferences: AppPreferences(), airPlay: airPlay, cast: FakeCast(), stream: streams)
        )

        connection.isConnected = true
        microphoneInstaller.isInstalled = true
        webStream.status = .running
        model.refresh()
        XCTAssertTrue(model.camera.isSending)
        XCTAssertEqual(model.microphone.state, .installed)
        XCTAssertEqual(model.streams.webStreamStatus, .running)
        XCTAssertEqual(airPlay.applied.count, 1)

        var preferences = AppPreferences()
        preferences.webStream.port = 9000
        preferences.sendsToAirPlay = true
        model.follow(preferences)
        XCTAssertEqual(
            airPlay.applied.last?.address, "http://localhost:9000/stream.m3u8",
            "the players hear of the new port, which the streams took first"
        )

        model.markScene(named: "Wide")
        XCTAssertEqual(webStream.marked, ["Wide"])
    }
}
