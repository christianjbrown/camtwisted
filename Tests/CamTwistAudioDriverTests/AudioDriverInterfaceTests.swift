import CamTwistAudioDriver
import CamTwistCore
import CoreAudio
import CoreAudio.AudioServerPlugIn
import XCTest

/// Walks every entry point of the driver's table, every property it answers
/// and every refusal it gives, the way the system's audio server would.
final class AudioDriverInterfaceTests: XCTestCase {
    private enum Object {
        static let plugIn = AudioObjectID(kAudioObjectPlugInObject)
        static let microphone: AudioObjectID = 2
        static let microphoneStream: AudioObjectID = 3
        static let feed: AudioObjectID = 4
        static let feedStream: AudioObjectID = 5
        static let nothing: AudioObjectID = 99
    }

    private enum Status {
        static let badObject = OSStatus(kAudioHardwareBadObjectError)
        static let unknownProperty = OSStatus(kAudioHardwareUnknownPropertyError)
        static let badSize = OSStatus(kAudioHardwareBadPropertySizeError)
        static let illegal = OSStatus(kAudioHardwareIllegalOperationError)
        static let unsupported = OSStatus(kAudioHardwareUnsupportedOperationError)
        static let noInterface = Int32(bitPattern: 0x8000_0004)
    }

    private enum Layout {
        static let frames: UInt32 = 8
        static let channels = 2
        static let ringFrames = 16384
        static let zeroTimeStampPeriod: UInt32 = 16384
        static let idSize = MemoryLayout<AudioObjectID>.size
        static let scalarSize = MemoryLayout<UInt32>.size
        static let formatSize = MemoryLayout<AudioStreamBasicDescription>.size
        static let rangedFormatSize = MemoryLayout<AudioStreamRangedDescription>.size
        static let rangeSize = MemoryLayout<AudioValueRange>.size
        static let sampleRate = 48000.0
        static let poisoned: UInt8 = 0xAB
        static let longWait: TimeInterval = 3
        static let pollStep: TimeInterval = 0.02
    }

    private static let iUnknown = "00000000-0000-0000-C000-000000000046"
    private static let driverInterface = "EEA5773D-CC43-49F1-8E00-8F96E7D23B17"
    private static let serverPlugIn = "443ABAB8-E7B3-491A-B985-BEB9187030DB"

    private let write = AudioServerPlugInIOOperation.writeMix.rawValue
    private let read = AudioServerPlugInIOOperation.readInput.rawValue
    private let otherOperation = AudioServerPlugInIOOperation.processOutput.rawValue

    private var driver: AudioServerPlugInDriverRef!
    private let host = UnsafeMutablePointer<AudioServerPlugInHostInterface>.allocate(capacity: 1)
    private var client = AudioServerPlugInClientInfo()
    private var table: AudioServerPlugInDriverInterface { driver.pointee!.pointee }

    override func setUp() {
        let made = CamTwistAudioDriver_Create(
            nil, CFUUIDCreateFromString(nil, Self.serverPlugIn as CFString)
        )
        driver = made?.assumingMemoryBound(to: UnsafeMutablePointer<AudioServerPlugInDriverInterface>?.self)
        XCTAssertEqual(table.Initialize(driver, host), 0)
    }

    override func tearDown() {
        host.deallocate()
    }

    // MARK: Helpers

    private func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private struct Fetched {
        var status: OSStatus
        var used: UInt32
        var bytes: [UInt8]

        func scalar() -> UInt32 { load(UInt32.self) }
        func load<Value>(_ type: Value.Type) -> Value {
            bytes.withUnsafeBytes { $0.loadUnaligned(as: type) }
        }
    }

