import CamTwistAudioDriver
import CamTwistCore
import CoreAudio
import CoreAudio.AudioServerPlugIn
import XCTest

/// Drives the audio driver the way the system's audio server does: through
/// the table of functions its factory hands back.
final class AudioDriverTests: XCTestCase {
    private enum Object {
        static let plugIn = AudioObjectID(kAudioObjectPlugInObject)
        static let microphone: AudioObjectID = 2
        static let microphoneStream: AudioObjectID = 3
        static let feed: AudioObjectID = 4
        static let feedStream: AudioObjectID = 5
        static let nothing: AudioObjectID = 99
    }

    private var driver: AudioServerPlugInDriverRef!
    /// The audio server's side, which the driver keeps and never calls.
    private let host = UnsafeMutablePointer<AudioServerPlugInHostInterface>.allocate(capacity: 1)
    private var client = AudioServerPlugInClientInfo()
    private var table: AudioServerPlugInDriverInterface { driver.pointee!.pointee }

    override func setUp() {
        let made = CamTwistAudioDriver_Create(nil, CFUUIDCreateFromString(nil, "443ABAB8-E7B3-491A-B985-BEB9187030DB" as CFString))
        driver = made?.assumingMemoryBound(to: UnsafeMutablePointer<AudioServerPlugInDriverInterface>?.self)
        XCTAssertEqual(table.Initialize(driver, host), 0)
    }

    override func tearDown() {
        host.deallocate()
    }

