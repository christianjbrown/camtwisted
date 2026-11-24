import XCTest
@testable import CamTwistCore

final class AdapterLogicTests: XCTestCase {
    func testSnapshotsAreNamedAfterTheMomentTheyWereTaken() {
        let zone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(SnapshotName.baseName(at: date, in: zone), "CamTwisted 1970-01-01 00.00.00")
        XCTAssertEqual(SnapshotName.fileExtension, "png")
        XCTAssertFalse(SnapshotName.baseName(at: date).isEmpty)
    }

    func testANoteOnPressesItsNote() {
        XCTAssertEqual(MIDINoteMessage.notePressed(in: [0x90, 60, 100]), 60)
        XCTAssertEqual(MIDINoteMessage.notePressed(in: [0x93, 61, 1]), 61, "any channel")
    }

    func testOtherPacketsPressNothing() {
        XCTAssertNil(MIDINoteMessage.notePressed(in: [0x90, 60]))
        XCTAssertNil(MIDINoteMessage.notePressed(in: [0x80, 60, 100]))
        XCTAssertNil(MIDINoteMessage.notePressed(in: [0x90, 60, 0]), "silent note-on is a note-off")
    }

    func testReadingStopsWhenTheDeviceRefusesOrTheConnectionGoes() {
        XCTAssertEqual(CastReadOutcome.after(sessionFailed: true, connectionEnded: true, readerBroken: true), .refused)
        XCTAssertEqual(CastReadOutcome.after(sessionFailed: false, connectionEnded: true, readerBroken: false), .lost)
        XCTAssertEqual(CastReadOutcome.after(sessionFailed: false, connectionEnded: false, readerBroken: true), .lost)
        XCTAssertEqual(CastReadOutcome.after(sessionFailed: false, connectionEnded: false, readerBroken: false), .keepReading)
    }

    func testCastDevicesAreListedByNameWhateverTheCase() {
        XCTAssertEqual(CastDeviceOrder.sorted(["tv", "Bedroom", "Attic"], name: { $0 }), ["Attic", "Bedroom", "tv"])
    }

    func testTheMicrophoneInstallerOnlyComplainsOfAFailedScript() {
        XCTAssertNil(MicrophoneInstallOutcome.problem(exitStatus: 0))
        XCTAssertEqual(MicrophoneInstallOutcome.problem(exitStatus: 1), MicrophoneInstallOutcome.cancelled)
    }

    func testADisplayNumberIsReadFromItsRecord() {
        XCTAssertEqual(DisplayIdentity.displayID(inDescription: [DisplayIdentity.screenNumberKey: NSNumber(value: 7)]), 7)
        XCTAssertNil(DisplayIdentity.displayID(inDescription: [:]))
        XCTAssertNil(DisplayIdentity.displayID(inDescription: [DisplayIdentity.screenNumberKey: "seven"]))
    }

    func testOnlyEscapeClosesTheFullScreenOutput() {
        XCTAssertTrue(FullScreenKeys.closes(keyCode: 53))
        XCTAssertFalse(FullScreenKeys.closes(keyCode: 0))
    }

    func testAirPlayPlaysOnlyWhileOnAndIsSilentUntilADeviceHasIt() {
        XCTAssertEqual(AirPlayPolicy.wantedAddress(isOn: true, address: "http://x"), "http://x")
        XCTAssertNil(AirPlayPolicy.wantedAddress(isOn: false, address: "http://x"))
        XCTAssertEqual(AirPlayPolicy.volume(isOnDevice: true), 1)
        XCTAssertEqual(AirPlayPolicy.volume(isOnDevice: false), 0)
    }

    func testEmptyPasswordsAreNotKept() {
        XCTAssertTrue(KeychainRules.keeps("secret"))
        XCTAssertFalse(KeychainRules.keeps(""))
    }

    func testAThumbnailIsScaledToTheTileWidth() {
        XCTAssertEqual(ThumbnailScale.factor(forWidth: 1920), ThumbnailScale.width / 1920)
    }
}