    /// Asks for a property's data with `room` bytes to put it in.
    private func fetch(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, room: Int = 64
    ) -> Fetched {
        var address = address(selector, scope: scope)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: max(room, 1), alignment: 16)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: Layout.poisoned, count: max(room, 1))
        var used: UInt32 = 0
        let status = table.GetPropertyData(driver, object, 0, &address, 0, nil, UInt32(room), &used, buffer)
        let kept = status == 0 ? min(Int(used), room) : 0
        return Fetched(
            status: status, used: used, bytes: Array(UnsafeRawBufferPointer(start: buffer, count: kept))
        )
    }

    private func size(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> (status: OSStatus, size: UInt32) {
        var address = address(selector, scope: scope)
        var size: UInt32 = 12345
        let status = table.GetPropertyDataSize(driver, object, 0, &address, 0, nil, &size)
        return (status, size)
    }

    private func ids(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, room: Int = 64
    ) -> [AudioObjectID] {
        let fetched = fetch(object, selector, scope: scope, room: room)
        XCTAssertEqual(fetched.status, 0)
        return stride(from: 0, to: fetched.bytes.count, by: Layout.idSize).map { offset in
            fetched.bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: AudioObjectID.self) }
        }
    }

    private func text(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        let fetched = fetch(object, selector)
        guard fetched.status == 0 else { return nil }
        return fetched.load(Unmanaged<CFString>.self).takeUnretainedValue() as String
    }

    private func uuidBytes(_ text: String) -> CFUUIDBytes {
        CFUUIDGetUUIDBytes(CFUUIDCreateFromString(nil, text as CFString))
    }

    private func translate(
        _ uid: String, qualifierSize: Int? = nil, passQualifier: Bool = true
    ) -> (status: OSStatus, device: AudioObjectID) {
        var address = address(kAudioPlugInPropertyTranslateUIDToDevice)
        var qualifier = uid as CFString
        var found = AudioObjectID(77)
        var used: UInt32 = 0
        let size = UInt32(Layout.idSize)
        let declared = UInt32(qualifierSize ?? MemoryLayout<CFString>.size)
        let status = passQualifier
            ? table.GetPropertyData(driver, Object.plugIn, 0, &address, declared, &qualifier, size, &used, &found)
            : table.GetPropertyData(driver, Object.plugIn, 0, &address, declared, nil, size, &used, &found)
        return (status, found)
    }

    private func start(_ device: AudioObjectID) {
        XCTAssertEqual(table.StartIO(driver, device, 0), 0)
    }

    private func stop(_ device: AudioObjectID) {
        XCTAssertEqual(table.StopIO(driver, device, 0), 0)
    }

    private func running(_ device: AudioObjectID) -> UInt32 {
        fetch(device, kAudioDevicePropertyDeviceIsRunning).scalar()
    }

    private func zeroTimeStamp(_ device: AudioObjectID) -> (status: OSStatus, sample: Float64, host: UInt64, seed: UInt64) {
        var sample = -1.0
        var hostTime: UInt64 = 0
        var seed: UInt64 = 0
        let status = table.GetZeroTimeStamp(driver, device, 0, &sample, &hostTime, &seed)
        return (status, sample, hostTime, seed)
    }

    private func play(_ samples: [Float32], at time: Double, to device: AudioObjectID = Object.feed) -> OSStatus {
        var samples = samples
        var cycle = AudioServerPlugInIOCycleInfo()
        cycle.mOutputTime.mSampleTime = time
        let stream = device == Object.feed ? Object.feedStream : Object.microphoneStream
        return table.DoIOOperation(
            driver, device, stream, 0, write, UInt32(samples.count / Layout.channels), &cycle, &samples, nil
        )
    }

    private func hear(frames: Int, from time: Double) -> [Float32] {
        var buffer = [Float32](repeating: -1, count: frames * Layout.channels)
        var cycle = AudioServerPlugInIOCycleInfo()
        cycle.mInputTime.mSampleTime = time
        XCTAssertEqual(
            table.DoIOOperation(
                driver, Object.microphone, Object.microphoneStream, 0, read, UInt32(frames), &cycle, &buffer, nil
            ),
            0
        )
        return buffer
    }

    private func ramp(frames: Int, from first: Float32 = 1) -> [Float32] {
        (0..<(frames * Layout.channels)).map { first + Float32($0) }
    }

    private func silence(frames: Int) -> [Float32] {
        [Float32](repeating: 0, count: frames * Layout.channels)
    }

    /// The C table's pointers are not optional in Swift, but the driver checks
    /// for NULL, so a test has to be able to send one.
    private func null<Pointee>(_ type: Pointee.Type) -> UnsafePointer<Pointee> {
        unsafeBitCast(0 as Int, to: UnsafePointer<Pointee>.self)
    }

    private func nullMutable<Pointee>(_ type: Pointee.Type) -> UnsafeMutablePointer<Pointee> {
        unsafeBitCast(0 as Int, to: UnsafeMutablePointer<Pointee>.self)
    }

    private var nullBuffer: UnsafeMutableRawPointer {
        unsafeBitCast(0 as Int, to: UnsafeMutableRawPointer.self)
    }

    // MARK: Lifetime

    func testTheFactoryHandsBackTheSameDriverEveryTime() {
        let again = CamTwistAudioDriver_Create(
            nil, CFUUIDCreateFromString(nil, Self.serverPlugIn as CFString)
        )
        XCTAssertEqual(again, UnsafeMutableRawPointer(driver))
    }

    func testTheDriverAnswersToItsOwnInterfaceAndToIUnknown() {
        var interface: UnsafeMutableRawPointer?
        XCTAssertEqual(table.QueryInterface(driver, uuidBytes(Self.iUnknown), &interface), 0)
        XCTAssertEqual(interface, UnsafeMutableRawPointer(driver))
        interface = nil
        XCTAssertEqual(table.QueryInterface(driver, uuidBytes(Self.driverInterface), &interface), 0)
        XCTAssertEqual(interface, UnsafeMutableRawPointer(driver))
    }

    func testAnInterfaceItDoesNotKnowIsRefusedAndNothingIsHandedOut() {
        var interface: UnsafeMutableRawPointer?
        XCTAssertEqual(
            table.QueryInterface(driver, CFUUIDGetUUIDBytes(CFUUIDCreate(nil)), &interface), Status.noInterface
        )
        XCTAssertNil(interface)
    }

    func testAskingForAnInterfaceNeedsTheRealDriverAndSomewhereToPutIt() {
        var interface: UnsafeMutableRawPointer?
        let stranger = UnsafeMutablePointer<UnsafeMutablePointer<AudioServerPlugInDriverInterface>?>.allocate(capacity: 1)
        defer { stranger.deallocate() }
        XCTAssertEqual(table.QueryInterface(stranger, uuidBytes(Self.iUnknown), &interface), Status.badObject)
        XCTAssertEqual(table.QueryInterface(driver, uuidBytes(Self.iUnknown), nil), Status.badObject)
        XCTAssertNil(interface)
    }

    func testTheReferenceCountGoesUpAndDownAndStopsAtNothing() {
        while table.Release(driver) > 0 {}
        XCTAssertEqual(table.Release(driver), 0, "released more often than held stays at nothing")
        XCTAssertEqual(table.AddRef(driver), 1)
        XCTAssertEqual(table.AddRef(driver), 2)
        XCTAssertEqual(table.Release(driver), 1)
        XCTAssertEqual(table.Release(driver), 0)
    }

    func testInitializeNeedsTheRealDriver() {
        let stranger = UnsafeMutablePointer<UnsafeMutablePointer<AudioServerPlugInDriverInterface>?>.allocate(capacity: 1)
        defer { stranger.deallocate() }
        XCTAssertEqual(table.Initialize(stranger, host), Status.badObject)
        XCTAssertEqual(table.Initialize(driver, host), 0)
    }

    // MARK: Devices that never change

    func testNoDeviceIsMadeOrTakenAway() {
        var made = AudioObjectID(0)
        XCTAssertEqual(table.CreateDevice(driver, [:] as CFDictionary, &client, &made), Status.unsupported)
        XCTAssertEqual(table.DestroyDevice(driver, Object.feed), Status.unsupported)
        XCTAssertEqual(table.DestroyDevice(driver, Object.nothing), Status.unsupported)
    }

    func testClientsComeAndGoOnBothDevicesButNotOnAnythingElse() {
        for device in [Object.microphone, Object.feed] {
            XCTAssertEqual(table.AddDeviceClient(driver, device, &client), 0)
            XCTAssertEqual(table.RemoveDeviceClient(driver, device, &client), 0)
        }
        XCTAssertEqual(table.AddDeviceClient(driver, Object.nothing, &client), Status.badObject)
        XCTAssertEqual(table.AddDeviceClient(driver, Object.microphoneStream, &client), Status.badObject)
        XCTAssertEqual(table.RemoveDeviceClient(driver, Object.nothing, &client), Status.badObject)
    }

    func testConfigurationChangesAreAcceptedOnBothDevicesAndRefusedElsewhere() {
        for device in [Object.microphone, Object.feed] {
            XCTAssertEqual(table.PerformDeviceConfigurationChange(driver, device, 0, nil), 0)
            XCTAssertEqual(table.AbortDeviceConfigurationChange(driver, device, 0, nil), 0)
        }
        XCTAssertEqual(table.PerformDeviceConfigurationChange(driver, Object.nothing, 0, nil), Status.badObject)
        XCTAssertEqual(table.AbortDeviceConfigurationChange(driver, Object.nothing, 0, nil), Status.badObject)
    }

    // MARK: Plug-in properties

    func testThePlugInDescribesItself() {
        XCTAssertEqual(fetch(Object.plugIn, kAudioObjectPropertyBaseClass).scalar(), kAudioObjectClassID)
        XCTAssertEqual(fetch(Object.plugIn, kAudioObjectPropertyClass).scalar(), kAudioPlugInClassID)
        XCTAssertEqual(fetch(Object.plugIn, kAudioObjectPropertyOwner).scalar(), AudioObjectID(kAudioObjectUnknown))
        XCTAssertEqual(text(Object.plugIn, kAudioObjectPropertyManufacturer), MicrophoneContract.manufacturer)
        XCTAssertEqual(text(Object.plugIn, kAudioPlugInPropertyResourceBundle), "")
        XCTAssertEqual(
            fetch(Object.plugIn, kAudioPlugInPropertyTranslateUIDToBox).scalar(), AudioObjectID(kAudioObjectUnknown)
        )
    }

    func testThePlugInOwnsAndListsBothDevicesAndNoBoxes() {
        let both = [Object.microphone, Object.feed]
        XCTAssertEqual(ids(Object.plugIn, kAudioObjectPropertyOwnedObjects), both)
        XCTAssertEqual(ids(Object.plugIn, kAudioPlugInPropertyDeviceList), both)
        XCTAssertEqual(ids(Object.plugIn, kAudioPlugInPropertyDeviceList, room: Layout.idSize), [Object.microphone])
        XCTAssertEqual(ids(Object.plugIn, kAudioPlugInPropertyDeviceList, room: 0), [])
        XCTAssertEqual(ids(Object.plugIn, kAudioPlugInPropertyBoxList), [])
        XCTAssertEqual(size(Object.plugIn, kAudioPlugInPropertyDeviceList).size, UInt32(2 * Layout.idSize))
        XCTAssertEqual(size(Object.plugIn, kAudioObjectPropertyOwnedObjects).size, UInt32(2 * Layout.idSize))
        XCTAssertEqual(size(Object.plugIn, kAudioPlugInPropertyBoxList).size, 0)
    }

    func testADeviceIsFoundByItsIdentifierOnlyWhenTheQuestionIsWellFormed() {
        XCTAssertEqual(translate(MicrophoneContract.deviceUID).device, Object.microphone)
        XCTAssertEqual(translate(MicrophoneContract.feedUID).device, Object.feed)
        XCTAssertEqual(translate("somebody else").device, AudioObjectID(kAudioObjectUnknown))
        XCTAssertEqual(
            translate(MicrophoneContract.deviceUID, qualifierSize: 3).device, AudioObjectID(kAudioObjectUnknown),
            "a qualifier of the wrong size names nothing"
        )
        XCTAssertEqual(
            translate(MicrophoneContract.deviceUID, passQualifier: false).device, AudioObjectID(kAudioObjectUnknown),
            "no qualifier names nothing"
        )
        XCTAssertEqual(translate("somebody else").status, 0)
    }

    func testThePlugInRefusesWhatItDoesNotKnow() {
        XCTAssertEqual(fetch(Object.plugIn, kAudioDevicePropertyVolumeScalar).status, Status.unknownProperty)
        XCTAssertEqual(size(Object.plugIn, kAudioDevicePropertyVolumeScalar).status, Status.unknownProperty)
    }

    // MARK: Device properties

    func testEachDeviceDescribesItself() {
        for (device, name, uid) in [
            (Object.microphone, MicrophoneContract.deviceName, MicrophoneContract.deviceUID),
            (Object.feed, MicrophoneContract.feedName, MicrophoneContract.feedUID),
        ] {
            XCTAssertEqual(fetch(device, kAudioObjectPropertyBaseClass).scalar(), kAudioObjectClassID)
            XCTAssertEqual(fetch(device, kAudioObjectPropertyClass).scalar(), kAudioDeviceClassID)
            XCTAssertEqual(fetch(device, kAudioObjectPropertyOwner).scalar(), Object.plugIn)
            XCTAssertEqual(text(device, kAudioObjectPropertyName), name)
            XCTAssertEqual(text(device, kAudioObjectPropertyManufacturer), MicrophoneContract.manufacturer)
            XCTAssertEqual(text(device, kAudioDevicePropertyDeviceUID), uid)
            XCTAssertEqual(text(device, kAudioDevicePropertyModelUID), "CamTwistedMicrophoneModel")
            XCTAssertEqual(fetch(device, kAudioDevicePropertyTransportType).scalar(), kAudioDeviceTransportTypeVirtual)
            XCTAssertEqual(ids(device, kAudioDevicePropertyRelatedDevices), [device])
            XCTAssertEqual(fetch(device, kAudioDevicePropertyClockDomain).scalar(), 0)
            XCTAssertEqual(fetch(device, kAudioDevicePropertyDeviceIsAlive).scalar(), 1)
            XCTAssertEqual(fetch(device, kAudioDevicePropertyDeviceCanBeDefaultSystemDevice).scalar(), 0)
            XCTAssertEqual(fetch(device, kAudioDevicePropertyLatency).scalar(), 0)
            XCTAssertEqual(fetch(device, kAudioDevicePropertySafetyOffset).scalar(), 0)
            XCTAssertEqual(fetch(device, kAudioDevicePropertyZeroTimeStampPeriod).scalar(), Layout.zeroTimeStampPeriod)
            XCTAssertEqual(fetch(device, kAudioDevicePropertyClockIsStable).scalar(), 1)
            XCTAssertEqual(fetch(device, kAudioDevicePropertyNominalSampleRate).load(Float64.self), Layout.sampleRate)
            XCTAssertEqual(fetch(device, kAudioDevicePropertyNominalSampleRate).used, 8)
        }
    }

    func testTheHiddenFeedAndTheVisibleMicrophone() {
        XCTAssertEqual(fetch(Object.microphone, kAudioDevicePropertyIsHidden).scalar(), 0)
        XCTAssertEqual(fetch(Object.feed, kAudioDevicePropertyIsHidden).scalar(), 1)
    }

    func testOnlyTheMicrophoneCanBeTheDefaultAndOnlyToListenTo() {
        let mic = Object.microphone
        let can = kAudioDevicePropertyDeviceCanBeDefaultDevice
        XCTAssertEqual(fetch(mic, can, scope: kAudioObjectPropertyScopeInput).scalar(), 1)
        XCTAssertEqual(fetch(mic, can).scalar(), 1)
        XCTAssertEqual(fetch(mic, can, scope: kAudioObjectPropertyScopeOutput).scalar(), 0)
        XCTAssertEqual(fetch(Object.feed, can, scope: kAudioObjectPropertyScopeInput).scalar(), 0)
        XCTAssertEqual(fetch(Object.feed, can, scope: kAudioObjectPropertyScopeOutput).scalar(), 0)
    }

    func testTheOneRateIsTheOnlyRateOffered() {
        let fetched = fetch(Object.microphone, kAudioDevicePropertyAvailableNominalSampleRates)
        XCTAssertEqual(fetched.used, UInt32(Layout.rangeSize))
        let range = fetched.load(AudioValueRange.self)
        XCTAssertEqual(range.mMinimum, Layout.sampleRate)
        XCTAssertEqual(range.mMaximum, Layout.sampleRate)
        XCTAssertEqual(size(Object.feed, kAudioDevicePropertyAvailableNominalSampleRates).size, UInt32(Layout.rangeSize))
        XCTAssertEqual(fetch(Object.feed, kAudioDevicePropertyAvailableNominalSampleRates, room: 4).used, 0)
    }

    func testStereoIsChannelsOneAndTwo() {
        let fetched = fetch(Object.microphone, kAudioDevicePropertyPreferredChannelsForStereo)
        XCTAssertEqual(fetched.used, 8)
        XCTAssertEqual(fetched.bytes.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }, [1, 2])
        XCTAssertEqual(size(Object.microphone, kAudioDevicePropertyPreferredChannelsForStereo).size, 8)
        XCTAssertEqual(
            fetch(Object.microphone, kAudioDevicePropertyPreferredChannelsForStereo, room: 4).status, Status.badSize
        )
    }

    func testEachDeviceHasItsOneStreamInTheRightDirectionAndNoControls() {
        let input = kAudioObjectPropertyScopeInput
        let output = kAudioObjectPropertyScopeOutput
        let global = kAudioObjectPropertyScopeGlobal
        for selector in [kAudioDevicePropertyStreams, kAudioObjectPropertyOwnedObjects] {
            XCTAssertEqual(ids(Object.microphone, selector, scope: input), [Object.microphoneStream])
            XCTAssertEqual(ids(Object.microphone, selector, scope: global), [Object.microphoneStream])
            XCTAssertEqual(ids(Object.microphone, selector, scope: output), [])
            XCTAssertEqual(ids(Object.feed, selector, scope: output), [Object.feedStream])
            XCTAssertEqual(ids(Object.feed, selector, scope: global), [Object.feedStream])
            XCTAssertEqual(ids(Object.feed, selector, scope: input), [])
        }
        XCTAssertEqual(size(Object.microphone, kAudioDevicePropertyStreams, scope: input).size, UInt32(Layout.idSize))
        XCTAssertEqual(size(Object.microphone, kAudioDevicePropertyStreams, scope: output).size, 0)
        XCTAssertEqual(ids(Object.microphone, kAudioObjectPropertyControlList), [])
        XCTAssertEqual(ids(Object.feed, kAudioObjectPropertyControlList), [])
    }

    func testADeviceReportsRunningOnlyWhileSomeoneIsUsingIt() {
        XCTAssertEqual(running(Object.microphone), 0)
        XCTAssertEqual(running(Object.feed), 0)
        start(Object.microphone)
        XCTAssertEqual(running(Object.microphone), 1)
        XCTAssertEqual(running(Object.feed), 0)
        stop(Object.microphone)
        start(Object.feed)
        XCTAssertEqual(running(Object.microphone), 0)
        XCTAssertEqual(running(Object.feed), 1)
        stop(Object.feed)
    }

    func testADeviceRefusesWhatItDoesNotKnow() {
        XCTAssertEqual(fetch(Object.microphone, kAudioDevicePropertyVolumeScalar).status, Status.unknownProperty)
        XCTAssertEqual(size(Object.feed, kAudioDevicePropertyVolumeScalar).status, Status.unknownProperty)
    }

    // MARK: Stream properties

    func testEachStreamDescribesItself() {
        for (stream, owner, isInput) in [
            (Object.microphoneStream, Object.microphone, true),
            (Object.feedStream, Object.feed, false),
        ] {
            XCTAssertEqual(fetch(stream, kAudioObjectPropertyBaseClass).scalar(), kAudioObjectClassID)
            XCTAssertEqual(fetch(stream, kAudioObjectPropertyClass).scalar(), kAudioStreamClassID)
            XCTAssertEqual(fetch(stream, kAudioObjectPropertyOwner).scalar(), owner)
            XCTAssertEqual(ids(stream, kAudioObjectPropertyOwnedObjects), [])
            XCTAssertEqual(fetch(stream, kAudioStreamPropertyIsActive).scalar(), 1)
            XCTAssertEqual(fetch(stream, kAudioStreamPropertyDirection).scalar(), isInput ? 1 : 0)
            XCTAssertEqual(
                fetch(stream, kAudioStreamPropertyTerminalType).scalar(),
                isInput ? kAudioStreamTerminalTypeMicrophone : kAudioStreamTerminalTypeSpeaker
            )
            XCTAssertEqual(fetch(stream, kAudioStreamPropertyStartingChannel).scalar(), 1)
            XCTAssertEqual(fetch(stream, kAudioStreamPropertyLatency).scalar(), 0)
        }
    }

    func testEveryStreamFormatIsFloatStereoAtTheOneRate() {
        for stream in [Object.microphoneStream, Object.feedStream] {
            for selector in [kAudioStreamPropertyVirtualFormat, kAudioStreamPropertyPhysicalFormat] {
                let fetched = fetch(stream, selector)
                XCTAssertEqual(fetched.used, UInt32(Layout.formatSize))
                let format = fetched.load(AudioStreamBasicDescription.self)
                XCTAssertEqual(format.mSampleRate, Layout.sampleRate)
                XCTAssertEqual(format.mFormatID, kAudioFormatLinearPCM)
                XCTAssertEqual(
                    format.mFormatFlags,
                    kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked
                )
                XCTAssertEqual(format.mBytesPerPacket, 8)
                XCTAssertEqual(format.mFramesPerPacket, 1)
                XCTAssertEqual(format.mBytesPerFrame, 8)
                XCTAssertEqual(format.mChannelsPerFrame, 2)
                XCTAssertEqual(format.mBitsPerChannel, 32)
            }
            for selector in [kAudioStreamPropertyAvailableVirtualFormats, kAudioStreamPropertyAvailablePhysicalFormats] {
                let fetched = fetch(stream, selector)
                XCTAssertEqual(fetched.used, UInt32(Layout.rangedFormatSize))
                let only = fetched.load(AudioStreamRangedDescription.self)
                XCTAssertEqual(only.mFormat.mChannelsPerFrame, 2)
                XCTAssertEqual(only.mSampleRateRange.mMinimum, Layout.sampleRate)
                XCTAssertEqual(only.mSampleRateRange.mMaximum, Layout.sampleRate)
                XCTAssertEqual(size(stream, selector).size, UInt32(Layout.rangedFormatSize))
            }
        }
    }

    func testAStreamRefusesWhatItDoesNotKnow() {
        XCTAssertEqual(fetch(Object.feedStream, kAudioDevicePropertyVolumeScalar).status, Status.unknownProperty)
        XCTAssertEqual(size(Object.microphoneStream, kAudioDevicePropertyVolumeScalar).status, Status.unknownProperty)
    }

    // MARK: Property questions in general

    func testAnObjectThatIsNotThereHasNoProperties() {
        XCTAssertEqual(fetch(Object.nothing, kAudioObjectPropertyName).status, Status.badObject)
        XCTAssertEqual(size(Object.nothing, kAudioObjectPropertyName).status, Status.badObject)
    }

    func testAValueNeedsRoomForItselfButAListTakesWhatFits() {
        let scalars: [(AudioObjectID, AudioObjectPropertySelector)] = [
            (Object.plugIn, kAudioObjectPropertyClass),
            (Object.plugIn, kAudioObjectPropertyManufacturer),
            (Object.microphone, kAudioDevicePropertyNominalSampleRate),
            (Object.microphone, kAudioDevicePropertyDeviceIsRunning),
            (Object.microphone, kAudioDevicePropertyDeviceCanBeDefaultDevice),
            (Object.feedStream, kAudioStreamPropertyVirtualFormat),
        ]
        for (object, selector) in scalars {
            XCTAssertEqual(fetch(object, selector, room: 1).status, Status.badSize)
            XCTAssertEqual(fetch(object, selector, room: 0).status, Status.badSize)
        }
        XCTAssertEqual(fetch(Object.microphone, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput, room: 3).used, 0)
    }

    func testEveryPropertyIsThereIsNotSettableAndRefusesToBeSet() {
        let every = Self.everyProperty
        for (object, selectors) in every {
            for selector in selectors {
                var property = address(selector)
                var settable: DarwinBoolean = true
                XCTAssertTrue(table.HasProperty(driver, object, 0, &property).boolValue, "\(object) \(selector)")
                XCTAssertEqual(table.IsPropertySettable(driver, object, 0, &property, &settable), 0)
                XCTAssertFalse(settable.boolValue)
                var value: UInt32 = 0
                XCTAssertEqual(
                    table.SetPropertyData(driver, object, 0, &property, 0, nil, 4, &value), Status.unsupported
                )
            }
        }
    }

    private static let everyProperty: [(AudioObjectID, [AudioObjectPropertySelector])] = [
            (Object.plugIn, [
                kAudioObjectPropertyBaseClass, kAudioObjectPropertyClass, kAudioObjectPropertyOwner,
                kAudioObjectPropertyManufacturer, kAudioObjectPropertyOwnedObjects, kAudioPlugInPropertyDeviceList,
                kAudioPlugInPropertyBoxList, kAudioPlugInPropertyTranslateUIDToBox,
                kAudioPlugInPropertyTranslateUIDToDevice, kAudioPlugInPropertyResourceBundle,
            ]),
            (Object.microphone, deviceSelectors),
            (Object.feed, deviceSelectors),
            (Object.microphoneStream, streamSelectors),
            (Object.feedStream, streamSelectors),
        ]

    /// Properties that are lists, which hand over as many items as fit rather than refusing.
    private static let listSelectors: Set<AudioObjectPropertySelector> = [
        kAudioObjectPropertyOwnedObjects, kAudioPlugInPropertyDeviceList, kAudioPlugInPropertyBoxList,
        kAudioDevicePropertyRelatedDevices, kAudioDevicePropertyStreams, kAudioObjectPropertyControlList,
        kAudioDevicePropertyAvailableNominalSampleRates, kAudioStreamPropertyAvailableVirtualFormats,
        kAudioStreamPropertyAvailablePhysicalFormats,
    ]

    private static let deviceSelectors: [AudioObjectPropertySelector] = [
        kAudioObjectPropertyBaseClass, kAudioObjectPropertyClass, kAudioObjectPropertyOwner,
        kAudioObjectPropertyName, kAudioObjectPropertyManufacturer, kAudioDevicePropertyDeviceUID,
        kAudioDevicePropertyModelUID, kAudioDevicePropertyTransportType, kAudioDevicePropertyRelatedDevices,
        kAudioDevicePropertyClockDomain, kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyDeviceIsRunning,
        kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioDevicePropertyDeviceCanBeDefaultSystemDevice,
        kAudioDevicePropertyLatency, kAudioDevicePropertySafetyOffset, kAudioObjectPropertyOwnedObjects,
        kAudioDevicePropertyStreams, kAudioObjectPropertyControlList, kAudioDevicePropertyNominalSampleRate,
        kAudioDevicePropertyAvailableNominalSampleRates, kAudioDevicePropertyIsHidden,
        kAudioDevicePropertyPreferredChannelsForStereo, kAudioDevicePropertyZeroTimeStampPeriod,
        kAudioDevicePropertyClockIsStable,
    ]

    private static let streamSelectors: [AudioObjectPropertySelector] = [
        kAudioObjectPropertyBaseClass, kAudioObjectPropertyClass, kAudioObjectPropertyOwner,
        kAudioObjectPropertyOwnedObjects, kAudioStreamPropertyIsActive, kAudioStreamPropertyDirection,
        kAudioStreamPropertyTerminalType, kAudioStreamPropertyStartingChannel, kAudioStreamPropertyLatency,
        kAudioStreamPropertyVirtualFormat, kAudioStreamPropertyPhysicalFormat,
        kAudioStreamPropertyAvailableVirtualFormats, kAudioStreamPropertyAvailablePhysicalFormats,
    ]

    func testEveryValueRefusesTooLittleRoomAndEveryListGivesNothingInstead() {
        for (object, selectors) in Self.everyProperty {
            for selector in selectors where selector != kAudioPlugInPropertyTranslateUIDToDevice {
                let tiny = fetch(object, selector, room: 1)
                if Self.listSelectors.contains(selector) {
                    XCTAssertEqual(tiny.status, 0, "\(object) \(selector)")
                    XCTAssertEqual(tiny.used, 0)
                } else {
                    XCTAssertEqual(tiny.status, Status.badSize, "\(object) \(selector)")
                }
            }
        }
        var address = address(kAudioPlugInPropertyTranslateUIDToDevice)
        var used: UInt32 = 0
        var found = AudioObjectID(0)
        XCTAssertEqual(
            table.GetPropertyData(driver, Object.plugIn, 0, &address, 0, nil, 1, &used, &found), Status.badSize
        )
    }

    func testAnUnknownPropertyOrObjectCannotBeSetOrChecked() {
        var unknown = address(kAudioDevicePropertyVolumeScalar)
        var name = address(kAudioObjectPropertyName)
        var settable: DarwinBoolean = true
        var value: UInt32 = 0
        XCTAssertFalse(table.HasProperty(driver, Object.feed, 0, &unknown).boolValue)
        XCTAssertFalse(table.HasProperty(driver, Object.nothing, 0, &name).boolValue)
        XCTAssertEqual(table.IsPropertySettable(driver, Object.feed, 0, &unknown, &settable), Status.unknownProperty)
        XCTAssertFalse(settable.boolValue)
        XCTAssertEqual(table.SetPropertyData(driver, Object.feed, 0, &unknown, 0, nil, 4, &value), Status.unknownProperty)
        XCTAssertEqual(table.SetPropertyData(driver, Object.nothing, 0, &name, 0, nil, 4, &value), Status.unknownProperty)
    }

    func testMissingArgumentsAreRefusedNotFollowed() {
        var name = address(kAudioObjectPropertyName)
        var size: UInt32 = 0
        var used: UInt32 = 0
        var buffer = [UInt8](repeating: 0, count: 16)
        let noAddress = null(AudioObjectPropertyAddress.self)
        XCTAssertFalse(table.HasProperty(driver, Object.feed, 0, noAddress).boolValue)
        XCTAssertEqual(
            table.IsPropertySettable(driver, Object.feed, 0, &name, nullMutable(DarwinBoolean.self)), Status.illegal
        )
        XCTAssertEqual(table.GetPropertyDataSize(driver, Object.feed, 0, noAddress, 0, nil, &size), Status.illegal)
        XCTAssertEqual(
            table.GetPropertyDataSize(driver, Object.feed, 0, &name, 0, nil, nullMutable(UInt32.self)), Status.illegal
        )
        XCTAssertEqual(
            table.GetPropertyData(driver, Object.feed, 0, &name, 0, nil, 16, &used, nullBuffer), Status.illegal
        )
        XCTAssertEqual(
            table.GetPropertyData(driver, Object.feed, 0, noAddress, 0, nil, 16, &used, &buffer), Status.illegal
        )
        XCTAssertEqual(
            table.GetPropertyData(driver, Object.feed, 0, &name, 0, nil, 16, nullMutable(UInt32.self), &buffer),
            Status.illegal
        )
    }

    // MARK: Running

    func testStartingAndStoppingKeepsCountOfEachDevicesUsers() {
        start(Object.feed)
        start(Object.feed)
        stop(Object.feed)
        XCTAssertEqual(running(Object.feed), 1, "one of two users has stopped")
        stop(Object.feed)
        XCTAssertEqual(running(Object.feed), 0)
        stop(Object.feed)
        stop(Object.microphone)
        XCTAssertEqual(running(Object.feed), 0, "stopping more than started stays at nothing")
        XCTAssertEqual(running(Object.microphone), 0)
        start(Object.feed)
        stop(Object.feed)
    }

    func testStartingOrStoppingSomethingThatIsNotADeviceIsRefused() {
        XCTAssertEqual(table.StartIO(driver, Object.nothing, 0), Status.badObject)
        XCTAssertEqual(table.StartIO(driver, Object.microphoneStream, 0), Status.badObject)
        XCTAssertEqual(table.StopIO(driver, Object.nothing, 0), Status.badObject)
        XCTAssertEqual(table.StopIO(driver, Object.feedStream, 0), Status.badObject)
    }

    func testTheSecondDeviceToStartJoinsTheClockAndKeepsTheSound() {
        start(Object.feed)
        XCTAssertEqual(play(ramp(frames: Int(Layout.frames)), at: 100), 0)
        start(Object.microphone)
        XCTAssertEqual(hear(frames: Int(Layout.frames), from: 100), ramp(frames: Int(Layout.frames)))
        stop(Object.microphone)
        stop(Object.feed)
    }

    func testTheClockStartsAtNothingAndMovesOnOnePeriodAtATime() {
        start(Object.microphone)
        let first = zeroTimeStamp(Object.microphone)
        XCTAssertEqual(first.status, 0)
        XCTAssertEqual(first.sample, 0)
        XCTAssertEqual(first.seed, 1)
        XCTAssertGreaterThan(first.host, 0)
        let deadline = Date().addingTimeInterval(Layout.longWait)
        var later = first
        while later.sample == 0 && Date() < deadline {
            Thread.sleep(forTimeInterval: Layout.pollStep)
            later = zeroTimeStamp(Object.feed)
        }
        XCTAssertEqual(later.sample, Float64(Layout.zeroTimeStampPeriod))
        XCTAssertGreaterThan(later.host, first.host)
        XCTAssertEqual(later.seed, 1)
        stop(Object.microphone)
    }

    func testTheClockRefusesWhatIsNotADevice() {
        XCTAssertEqual(zeroTimeStamp(Object.nothing).status, Status.badObject)
        XCTAssertEqual(zeroTimeStamp(Object.feedStream).status, Status.badObject)
    }

    // MARK: Input and output

    func testEachDeviceSaysWhichOperationsItWillDo() {
        var willDo: DarwinBoolean = true
        var inPlace: DarwinBoolean = false
        XCTAssertEqual(table.WillDoIOOperation(driver, Object.feed, 0, write, &willDo, &inPlace), 0)
        XCTAssertTrue(willDo.boolValue)
        XCTAssertTrue(inPlace.boolValue)
        XCTAssertEqual(table.WillDoIOOperation(driver, Object.feed, 0, read, &willDo, &inPlace), 0)
        XCTAssertFalse(willDo.boolValue, "the feed has nothing to listen to")
        XCTAssertEqual(table.WillDoIOOperation(driver, Object.feed, 0, otherOperation, &willDo, &inPlace), 0)
        XCTAssertFalse(willDo.boolValue)
        XCTAssertEqual(table.WillDoIOOperation(driver, Object.microphone, 0, read, &willDo, &inPlace), 0)
        XCTAssertTrue(willDo.boolValue)
        XCTAssertEqual(table.WillDoIOOperation(driver, Object.microphone, 0, write, &willDo, &inPlace), 0)
        XCTAssertFalse(willDo.boolValue, "the microphone has nothing to play")
        XCTAssertEqual(table.WillDoIOOperation(driver, Object.nothing, 0, read, &willDo, &inPlace), Status.badObject)
    }

    func testBeginningAndEndingAnOperationNeedsADevice() {
        var cycle = AudioServerPlugInIOCycleInfo()
        for device in [Object.microphone, Object.feed] {
            XCTAssertEqual(table.BeginIOOperation(driver, device, 0, read, Layout.frames, &cycle), 0)
            XCTAssertEqual(table.EndIOOperation(driver, device, 0, read, Layout.frames, &cycle), 0)
        }
        XCTAssertEqual(table.BeginIOOperation(driver, Object.nothing, 0, read, Layout.frames, &cycle), Status.badObject)
        XCTAssertEqual(table.EndIOOperation(driver, Object.nothing, 0, read, Layout.frames, &cycle), Status.badObject)
    }

    func testAnOperationOnSomethingThatIsNotADeviceIsRefused() {
        var cycle = AudioServerPlugInIOCycleInfo()
        var samples = ramp(frames: Int(Layout.frames))
        XCTAssertEqual(
            table.DoIOOperation(
                driver, Object.nothing, Object.feedStream, 0, write, Layout.frames, &cycle, &samples, nil
            ),
            Status.badObject
        )
    }

    func testAnOperationTheDeviceDoesNotHandleLeavesTheBufferAlone() {
        start(Object.feed)
        var cycle = AudioServerPlugInIOCycleInfo()
        let original = ramp(frames: Int(Layout.frames))
        var samples = original
        XCTAssertEqual(
            table.DoIOOperation(
                driver, Object.feed, Object.feedStream, 0, read, Layout.frames, &cycle, &samples, nil
            ),
            0
        )
        XCTAssertEqual(samples, original)
        XCTAssertEqual(
            table.DoIOOperation(
                driver, Object.microphone, Object.microphoneStream, 0, write, Layout.frames, &cycle, &samples, nil
            ),
            0
        )
        XCTAssertEqual(samples, original)
        stop(Object.feed)
    }

    func testAnOperationWithoutATimeOrABufferDoesNothing() {
        start(Object.feed)
        var cycle = AudioServerPlugInIOCycleInfo()
        var samples = ramp(frames: Int(Layout.frames))
        XCTAssertEqual(
            table.DoIOOperation(
                driver, Object.feed, Object.feedStream, 0, write, Layout.frames, null(AudioServerPlugInIOCycleInfo.self), &samples, nil
            ),
            0
        )
        XCTAssertEqual(
            table.DoIOOperation(
                driver, Object.feed, Object.feedStream, 0, write, Layout.frames, &cycle, nullBuffer, nil
            ),
            0
        )
        XCTAssertEqual(hear(frames: Int(Layout.frames), from: 0), silence(frames: Int(Layout.frames)))
        stop(Object.feed)
    }

    func testSoundWrittenAcrossTheEndOfTheRingIsHeardWhole() {
        start(Object.feed)
        let frames = Int(Layout.frames)
        let played = ramp(frames: frames)
        let start = Double(Layout.ringFrames - frames / 2)
        XCTAssertEqual(play(played, at: start), 0)
        XCTAssertEqual(hear(frames: frames, from: start), played)
        stop(Object.feed)
    }

    func testOnlySoundThatIsStillInTheRingIsHeard() {
        start(Object.feed)
        let frames = Int(Layout.frames)
        let first = ramp(frames: frames)
        let second = ramp(frames: frames, from: 100)
        XCTAssertEqual(play(first, at: 0), 0)
        XCTAssertEqual(hear(frames: frames, from: 0), first)
        XCTAssertEqual(hear(frames: frames, from: -Double(frames)), silence(frames: frames), "before time began")
        XCTAssertEqual(hear(frames: frames, from: Double(frames)), silence(frames: frames), "not yet played")
        // One whole ring later the same slots hold the new sound.
        XCTAssertEqual(play(second, at: Double(Layout.ringFrames)), 0)
        XCTAssertEqual(hear(frames: frames, from: Double(Layout.ringFrames)), second)
        XCTAssertEqual(hear(frames: frames, from: 0), silence(frames: frames), "written over since")
        stop(Object.feed)
    }
}
