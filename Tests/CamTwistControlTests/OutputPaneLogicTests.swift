import CamTwistCore
import XCTest
@testable import CamTwistControl
@testable import CamTwistRendering

final class StatusLineTests: XCTestCase {
    func testCameraStatesEachHaveTheirOwnLine() {
        XCTAssertEqual(StatusLine.camera(.installed, watchers: "Zoom", isSending: false),
                       StatusLine("Installed, in use by Zoom", .done))
        XCTAssertEqual(StatusLine.camera(.installed, watchers: "", isSending: true).text,
                       "Installed, and getting the picture")
        XCTAssertEqual(StatusLine.camera(.installed, watchers: "", isSending: false).text, "Installed")
        XCTAssertEqual(StatusLine.camera(.installing, watchers: "", isSending: false), StatusLine("Installing", .working))
        XCTAssertEqual(StatusLine.camera(.unknown, watchers: "", isSending: false),
                       StatusLine("Not installed yet", .notStarted))
        XCTAssertEqual(StatusLine.camera(.failed("No"), watchers: "", isSending: false), StatusLine("No", .failure))
        let approval = StatusLine.camera(.needsApproval, watchers: "", isSending: false)
        XCTAssertEqual(approval.icon, .warning)
        XCTAssertTrue(approval.text.contains(CameraContract.deviceName))
        XCTAssertTrue(approval.text.contains("\"Login Items & Extensions\""))
    }

    func testMicrophoneStatesEachHaveTheirOwnLine() {
        XCTAssertEqual(StatusLine.microphone(.installed), StatusLine("Installed", .done))
        XCTAssertEqual(StatusLine.microphone(.installing).icon, .working)
        XCTAssertEqual(StatusLine.microphone(.failed("Bad")), StatusLine("Bad", .failure))
        XCTAssertEqual(StatusLine.microphone(.notInstalled), StatusLine("Not installed yet", .notStarted))
    }

    func testRecordingLinesNameTheFileAndAlertWhileRecording() {
        XCTAssertEqual(StatusLine.recording(.off), StatusLine("Starting", .working))
        XCTAssertEqual(StatusLine.recording(.recording("a.mov")), StatusLine("Recording to a.mov", .recording, tint: .alert))
        XCTAssertEqual(StatusLine.recording(.failed("Full")), StatusLine("Full", .failure))
    }

    func testCastSaysNothingWhileIdle() {
        XCTAssertNil(StatusLine.cast(.idle))
        XCTAssertEqual(StatusLine.cast(.starting), StatusLine("Starting on the device", .working))
        XCTAssertEqual(StatusLine.cast(.loading), StatusLine("Starting on the device", .working))
        XCTAssertEqual(StatusLine.cast(.playing), StatusLine("Playing on the device", .playing))
        XCTAssertEqual(StatusLine.cast(.failed("Lost")), StatusLine("Lost", .failure))
    }

    func testRTMPSaysNothingWhileIdle() {
        XCTAssertNil(StatusLine.rtmp(.idle))
        XCTAssertEqual(StatusLine.rtmp(.connecting), StatusLine("Connecting", .working))
        XCTAssertEqual(StatusLine.rtmp(.live), StatusLine("Live", .live, tint: .alert))
        XCTAssertEqual(StatusLine.rtmp(.failed("Refused")), StatusLine("Could not stream: Refused", .failure))
    }

    func testWebStreamOnlySpeaksOfFailure() {
        XCTAssertNil(StatusLine.webStream(.off))
        XCTAssertNil(StatusLine.webStream(.running))
        XCTAssertEqual(StatusLine.webStream(.failed("Port in use")), StatusLine("Could not start: Port in use", .failure))
    }

    func testIconsAreSystemSymbolNames() {
        XCTAssertEqual(StatusIcon.done.rawValue, "checkmark.circle")
        XCTAssertEqual(StatusIcon.failure.rawValue, "xmark.octagon")
    }
}

final class InstallControlsTests: XCTestCase {
    func testCameraButtonsFollowTheState() {
        XCTAssertEqual(CameraInstallControls(.installed).installTitle, "Reinstall camera")
        XCTAssertTrue(CameraInstallControls(.installed).canRemove)
        XCTAssertFalse(CameraInstallControls(.unknown).canRemove)
        XCTAssertEqual(CameraInstallControls(.unknown).installTitle, "Install camera")
        XCTAssertTrue(CameraInstallControls(.installing).isBusy)
        XCTAssertFalse(CameraInstallControls(.installed).isBusy)
        XCTAssertEqual(CameraInstallControls(.needsApproval).installTitle, "Try again")
        XCTAssertEqual(CameraInstallControls(.failed("x")).installTitle, "Try again")
    }