    private func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func value<Value>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ start: Value,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> Value? {
        var address = address(selector, scope: scope)
        var result = start
        var used: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &result) {
            table.GetPropertyData(driver, object, 0, &address, 0, nil, UInt32(MemoryLayout<Value>.size), &used, $0)
        }
        return status == 0 ? result : nil
    }

    private func text(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        value(object, selector, nil as Unmanaged<CFString>?)?.map { $0.takeUnretainedValue() as String }
    }

    private func list(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, room: Int = 8
    ) -> [AudioObjectID] {
        var address = address(selector, scope: scope)
        var items = [AudioObjectID](repeating: 0, count: room)
        var used: UInt32 = 0
        let size = UInt32(room * MemoryLayout<AudioObjectID>.size)
        XCTAssertEqual(table.GetPropertyData(driver, object, 0, &address, 0, nil, size, &used, &items), 0)
        return Array(items.prefix(Int(used) / MemoryLayout<AudioObjectID>.size))
    }

    func testTheFactoryOnlyAnswersForAudioServerPlugIns() {
        XCTAssertNil(CamTwistAudioDriver_Create(nil, CFUUIDCreate(nil)))
        var interface: UnsafeMutableRawPointer?
        let wanted = CFUUIDGetUUIDBytes(CFUUIDCreateFromString(nil, "EEA5773D-CC43-49F1-8E00-8F96E7D23B17" as CFString))
        XCTAssertEqual(table.QueryInterface(driver, wanted, &interface), 0)
        XCTAssertEqual(interface, UnsafeMutableRawPointer(driver))
        XCTAssertNotEqual(table.QueryInterface(driver, CFUUIDGetUUIDBytes(CFUUIDCreate(nil)), &interface), 0)
        let held = table.AddRef(driver)
        XCTAssertEqual(table.Release(driver), held - 1)
    }

    func testTheNamesMatchTheContractTheAppFindsThemBy() {
        XCTAssertEqual(text(Object.microphone, kAudioObjectPropertyName), MicrophoneContract.deviceName)
        XCTAssertEqual(text(Object.microphone, kAudioDevicePropertyDeviceUID), MicrophoneContract.deviceUID)
        XCTAssertEqual(text(Object.feed, kAudioObjectPropertyName), MicrophoneContract.feedName)
        XCTAssertEqual(text(Object.feed, kAudioDevicePropertyDeviceUID), MicrophoneContract.feedUID)
        XCTAssertEqual(text(Object.plugIn, kAudioObjectPropertyManufacturer), MicrophoneContract.manufacturer)
        XCTAssertEqual(
            value(Object.microphone, kAudioDevicePropertyNominalSampleRate, 0.0), MicrophoneContract.sampleRate
        )
        let format = value(Object.feedStream, kAudioStreamPropertyVirtualFormat, AudioStreamBasicDescription())
        XCTAssertEqual(format?.mChannelsPerFrame, UInt32(MicrophoneContract.channels))
        XCTAssertEqual(format?.mSampleRate, MicrophoneContract.sampleRate)
    }

    func testTheMicrophoneIsSeenAndTheFeedIsHidden() {
        XCTAssertEqual(list(Object.plugIn, kAudioPlugInPropertyDeviceList), [Object.microphone, Object.feed])
        XCTAssertEqual(list(Object.plugIn, kAudioPlugInPropertyDeviceList, room: 1), [Object.microphone], "as many as fit")
        XCTAssertEqual(list(Object.plugIn, kAudioPlugInPropertyBoxList), [])
        XCTAssertEqual(value(Object.microphone, kAudioDevicePropertyIsHidden, UInt32(9)), 0)
        XCTAssertEqual(value(Object.feed, kAudioDevicePropertyIsHidden, UInt32(9)), 1)
        XCTAssertEqual(
            value(Object.microphone, kAudioDevicePropertyDeviceCanBeDefaultDevice, UInt32(9), scope: kAudioObjectPropertyScopeInput), 1
        )
        XCTAssertEqual(value(Object.feed, kAudioDevicePropertyDeviceCanBeDefaultDevice, UInt32(9)), 0)
        // The microphone has an input and no output; the feed the other way round.
        XCTAssertEqual(
            list(Object.microphone, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput), [Object.microphoneStream]
        )
        XCTAssertEqual(list(Object.microphone, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput), [])
        XCTAssertEqual(list(Object.feed, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput), [Object.feedStream])
        XCTAssertEqual(value(Object.microphoneStream, kAudioStreamPropertyDirection, UInt32(9)), 1)
        XCTAssertEqual(value(Object.feedStream, kAudioStreamPropertyDirection, UInt32(9)), 0)
        XCTAssertEqual(value(Object.feedStream, kAudioObjectPropertyOwner, AudioObjectID(0)), Object.feed)
    }

    func testADeviceIsFoundByItsIdentifier() {
        func device(for uid: String) -> AudioObjectID? {
            var address = address(kAudioPlugInPropertyTranslateUIDToDevice)
            var qualifier = uid as CFString
            var found = AudioObjectID(77)
            var used: UInt32 = 0
            let size = UInt32(MemoryLayout<AudioObjectID>.size)
            let status = table.GetPropertyData(
                driver, Object.plugIn, 0, &address, UInt32(MemoryLayout<CFString>.size), &qualifier, size, &used, &found
            )
            return status == 0 ? found : nil
        }
        XCTAssertEqual(device(for: MicrophoneContract.deviceUID), Object.microphone)
        XCTAssertEqual(device(for: MicrophoneContract.feedUID), Object.feed)
        XCTAssertEqual(device(for: "somebody else"), AudioObjectID(kAudioObjectUnknown))
    }

    func testWhatIsNotThereIsRefusedAndNothingCanBeSet() {
        var unknown = address(kAudioDevicePropertyVolumeScalar)
        var name = address(kAudioObjectPropertyName)
        XCTAssertFalse(table.HasProperty(driver, Object.microphone, 0, &unknown).boolValue)
        XCTAssertTrue(table.HasProperty(driver, Object.microphone, 0, &name).boolValue)
        XCTAssertFalse(table.HasProperty(driver, Object.nothing, 0, &name).boolValue)
        var settable: DarwinBoolean = true
        XCTAssertEqual(table.IsPropertySettable(driver, Object.microphone, 0, &name, &settable), 0)
        XCTAssertFalse(settable.boolValue)
        XCTAssertNotEqual(table.IsPropertySettable(driver, Object.microphone, 0, &unknown, &settable), 0)
        var size: UInt32 = 0
        XCTAssertEqual(table.GetPropertyDataSize(driver, Object.microphone, 0, &name, 0, nil, &size), 0)
        XCTAssertEqual(Int(size), MemoryLayout<CFString>.size)
        XCTAssertNotEqual(table.GetPropertyDataSize(driver, Object.feedStream, 0, &unknown, 0, nil, &size), 0)
        var rate = 44100.0
        XCTAssertNotEqual(table.SetPropertyData(driver, Object.microphone, 0, &name, 0, nil, 8, &rate), 0)
        // Too little room for a value is an error, not a short answer.
        var small: UInt8 = 0
        var used: UInt32 = 0
        XCTAssertNotEqual(table.GetPropertyData(driver, Object.microphone, 0, &name, 0, nil, 1, &used, &small), 0)
        XCTAssertNotEqual(table.StartIO(driver, Object.nothing, 0), 0)
        XCTAssertNotEqual(table.AddDeviceClient(driver, Object.nothing, &client), 0)
        XCTAssertEqual(table.AddDeviceClient(driver, Object.feed, &client), 0)
        XCTAssertEqual(table.RemoveDeviceClient(driver, Object.feed, &client), 0)
        var made = AudioObjectID(0)
        XCTAssertNotEqual(table.CreateDevice(driver, [:] as CFDictionary, &client, &made), 0)
        XCTAssertNotEqual(table.DestroyDevice(driver, Object.feed), 0)
    }

    func testWhatIsPlayedToTheFeedIsWhatTheMicrophoneHears() {
        let write = AudioServerPlugInIOOperation.writeMix.rawValue
        let read = AudioServerPlugInIOOperation.readInput.rawValue
        var willDo: DarwinBoolean = false
        var inPlace: DarwinBoolean = false
        XCTAssertEqual(table.WillDoIOOperation(driver, Object.feed, 0, write, &willDo, &inPlace), 0)
        XCTAssertTrue(willDo.boolValue)
        XCTAssertEqual(table.WillDoIOOperation(driver, Object.feed, 0, read, &willDo, &inPlace), 0)
        XCTAssertFalse(willDo.boolValue, "the feed has nothing to listen to")
        XCTAssertEqual(table.WillDoIOOperation(driver, Object.microphone, 0, read, &willDo, &inPlace), 0)
        XCTAssertTrue(willDo.boolValue)

        XCTAssertEqual(table.StartIO(driver, Object.feed, 0), 0)
        XCTAssertEqual(table.StartIO(driver, Object.microphone, 0), 0)
        XCTAssertEqual(value(Object.feed, kAudioDevicePropertyDeviceIsRunning, UInt32(9)), 1)

        var sampleTime = -1.0
        var hostTime: UInt64 = 0
        var seed: UInt64 = 0
        XCTAssertEqual(table.GetZeroTimeStamp(driver, Object.microphone, 0, &sampleTime, &hostTime, &seed), 0)
        XCTAssertEqual(sampleTime, 0, "the clock starts when the first device does")
        XCTAssertGreaterThan(hostTime, 0)

        let frames: UInt32 = 256
        let channels = MicrophoneContract.channels
        var played = (0..<Int(frames) * channels).map { Float32($0 + 1) }
        var cycle = AudioServerPlugInIOCycleInfo()
        cycle.mOutputTime.mSampleTime = 1000
        XCTAssertEqual(table.BeginIOOperation(driver, Object.feed, 0, write, frames, &cycle), 0)
        XCTAssertEqual(table.DoIOOperation(driver, Object.feed, Object.feedStream, 0, write, frames, &cycle, &played, nil), 0)
        XCTAssertEqual(table.EndIOOperation(driver, Object.feed, 0, write, frames, &cycle), 0)

        func heard(from start: Double) -> [Float32] {
            var buffer = [Float32](repeating: -1, count: Int(frames) * channels)
            var cycle = AudioServerPlugInIOCycleInfo()
            cycle.mInputTime.mSampleTime = start
            XCTAssertEqual(
                table.DoIOOperation(driver, Object.microphone, Object.microphoneStream, 0, read, frames, &cycle, &buffer, nil), 0
            )
            return buffer
        }
        XCTAssertEqual(heard(from: 1000), played, "the same sound, at the same moment")
        // Half of this stretch was played and half was not yet.
        let straddling = heard(from: 1128)
        XCTAssertEqual(Array(straddling.prefix(128 * channels)), Array(played.suffix(128 * channels)))
        XCTAssertEqual(Array(straddling.suffix(128 * channels)), [Float32](repeating: 0, count: 128 * channels))
        XCTAssertEqual(heard(from: 5000), [Float32](repeating: 0, count: Int(frames) * channels), "nothing played is silence")

        XCTAssertEqual(table.StopIO(driver, Object.feed, 0), 0)
        XCTAssertEqual(table.StopIO(driver, Object.microphone, 0), 0)
        XCTAssertEqual(value(Object.feed, kAudioDevicePropertyDeviceIsRunning, UInt32(9)), 0)
        // Started again, nothing of the last run is left to be heard.
        XCTAssertEqual(table.StartIO(driver, Object.microphone, 0), 0)
        XCTAssertEqual(heard(from: 1000), [Float32](repeating: 0, count: Int(frames) * channels))
        XCTAssertEqual(table.StopIO(driver, Object.microphone, 0), 0)
    }
}
