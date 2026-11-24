import XCTest
@testable import CamTwistCore

final class SoundTests: XCTestCase {
    func testSoundIsCarriedUnlessSwitchedOff() {
        XCTAssertTrue(SoundSettings().isOn)
        XCTAssertFalse(SoundSettings(isOn: false).isOn)
        let old = try? JSONDecoder().decode(SoundSettings.self, from: Data(#"{"isOn":true,"microphoneID":"mic"}"#.utf8))
        XCTAssertEqual(old, SoundSettings(isOn: true), "settings that still name a microphone load without it")
    }

    func testAPacketOfSoundLastsItsSamplesOverTheRate() {
        XCTAssertEqual(SoundFormat.standard.packetSeconds, 1024.0 / 48000, accuracy: 0.000001)
        XCTAssertEqual(SoundFormat(sampleRate: 44100, channels: 1, bitsPerSecond: 64000).channels, 1)
    }

    func testTheSoundHeaderNamesTheKindRateAndChannels() {
        // Low complexity AAC (2), 48 kHz (code 3), two channels: 00010 0011 0010 000.
        XCTAssertEqual(FLVAudio.sequenceHeader(for: .standard), Data([0xAF, 0x00, 0x11, 0x90]))
        // 44.1 kHz is code 4 and one channel: 00010 0100 0001 000.
        XCTAssertEqual(
            FLVAudio.sequenceHeader(for: SoundFormat(sampleRate: 44100, channels: 1, bitsPerSecond: 64000)),
            Data([0xAF, 0x00, 0x12, 0x08])
        )
        XCTAssertNil(FLVAudio.sequenceHeader(for: SoundFormat(sampleRate: 12345, channels: 2, bitsPerSecond: 1)))
        XCTAssertEqual(FLVAudio.frame(Data([7, 8])), Data([0xAF, 0x01, 7, 8]))
    }

    func testEachSoundingSourceHasItsLevelAndTheRestHaveNone() {
        let loud = ChainItem(content: .source(.camera(deviceID: "a")), volume: 0.8)
        let quiet = ChainItem(content: .source(.camera(deviceID: "b")))
        let off = ChainItem(isEnabled: false, content: .source(.camera(deviceID: "c")), volume: 1)
        let video = ChainItem(content: .source(.movie(MovieSettings(volume: 0.5))))
        let muted = ChainItem(content: .source(.movie(MovieSettings(isMuted: true, volume: 0.5))))
        let stream = ChainItem(content: .source(.stream(StreamSettings(address: "x", volume: 0.25))))
        let inBranch = ChainItem(content: .source(.camera(deviceID: "d")), volume: 0.3)
        let bars = ChainItem(content: .source(.colorBars), branch: [inBranch])
        let effect = ChainItem(content: .effect(name: "Blur", values: [:]))
        let microphone = ChainItem(content: .source(.microphone(deviceID: nil)), volume: 0.6)
        let scene = SceneConfiguration(items: [loud, quiet, off, video, muted, stream, bars, effect, microphone])
        XCTAssertEqual(SceneSound.levels(in: scene), [
            loud.id: 0.8, quiet.id: 1, video.id: 0.5, muted.id: 0, stream.id: 0.25, inBranch.id: 0.3,
            microphone.id: 0.6,
        ])
        XCTAssertEqual(SceneSound.levels(in: SceneConfiguration()), [:])

        // Scenes are heard when any of them has a source turned up at all.
        let silentCamera = ChainItem(content: .source(.camera(deviceID: "e")), volume: 0)
        let quietScene = SceneConfiguration(items: [silentCamera, muted, bars.branch == nil ? bars : effect])
        XCTAssertFalse(SceneSound.isHeard(in: [quietScene, SceneConfiguration()]))
        XCTAssertFalse(SceneSound.isHeard(in: []))
        XCTAssertTrue(SceneSound.isHeard(in: [quietScene, scene]))
    }
}

final class MicrophoneContractTests: XCTestCase {
    func testTheDriverIsInstalledWhereTheSystemLooksForAudioDrivers() {
        XCTAssertEqual(MicrophoneContract.installedPath, "/Library/Audio/Plug-Ins/HAL/CamTwistedAudio.driver")
        XCTAssertEqual(MicrophoneContract.deviceName, "CamTwisted Virtual Microphone output")
        XCTAssertNotEqual(MicrophoneContract.deviceUID, MicrophoneContract.feedUID)
        XCTAssertNotEqual(MicrophoneContract.deviceName, MicrophoneContract.feedName)
        XCTAssertEqual(MicrophoneContract.sampleRate, 48000)
        XCTAssertEqual(MicrophoneContract.channels, 2)
        XCTAssertEqual(MicrophoneContract.manufacturer, "CamTwisted")
    }

    func testInstallingReplacesTheDriverAndRestartsTheAudioServer() {
        XCTAssertEqual(
            MicrophoneInstallScript.install(from: "/Applications/It's Here.app/Contents/Resources/CamTwistedAudio.driver"),
            "/bin/rm -rf '/Library/Audio/Plug-Ins/HAL/CamTwistedAudio.driver'"
                + " && /bin/mkdir -p '/Library/Audio/Plug-Ins/HAL'"
                + " && /bin/cp -R '/Applications/It'\\''s Here.app/Contents/Resources/CamTwistedAudio.driver'"
                + " '/Library/Audio/Plug-Ins/HAL/CamTwistedAudio.driver'"
                + " && /usr/sbin/chown -R root:wheel '/Library/Audio/Plug-Ins/HAL/CamTwistedAudio.driver'"
                + " && (/usr/bin/killall coreaudiod || true)"
        )
        XCTAssertEqual(
            MicrophoneInstallScript.remove,
            "/bin/rm -rf '/Library/Audio/Plug-Ins/HAL/CamTwistedAudio.driver' && (/usr/bin/killall coreaudiod || true)"
        )
    }

    func testCommandsAreWrappedForTheSystemsPasswordPrompt() {
        XCTAssertEqual(
            MicrophoneInstallScript.appleScript(running: #"echo "a\b""#),
            #"do shell script "echo \"a\\b\"" with administrator privileges"#
        )
    }
}

final class LockedSceneTests: XCTestCase {
    func testALockedSceneIsNotRemovedAndACopyOfOneIsNotLocked() {
        var locked = StudioButton(name: "Kept", scene: SceneConfiguration())
        XCTAssertFalse(locked.isLocked)
        locked.isLocked = true
        let free = StudioButton(name: "Loose", scene: SceneConfiguration())
        var studio = StudioSettings(buttons: [locked, free])
        studio.removeScene(id: locked.id)
        studio.removeScene(id: free.id)
        studio.removeScene(id: UUID())
        XCTAssertEqual(studio.buttons.map(\.name), ["Kept"])
        XCTAssertFalse(locked.duplicated().isLocked, "a copy is there to be changed")
        studio.buttons[0].isLocked = false
        studio.removeScene(id: locked.id)
        XCTAssertEqual(studio.buttons, [])
    }
}

final class ScreenSoundTests: XCTestCase {
    func testAScreenAndAWindowAreSilentUntilTheirVolumeIsRaised() {
        let screen = ChainItem(content: .source(.display(DisplaySettings(displayID: 1))))
        var window = ChainItem(content: .source(.window(WindowSettings(titlePattern: "Notes"))))
        var scene = SceneConfiguration(items: [screen, window])
        XCTAssertEqual(SceneSound.levels(in: scene), [screen.id: 0, window.id: 0])
        XCTAssertFalse(SceneSound.isHeard(in: [scene]))
        window.volume = 0.6
        scene = SceneConfiguration(items: [screen, window])
        XCTAssertEqual(SceneSound.levels(in: scene), [screen.id: 0, window.id: 0.6])
        XCTAssertTrue(SceneSound.isHeard(in: [scene]))
    }

    func testOnlySourcesWithAVolumeOnTheirStepHaveAStartingOne() {
        XCTAssertEqual(SceneSound.startingVolume(for: .camera(deviceID: "cam")), 1)
        XCTAssertEqual(SceneSound.startingVolume(for: .microphone(deviceID: nil)), 1)
        XCTAssertEqual(SceneSound.startingVolume(for: .display(DisplaySettings(displayID: 1))), 0)
        XCTAssertEqual(SceneSound.startingVolume(for: .window(WindowSettings(titlePattern: ""))), 0)
        XCTAssertNil(SceneSound.startingVolume(for: .movie(MovieSettings())))
        XCTAssertNil(SceneSound.startingVolume(for: .colorBars))
    }
}

final class SourceFitTests: XCTestCase {
    func testASourceOfAnotherShapeFillsFitsOrStretches() {
        let canvas = CGSize(width: 160, height: 90)
        let tall = CGSize(width: 90, height: 90)
        XCTAssertEqual(AspectFitter.frame(for: tall, in: canvas, fit: .fill), CGRect(x: 0, y: -35, width: 160, height: 160))
        XCTAssertEqual(AspectFitter.frame(for: tall, in: canvas, fit: .fit), CGRect(x: 35, y: 0, width: 90, height: 90))
        XCTAssertEqual(AspectFitter.frame(for: tall, in: canvas, fit: .stretch), CGRect(x: 0, y: 0, width: 160, height: 90))
        XCTAssertEqual(SourceFit.allCases, [.fill, .fit, .stretch])
        let step = ChainItem(content: .source(.colorBars), fit: .fit)
        XCTAssertEqual(step.duplicated().fit, .fit, "a copy keeps how it fits")
        XCTAssertNil(ChainItem(content: .source(.colorBars)).fit)
    }
}