    func testMicrophoneButtonsFollowTheState() {
        XCTAssertEqual(MicrophoneInstallControls(.installed).installTitle, "Reinstall microphone")
        XCTAssertTrue(MicrophoneInstallControls(.installed).canRemove)
        XCTAssertEqual(MicrophoneInstallControls(.notInstalled).installTitle, "Install microphone")
        XCTAssertFalse(MicrophoneInstallControls(.notInstalled).canRemove)
        XCTAssertTrue(MicrophoneInstallControls(.installing).isBusy)
        XCTAssertFalse(MicrophoneInstallControls(.failed("x")).isBusy)
        XCTAssertFalse(MicrophoneInstallControls(.installed).offersAddOn)
        XCTAssertTrue(MicrophoneInstallControls(.notInstalled).offersAddOn)
    }
}

final class OutputChoicesTests: XCTestCase {
    private let main = DisplayChoice(id: 1, name: "Main")
    private let side = DisplayChoice(id: 2, name: "Side")
    private let third = DisplayChoice(id: 3, name: "Third")

    func testTheWindowsOwnScreenIsLeftOut() {
        let choices = OutputChoices(displays: [main, side, third], windowDisplayID: 1, selected: nil)
        XCTAssertEqual(choices.otherDisplays, [side, third])
        XCTAssertTrue(choices.canSwitch)
        XCTAssertFalse(choices.needsSecondScreen)
        XCTAssertEqual(choices.screen(whenSwitched: true), 3)
        XCTAssertNil(choices.screen(whenSwitched: false))
    }

    func testWithoutAnotherScreenTheSwitchIsOffUnlessOneIsInUse() {
        let alone = OutputChoices(displays: [main], windowDisplayID: 1, selected: nil)
        XCTAssertFalse(alone.canSwitch)
        XCTAssertTrue(alone.needsSecondScreen)
        XCTAssertNil(alone.screen(whenSwitched: true))
        let inUse = OutputChoices(displays: [main], windowDisplayID: 1, selected: 2)
        XCTAssertTrue(inUse.canSwitch)
        XCTAssertFalse(inUse.needsSecondScreen)
    }

    func testNoKnownWindowScreenKeepsEveryDisplay() {
        XCTAssertEqual(OutputChoices(displays: [main], windowDisplayID: nil, selected: nil).otherDisplays, [main])
    }

    func testPickerTitles() {
        XCTAssertEqual(OutputChoices.castPlaceholder(deviceCount: 0), "Looking for devices")
        XCTAssertEqual(OutputChoices.castPlaceholder(deviceCount: 2), "Choose a device")
        XCTAssertEqual(OutputChoices.airPlayTitle(isOnDevice: true), "Playing on a screen")
        XCTAssertEqual(OutputChoices.airPlayTitle(isOnDevice: false), "Choose a screen")
    }
}

final class CameraInstallMachineTests: XCTestCase {
    func testRefreshFollowsThePresenceOfTheCamera() {
        var machine = CameraInstallMachine()
        machine.refresh(cameraIsPresent: false)
        XCTAssertEqual(machine.state, .unknown)
        machine.refresh(cameraIsPresent: true)
        XCTAssertEqual(machine.state, .installed)
        machine.refresh(cameraIsPresent: false)
        XCTAssertEqual(machine.state, .unknown)
    }

    func testRefreshLeavesAnInstallUnderWay() {
        var machine = CameraInstallMachine()
        machine.beginInstall()
        machine.refresh(cameraIsPresent: true)
        XCTAssertEqual(machine.state, .installing)
    }

    func testRefreshKeepsWaitingForApprovalUntilTheCameraAppears() {
        var machine = CameraInstallMachine()
        machine.needsApproval()
        machine.refresh(cameraIsPresent: false)
        XCTAssertEqual(machine.state, .needsApproval)
        machine.refresh(cameraIsPresent: true)
        XCTAssertEqual(machine.state, .installed)
    }

    func testAnInstallEndsInstalledOrAwaitingApproval() {
        var machine = CameraInstallMachine()
        machine.beginInstall()
        machine.finished(completed: true)
        XCTAssertEqual(machine.state, .installed)
        machine.beginInstall()
        machine.finished(completed: false)
        XCTAssertEqual(machine.state, .needsApproval)
    }

    func testARemovalEndsNotInstalledWhateverTheResult() {
        var machine = CameraInstallMachine()
        machine.beginRemove()
        machine.finished(completed: true)
        XCTAssertEqual(machine.state, .unknown)
        machine.beginInstall()
        machine.finished(completed: true)
        XCTAssertEqual(machine.state, .installed, "the removal flag does not outlive its request")
    }

    func testAFailureIsKeptAndEndsARemoval() {
        var machine = CameraInstallMachine()
        machine.beginRemove()
        machine.failed("Refused")
        XCTAssertEqual(machine.state, .failed("Refused"))
        machine.beginInstall()
        machine.finished(completed: true)
        XCTAssertEqual(machine.state, .installed)
    }
}
