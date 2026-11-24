import CamTwistCore
import Observation
import XCTest
@testable import CamTwistRendering
@testable import CamTwistControl

private final class WeakModel {
    weak var model: AppModel?
    init(_ model: AppModel?) { self.model = model }
}

/// A model wired to fakes, with every fake in reach.
@MainActor
final class Harness {
    let store = FakeKeyValueStore()
    let renderer = FakeRenderer()
    let library = FakeEffectLibrary()
    let choices = FakeSourceChoices()
    let pictureSizes = FakePictureSizes()
    let overlayMeasurer = FakeOverlayMeasurer()
    let installer = FakeInstaller()
    let monitor = FakeMonitor()
    let connection = FakeCameraConnection()
    let midi = FakeMIDI()
    let shortcuts = FakeShortcuts()
    let timers = FakeTimers()
    let scripts = FakeScripts()
    let snapshots = FakeSnapshotWriter()
    let fullScreen = FakeFullScreen()
    let webStream = FakeWebStream()
    let webMovie = FakeWebStream()
    let rtmp = FakeRTMP()
    let sound = FakeSound()
    let microphone = FakeMicrophone()
    let drawing = FakeDrawing()
    let microphoneInstaller = FakeMicrophoneInstaller()
    let airPlay = FakeAirPlay()
    let cast = FakeCast()
    let addresses = FakeAddresses()
    let thumbnailer = FakeEffectThumbnailer()
    let windows = FakeWindows()
    let filing = FakeSetupFiling()
    let files = FakeFiles()
    let fileChecker = FakeFileChecker()
    let processes = FakeProcesses()
    let sceneThumbnails = FakeSceneThumbnails()
    let recorder = FakeRecorder()
    let passwords = FakePasswords()
    let permissions = FakePermissions()
    let scheduler = FakeScheduler()
    var pictures = FakeDirectoryListing()
    let picturesFolder = URL(fileURLWithPath: "/pictures")

    /// How often the model looks again at what there is, in seconds.
    static let refreshInterval: TimeInterval = 2

    func makeModel() -> AppModel {
        AppModelAssembly.model(AppParts(
            picture: PictureParts(
                renderer: renderer,
                drawing: drawing,
                pictureSizes: pictureSizes,
                overlayMeasurer: overlayMeasurer,
                programMonitor: monitor,
                fullScreenOutput: fullScreen,
                sceneThumbnails: sceneThumbnails
            ),
            sources: SourceParts(
                effectLibrary: library,
                sourceChoices: choices,
                thumbnailer: thumbnailer,
                pictureCatalog: PictureCatalog(listing: pictures),
                picturesDirectory: picturesFolder,
                fileChecker: fileChecker,
                passwords: passwords
            ),
            outputs: OutputParts(
                installer: installer,
                cameraConnection: connection,
                processes: processes,
                webStream: webStream,
                webMovie: webMovie,
                rtmp: rtmp,
                airPlay: airPlay,
                cast: cast,
                addresses: addresses
            ),
            sound: SoundParts(sound: sound, microphone: microphone, microphoneInstaller: microphoneInstaller),
            capture: CaptureParts(recorder: recorder, snapshots: snapshots, folders: FakeFolders()),
            control: ControlParts(midi: midi, shortcuts: shortcuts, scripts: scripts),
            system: SystemParts(
                keyValueStore: store,
                windows: windows,
                filing: filing,
                files: files,
                permissions: permissions,
                scheduler: scheduler,
                timers: timers,
                refreshInterval: Self.refreshInterval,
                queue: ImmediateQueue()
            )
        ))
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    private let harness = Harness()

    // MARK: Launch

    func testEveryLaunchIsFreshAndOnlyTheGlobalPreferencesComeBack() {
        var globals = AppPreferences()
        globals.snapshotsFolder = "/snapshots"
        globals.rtmp.streamKey = "secret"
        globals.mirrorsPreview = true
        SavedState(keyValueStore: harness.store).save(globals: GlobalPreferences(globals))
        let model = harness.makeModel()
        XCTAssertEqual(model.studio.sceneOnAir?.scene, .initial, "what is on air is a scene from the start")
        XCTAssertEqual(model.preferences.snapshotsFolder, "/snapshots")
        XCTAssertEqual(model.preferences.rtmp.streamKey, "secret")
        XCTAssertFalse(model.preferences.mirrorsPreview, "the rest goes with a setup file")
        XCTAssertEqual(model.scene, .initial)
        XCTAssertTrue(model.startsAfresh)
        XCTAssertNil(model.documentURL)
    }

    // MARK: Locked scenes and window sizes

    func testALockedSceneCannotBeChangedOrRemovedUntilItIsUnlocked() {
        let model = harness.makeModel()
        model.start()
        let before = model.scene
        XCTAssertFalse(model.isEditedSceneLocked)

        // The scene on air, locked: nothing that changes it gets through.
        model.studio.buttons[0].isLocked = true
        XCTAssertTrue(model.isEditedSceneLocked)
        model.steps.add(.source(.colorBars))
        model.editedScene = SceneConfiguration()
        XCTAssertEqual(model.scene, before)

        // Another scene, locked: it cannot be changed or removed either.
        model.addScene()
        let other = try? XCTUnwrap(model.editedSceneID)
        let index = model.studio.buttons.count - 1
        let kept = model.studio.buttons[index].scene
        model.studio.buttons[index].isLocked = true
        XCTAssertTrue(model.isEditedSceneLocked)
        model.steps.add(.source(.colorBars))
        XCTAssertEqual(model.studio.buttons[index].scene, kept)
        model.removeScene(id: other ?? UUID())
        XCTAssertEqual(model.studio.buttons.count, index + 1, "locked, it stays")

        model.studio.buttons[index].isLocked = false
        model.steps.add(.source(.colorBars))
        XCTAssertNotEqual(model.studio.buttons[index].scene, kept, "unlocked, it changes again")
        model.removeScene(id: other ?? UUID())
        XCTAssertEqual(model.studio.buttons.count, index)
    }

    // MARK: Passwords

    func testAComputersVNCPasswordIsKeptUnderItsAddress() {
        let model = harness.makeModel()
        let computer = VNCSettings(address: "studio.local")
        XCTAssertNil(model.remoteScreens.password(for: computer))
        model.remoteScreens.setPassword("secret", for: computer)
        XCTAssertEqual(model.remoteScreens.password(for: computer), "secret")
        XCTAssertEqual(harness.passwords.kept, ["studio.local:5900": "secret"])
        XCTAssertNil(model.remoteScreens.password(for: VNCSettings(address: "studio.local:5901")), "another port is another computer")
        model.remoteScreens.setPassword("", for: computer)
        XCTAssertNil(model.remoteScreens.password(for: computer))
        XCTAssertEqual(sourceItem(.vnc(computer)).title, "Computer: studio.local")
        XCTAssertEqual(sourceItem(.vnc(VNCSettings())).title, "Another computer")
        XCTAssertTrue(SourceSpec.vnc(computer).canBeCutOut)
    }

    // MARK: Recording

    func testRecordingGoesToTheSnapshotsFolderWithAChapterForEachSceneOnAir() {
        let model = harness.makeModel()
        model.start()
        model.addScene()
        model.editScene(id: nil)
        let second = model.studio.buttons[1]
        XCTAssertEqual(model.capture.recordingStatus, .off)

        harness.recorder.status = .recording("Show.mov")
        model.capture.isRecording = true
        XCTAssertEqual(harness.recorder.applied.last?.isOn, true)
        XCTAssertEqual(harness.recorder.applied.last?.folder, model.capture.snapshotsDirectory)
        XCTAssertEqual(harness.recorder.applied.last?.sceneName, model.studio.buttons[0].name)
        XCTAssertEqual(model.capture.recordingStatus, .recording("Show.mov"))

        model.goLive(withScene: second.id)
        XCTAssertEqual(harness.recorder.marked.last, second.name, "a scene coming on air starts a chapter")

        harness.recorder.status = .failed("The disk is full.")
        model.refresh()
        XCTAssertEqual(model.capture.recordingStatus, .failed("The disk is full."))

        harness.recorder.status = .off
        model.capture.isRecording = false
        XCTAssertEqual(harness.recorder.applied.last?.isOn, false)
        XCTAssertEqual(model.capture.recordingStatus, .off)
    }

    // MARK: Scene pictures

    func testScenePicturesAreTakenInTurnWhileTheyAreWanted() {
        let model = harness.makeModel()
        model.start()
        model.addScene()
        model.editScene(id: nil)
        model.studio.buttons[1].scene = SceneConfiguration(items: [sourceItem(.colorBars)])
        let first = model.studio.buttons[0]
        let second = model.studio.buttons[1]
        model.refresh()
        XCTAssertTrue(harness.sceneThumbnails.requests.isEmpty, "none is taken until they are wanted")

        model.gallery.showsSceneThumbnails = true
        XCTAssertEqual(harness.sceneThumbnails.requests.map(\.scene), [first.scene])
        harness.sceneThumbnails.requests[0].completion(makeImage())
        XCTAssertNotNil(model.gallery.sceneThumbnails[first.id])
        XCTAssertEqual(harness.sceneThumbnails.requests.count, 2, "it carries on while a scene has none")
        XCTAssertEqual(harness.sceneThumbnails.requests[1].scene, second.scene)

        // A picture that could not be drawn leaves that scene without one,
        // and it is not asked for again straight away.
        harness.sceneThumbnails.requests[1].completion(nil)
        XCTAssertNil(model.gallery.sceneThumbnails[second.id])
        XCTAssertEqual(harness.sceneThumbnails.requests.count, 2)

        // Each time round, the one taken longest ago is taken again.
        model.refresh()
        XCTAssertEqual(harness.sceneThumbnails.requests.last?.scene, first.scene)
        harness.sceneThumbnails.requests[2].completion(makeImage())
        model.refresh()
        XCTAssertEqual(harness.sceneThumbnails.requests.last?.scene, second.scene)
        harness.sceneThumbnails.requests[3].completion(makeImage())
        XCTAssertNotNil(model.gallery.sceneThumbnails[second.id])

        // A scene that has changed jumps the queue.
        model.studio.buttons[1].scene = SceneConfiguration(items: [sourceItem(.testCard)])
        model.refresh()
        XCTAssertEqual(harness.sceneThumbnails.requests.last?.scene, model.studio.buttons[1].scene)

        // A scene that is removed takes its picture with it.
        harness.sceneThumbnails.requests[4].completion(makeImage())
        model.removeScene(id: second.id)
        model.refresh()
        XCTAssertNil(model.gallery.sceneThumbnails[second.id])

        // No longer wanted, no more are taken, and a late answer is still kept safely.
        let count = harness.sceneThumbnails.requests.count
        model.gallery.showsSceneThumbnails = false
        model.refresh()
        XCTAssertEqual(harness.sceneThumbnails.requests.count, count)
        harness.sceneThumbnails.isBusy = true
        model.gallery.showsSceneThumbnails = true
        XCTAssertEqual(harness.sceneThumbnails.requests.count, count, "busy, it waits for the next time round")
    }

    // MARK: Who is using the camera

    func testTheAppsWatchingTheCameraAreNamedOnceEach() {
        harness.processes.paths = [
            11: "/Applications/Zoom.app",
            12: "/Applications/Browser.app/Contents/Frameworks/Browser Helper.app",
            13: "/Applications/Browser.app",
            14: "/usr/libexec/somethingd",
        ]
        let model = harness.makeModel()
        model.refresh()
        XCTAssertEqual(model.outputs.camera.watchers, "", "nobody yet")

        harness.connection.watcherProcessIDs = [11]
        model.refresh()
        XCTAssertEqual(model.outputs.camera.watchers, "Zoom")

        // A helper counts as its app, a process that has gone is left out,
        // and one with no app of its own is too.
        harness.connection.watcherProcessIDs = [12, 13, 11, 14, 99]
        model.refresh()
        XCTAssertEqual(model.outputs.camera.watchers, "Browser and Zoom")

        XCTAssertEqual(CameraUse.sentence(listing: ["Zoom", "Browser", "Teams"]), "Zoom, Browser and Teams")
        XCTAssertNil(CameraUse.owningApp(ofBundleAt: "/usr/libexec/somethingd"))
    }

    // MARK: Drawing size

    func testThePictureIsDrawnInFullHDUntilAnOutputAsksFor4K() {
        let model = harness.makeModel()
        model.start()
        XCTAssertEqual(harness.drawing.sizes.last, .fullHD)

        model.preferences.webMovie.options.height = PictureHeight.ultraHD
        XCTAssertEqual(harness.drawing.sizes.last, .fullHD, "a stream that is off asks for nothing")
        model.preferences.webMovie.isOn = true
        XCTAssertEqual(harness.drawing.sizes.last, .ultraHD)
        model.preferences.webMovie.options.height = 720
        XCTAssertEqual(harness.drawing.sizes.last, .fullHD, "changing an output's size is followed")

        model.preferences.recording.height = PictureHeight.ultraHD
        XCTAssertEqual(harness.drawing.sizes.last, .fullHD)
        model.capture.isRecording = true
        XCTAssertEqual(harness.drawing.sizes.last, .ultraHD, "starting a 4K recording is followed")
        model.capture.isRecording = false
        XCTAssertEqual(harness.drawing.sizes.last, .fullHD, "and so is stopping it")
    }

    // MARK: The studio window

    func testTheStudioLinesAScenUpInThePreviewThenPutsItOnAir() {
        let model = harness.makeModel()
        model.start()
        let onAir = model.studio.onAirID
        model.addScene()
        model.editScene(id: nil)
        let other = model.studio.buttons[1]
        model.studio.buttons[1].scene = SceneConfiguration(items: [sourceItem(.colorBars)])
        XCTAssertNil(model.previewedSceneID)

        model.previewScene(id: other.id)
        XCTAssertEqual(model.previewedSceneID, other.id)
        XCTAssertEqual(model.studioPreview, model.studio.buttons[1].scene)

        // The scene on air has nothing to line up: asking for it clears the preview.
        model.previewScene(id: onAir ?? UUID())
        XCTAssertNil(model.previewedSceneID)
        model.previewScene(id: UUID())
        XCTAssertNil(model.studioPreview)

        model.previewScene(id: other.id)
        model.cutToPreview()
        XCTAssertEqual(model.studio.onAirID, other.id)
        XCTAssertEqual(model.scene, model.studio.buttons[1].scene)

        // Going live the scene's own way is a cut too, when that is its switch.
        let first = model.studio.buttons[0]
        model.previewScene(id: first.id)
        model.goLiveWithPreview()
        XCTAssertEqual(model.studio.onAirID, first.id)

        // A double click in the studio lines the scene up and takes it the studio's way.
        model.studio.choose(transition: StudioSettings.cutName)
        model.goLiveFromStudio(withScene: other.id)
        XCTAssertEqual(model.studio.onAirID, other.id)
        model.goLiveFromStudio(withScene: other.id)
        XCTAssertEqual(model.studio.onAirID, other.id, "the scene on air stays as it is")
    }

    // MARK: Missing sources

    func testAStepWhoseSourceIsNotThereSaysSo() {
        harness.choices.cameraList = [CameraChoice(id: "cam", name: "Camera")]
        harness.choices.displayList = [DisplayChoice(id: 1, name: "Screen")]
        harness.choices.microphoneList = [MicrophoneChoice(id: "mic", name: "Microphone")]
        harness.fileChecker.existing = ["/pictures/logo.png", "/clips/one.mov", "/slides"]
        let model = harness.makeModel()
        model.refresh()

        func problem(_ spec: SourceSpec) -> String? {
            model.choices.missingSourceProblem(with: ChainItem(content: .source(spec)))
        }
        // Everything that is there is fine.
        XCTAssertNil(problem(.camera(deviceID: "cam")))
        XCTAssertNil(problem(.display(DisplaySettings(displayID: 1))))
        XCTAssertNil(problem(.microphone(deviceID: "mic")))
        XCTAssertNil(problem(.microphone(deviceID: nil)), "the usual microphone is always there")
        XCTAssertNil(problem(.image(path: "/pictures/logo.png")))
        XCTAssertNil(problem(.image(path: "")), "no picture chosen yet is not one gone missing")
        XCTAssertNil(problem(.movie(MovieSettings(files: ["/clips/one.mov"]))))
        XCTAssertNil(problem(.slideShow(SlideShowSettings(paths: ["/slides"]))))
        XCTAssertNil(problem(.colorBars), "what needs nothing from outside is never missing")
        XCTAssertNil(model.choices.missingSourceProblem(with: ChainItem(content: .effect(name: "Blur", values: [:]))))

        // Everything that is not says what is wrong.
        XCTAssertEqual(problem(.camera(deviceID: "gone")), "This camera is not connected. Choose another.")
        XCTAssertEqual(problem(.display(DisplaySettings(displayID: 9))), "This screen is not connected. Choose another.")
        XCTAssertEqual(problem(.microphone(deviceID: "gone")), "This microphone is not connected. Choose another.")
        XCTAssertEqual(problem(.image(path: "/gone.png")), "This picture's file has moved or gone. Choose it again.")
        XCTAssertEqual(
            problem(.movie(MovieSettings(files: ["/clips/one.mov", "/gone.mov"]))),
            "A video's file has moved or gone. Choose it again."
        )
        XCTAssertEqual(
            problem(.slideShow(SlideShowSettings(paths: ["/gone"]))),
            "A picture or folder in this show has moved or gone. Choose it again."
        )

        // A scene knows when anything in it is missing, even in a branch.
        let fine = ChainItem(content: .source(.camera(deviceID: "cam")))
        let gone = ChainItem(content: .source(.camera(deviceID: "gone")))
        XCTAssertFalse(model.choices.isAnythingMissing(in: SceneConfiguration(items: [fine])))
        XCTAssertTrue(model.choices.isAnythingMissing(in: SceneConfiguration(items: [fine, gone])))
        XCTAssertTrue(model.choices.isAnythingMissing(in: SceneConfiguration(items: [
            ChainItem(content: .source(.colorBars), branch: [gone]),
        ])))
    }

    // MARK: Virtual microphone

    func testTheVirtualMicrophoneIsInstalledRemovedAndFedTheMix() {
        let model = harness.makeModel()
        model.start()
        XCTAssertEqual(model.outputs.microphone.state, .notInstalled)

        model.outputs.microphone.install()
        XCTAssertEqual(model.outputs.microphone.state, .installing)
        harness.microphoneInstaller.isInstalled = true
        harness.microphoneInstaller.installs[0](nil)
        XCTAssertEqual(model.outputs.microphone.state, .installed)

        // Switched on, it gets the mix of whatever on air makes sound.
        let camera = ChainItem(content: .source(.camera(deviceID: "cam")), volume: 0.5)
        model.scene = SceneConfiguration(items: [camera])
        model.preferences.sendsToMicrophone = true
        XCTAssertTrue(harness.microphone.isEnabled)
        XCTAssertEqual(harness.sound.levels.last, [camera.id: 0.5])

        model.outputs.microphone.remove()
        harness.microphoneInstaller.isInstalled = false
        harness.microphoneInstaller.removals[0]("could not")
        XCTAssertEqual(model.outputs.microphone.state, .failed("could not"))
        XCTAssertTrue(harness.microphone.isEnabled, "the output is put into effect again afterwards")
    }

    // MARK: Starting

    func testStartingWiresEverythingUpOnce() {
        let model = harness.makeModel()
        model.preferences.keepsWindowOnTop = true
        model.start()
        XCTAssertEqual(harness.renderer.startCount, 1)
        XCTAssertEqual(harness.renderer.programs.last, model.scene)
        XCTAssertEqual(harness.midi.startCount, 1)
        XCTAssertEqual(harness.windows.calls.last, true)
        XCTAssertEqual(harness.permissions.completions.count, 1)
        XCTAssertEqual(harness.scheduler.timers.map(\.interval), [Harness.refreshInterval])
        XCTAssertGreaterThan(harness.installer.refreshCount, 0)

        model.start()
        XCTAssertEqual(harness.renderer.startCount, 1)
        XCTAssertEqual(harness.scheduler.timers.count, 1)
    }

    func testGrantingCameraAccessRefreshesTheChoices() {
        let model = harness.makeModel()
        model.start()
        harness.choices.cameraList = [CameraChoice(id: "cam", name: "Camera")]
        harness.permissions.completions[0]()
        XCTAssertEqual(model.choices.cameras.map(\.id), ["cam"])
    }

    func testTheRefreshTimerRefreshes() {
        let model = harness.makeModel()
        model.start()
        harness.choices.displayList = [DisplayChoice(id: 1, name: "Main")]
        harness.scheduler.fire(0)
        XCTAssertEqual(model.choices.displays.count, 1)
    }

    // MARK: Refresh

    func testRefreshPublishesWhatIsThere() {
        harness.choices.cameraList = [CameraChoice(id: "cam", name: "Camera")]
        harness.choices.displayList = [DisplayChoice(id: 1, name: "Main")]
        harness.choices.windowList = [WindowChoice(title: "Doc", application: "Editor")]
        harness.choices.audioList = [AudioDeviceChoice(id: "out", name: "Speakers")]
        harness.pictures = FakeDirectoryListing(urls: [URL(fileURLWithPath: "/pictures/cat.png")])
        harness.library.listings = [EffectListing(name: "Blur", kind: .filter)]
        harness.connection.isConnected = true
        harness.thumbnailer.images = ["Blur": makeImage()]
        let model = harness.makeModel()
        model.refresh()
        XCTAssertEqual(model.choices.cameras.count, 1)
        XCTAssertEqual(model.choices.windows.count, 1)
        XCTAssertEqual(model.choices.audioOutputs.count, 1)
        XCTAssertEqual(model.choices.savedPictures.map(\.name), ["cat"])
        XCTAssertEqual(model.choices.effects.map(\.name), ["Blur"])
        XCTAssertTrue(model.outputs.camera.isSending)
        XCTAssertEqual(Array(model.choices.thumbnails.keys), ["Blur"])
        XCTAssertEqual(harness.installer.refreshCount, 1)
    }

    /// Counts the times something being watched has changed.
    private final class Changes: @unchecked Sendable {
        var count = 0
    }

    func testAnIdleRefreshChangesNothingTheWindowWatches() {
        let model = harness.makeModel()
        model.refresh()
        let changes = Changes()
        withObservationTracking {
            _ = (model.choices.cameras, model.choices.displays, model.choices.windows, model.choices.audioOutputs, model.choices.microphones)
            _ = (model.choices.savedPictures, model.choices.effects, model.outputs.camera.isSending, model.outputs.camera.watchers)
            _ = (model.outputs.microphone.state, model.outputs.streams.rtmpStatus, model.outputs.streams.webStreamStatus, model.outputs.streams.webMovieStatus)
        } onChange: {
            changes.count += 1
        }
        model.refresh()
        XCTAssertEqual(changes.count, 0)
    }

    func testRefreshUncoversAScreenThatHasGone() {
        harness.choices.displayList = [DisplayChoice(id: 2, name: "Side")]
        harness.fullScreen.connected = [2]
        let model = harness.makeModel()
        model.refresh()
        model.fullScreen.displayID = 2
        harness.choices.displayList = []
        model.refresh()
        XCTAssertNil(model.fullScreen.displayID)
        XCTAssertEqual(harness.fullScreen.hideCount, 1)
    }

    // MARK: Full screen

    func testFullScreenCoversADisplayAndUncoversIt() {
        harness.fullScreen.connected = [2]
        let model = harness.makeModel()
        model.fullScreen.displayID = 2
        XCTAssertEqual(model.fullScreen.displayID, 2)
        model.fullScreen.displayID = 2
        XCTAssertEqual(harness.fullScreen.shown, [2])
        model.fullScreen.displayID = nil
        XCTAssertEqual(harness.fullScreen.hideCount, 1)
    }

    func testFullScreenGivesUpOnADisplayThatIsNotConnected() {
        let model = harness.makeModel()
        model.fullScreen.displayID = 9
        XCTAssertNil(model.fullScreen.displayID)
    }

    func testTheOutputClosingItselfClearsTheChoice() {
        harness.fullScreen.connected = [2]
        let model = harness.makeModel()
        model.start()
        model.fullScreen.displayID = 2
        harness.fullScreen.onClose?()
        XCTAssertNil(model.fullScreen.displayID)
    }

    // MARK: Changes follow through

    func testChangesToTheSceneAreDrawn() {
        let model = harness.makeModel()
        let scene = SceneConfiguration(items: [sourceItem(.testCard)])
        model.scene = scene
        model.scene = scene
        XCTAssertEqual(harness.renderer.programs, [scene])
        model.studio.transitionName = "Cut"
        model.studioPreview = scene
        XCTAssertEqual(harness.renderer.previews, [scene])
    }

    func testPreferencesAreSavedWhereGlobalAndPutIntoEffect() {
        let model = harness.makeModel()
        model.preferences.mirrorsPreview = true
        XCTAssertTrue(harness.monitor.isMirrored)
        model.preferences.snapshotsFolder = "/snapshots"
        XCTAssertEqual(SavedState(keyValueStore: harness.store).load().snapshotsFolder, "/snapshots")
    }

    func testAirPlayPlaysTheHLSStreamWhichIsServedForItsSake() {
        let model = harness.makeModel()
        harness.addresses.hosts = ["192.0.2.7"]
        model.preferences.sendsToAirPlay = true
        XCTAssertEqual(harness.airPlay.applied.last?.isOn, true)
        XCTAssertEqual(harness.airPlay.applied.last?.address, "http://192.0.2.7:8090/stream.m3u8")
        XCTAssertEqual(harness.webStream.applied.last?.isOn, true, "the stream is served though not switched on itself")
        XCTAssertFalse(model.preferences.webStream.isOn)

        // This Mac's address can change; AirPlay is told again each time round.
        harness.addresses.hosts = ["192.0.2.9"]
        model.refresh()
        XCTAssertEqual(harness.airPlay.applied.last?.address, "http://192.0.2.9:8090/stream.m3u8")

        model.preferences.sendsToAirPlay = false
        XCTAssertEqual(harness.airPlay.applied.last?.isOn, false)
        XCTAssertEqual(harness.webStream.applied.last?.isOn, false)
    }

    func testCastPlaysTheHLSStreamOnTheDeviceChosen() {
        let model = harness.makeModel()
        harness.addresses.hosts = ["192.0.2.7"]
        model.preferences.sendsToCast = true
        XCTAssertEqual(harness.cast.applied.last?.isOn, true)
        XCTAssertEqual(harness.cast.applied.last?.address, "http://192.0.2.7:8090/stream.m3u8")
        XCTAssertNil(harness.cast.applied.last?.deviceName, "no device chosen yet")
        XCTAssertEqual(harness.webStream.applied.last?.isOn, true, "the stream is served though not switched on itself")

        model.preferences.castDeviceName = "Living room"
        XCTAssertEqual(harness.cast.applied.last?.deviceName, "Living room")

        model.preferences.sendsToCast = false
        XCTAssertEqual(harness.cast.applied.last?.isOn, false)
        XCTAssertEqual(harness.webStream.applied.last?.isOn, false)
    }

    func testTheWebStreamFollowsItsSettingsAndReportsWhereToWatch() {
        let model = harness.makeModel()
        XCTAssertEqual(model.outputs.streams.webStreamLinks.map(\.address), [
            "http://localhost:8090/stream.m3u8", "http://localhost:8090/",
        ])
        XCTAssertEqual(model.outputs.streams.webStreamLinks.map(\.id), ["HLS", "Page that plays it"])
        XCTAssertEqual(model.outputs.streams.webMovieLinks.map(\.address), ["http://localhost:8091/stream.mp4"])
        XCTAssertEqual(model.outputs.streams.webMovieLinks.map(\.id), ["MP4"])
        harness.addresses.hosts = ["192.0.2.7", "192.0.2.8"]
        model.preferences.webStream = WebStreamSettings(isOn: true, port: 9000)
        XCTAssertEqual(harness.webStream.applied.last, WebStreamSettings(isOn: true, port: 9000))
        XCTAssertEqual(model.outputs.streams.webStreamLinks.first?.address, "http://192.0.2.7:9000/stream.m3u8")

        XCTAssertEqual(model.outputs.streams.webStreamStatus, .off)
        harness.webStream.status = .failed("Port in use")
        harness.webMovie.status = .running
        model.refresh()
        XCTAssertEqual(model.outputs.streams.webStreamStatus, .failed("Port in use"))
        XCTAssertEqual(model.outputs.streams.webMovieStatus, .running)
        var movie = WebStreamSettings(isOn: true, port: 9100)
        movie.options.height = 360
        model.preferences.webMovie = movie
        XCTAssertEqual(harness.webMovie.applied.last, movie)
        XCTAssertEqual(model.outputs.streams.webMovieLinks.first?.address, "http://192.0.2.7:9100/stream.mp4")

        let stream = RTMPSettings(isOn: true, address: "rtmp://example.com/live", streamKey: "key")
        model.preferences.rtmp = stream
        XCTAssertEqual(harness.rtmp.applied.last, stream)
        XCTAssertEqual(model.outputs.streams.rtmpStatus, .idle)
        harness.rtmp.status = .live
        model.refresh()
        XCTAssertEqual(model.outputs.streams.rtmpStatus, .live)

        // The opening scene has nothing to be heard, so the streams go
        // out without sound and the mix is not run.
        XCTAssertEqual(harness.rtmp.sound.last, false)
        XCTAssertEqual(harness.sound.applied.last, SoundSettings(isOn: false))
        harness.choices.microphoneList = [MicrophoneChoice(id: "mic", name: "Desk microphone")]
        model.refresh()
        XCTAssertEqual(model.choices.microphones.map(\.name), ["Desk microphone"])

        // A source that makes sound comes on air: the streams carry it,
        // and it is heard at its own level.
        let camera = ChainItem(content: .source(.camera(deviceID: "cam")), volume: 0.7)
        model.scene = SceneConfiguration(items: [camera])
        XCTAssertEqual(harness.rtmp.sound.last, true)
        XCTAssertEqual(harness.webStream.sound.last, true)
        XCTAssertEqual(harness.webMovie.sound.last, true)
        XCTAssertEqual(harness.sound.levels.last, [camera.id: 0.7])
        // Turned right down, there is nothing to carry and the streams go silent.
        var quiet = camera
        quiet.volume = 0
        model.scene = SceneConfiguration(items: [quiet])
        XCTAssertEqual(harness.rtmp.sound.last, false)
        XCTAssertEqual(harness.sound.levels.last, [camera.id: 0])
    }

    func testScriptsInAStepSwitchedOnRun() {
        let model = harness.makeModel()
        model.scene = SceneConfiguration(items: [ChainItem(content: .script(source: "beep"))])
        XCTAssertEqual(harness.scripts.sources, ["beep"])
    }

    // MARK: Actions

    func testActionsAreCarriedOutOnTheMainActor() {
        let model = harness.makeModel()
        model.scene = SceneConfiguration(items: [sourceItem(.testCard)])
        model.performOnMain(.clearScene)
        XCTAssertEqual(model.scene, SceneConfiguration())
    }

    func testAFinishedTransitionLandsOnTheTarget() {
        let model = harness.makeModel()
        let target = SceneConfiguration(items: [sourceItem(.colorBars)])
        model.studioPreview = target
        model.start()
        model.performOnMain(.studioTransition)
        XCTAssertTrue(model.isTransitioning)
        harness.renderer.finishedHandler?(target)
        XCTAssertFalse(model.isTransitioning)
        XCTAssertEqual(model.scene, target)
    }

    func testAMIDINotePutsItsSceneOnAirAndIsRemembered() {
        let model = harness.makeModel()
        let look = StudioButton(name: "Wide", scene: SceneConfiguration(items: [sourceItem(.colorBars)]), midiNote: 40)
        model.studio.buttons.append(look)
        model.start()
        harness.midi.onNote?(40)
        XCTAssertEqual(model.studio.onAirID, look.id)
        XCTAssertEqual(model.scene, look.scene)
        XCTAssertEqual(model.midi.lastNote, 40)
        harness.midi.onNote?(41)
        XCTAssertEqual(model.studio.onAirID, look.id, "a note no scene owns changes nothing")
        XCTAssertEqual(model.midi.lastNote, 41)
    }

    func testTheNextMIDINoteBelongsToTheSceneWaitingForIt() {
        let model = harness.makeModel()
        model.start()
        let scene = StudioButton(name: "Wide", scene: SceneConfiguration())
        model.studio.buttons = [scene]
        model.midi.learningFor = scene.id
        harness.midi.onNote?(50)
        XCTAssertNil(model.midi.learningFor)
        XCTAssertEqual(model.studio.buttons.first?.midiNote, 50)
        XCTAssertNil(model.studioPreview, "the note that is learnt does not also play the scene")
    }

    func testCallbacksAfterTheModelIsGoneDoNothing() {
        var model: AppModel? = harness.makeModel()
        model?.start()
        let probe = WeakModel(model)
        model = nil
        XCTAssertNil(probe.model)
        harness.renderer.finishedHandler?(SceneConfiguration())
        harness.midi.onNote?(1)
        harness.fullScreen.onClose?()
        harness.permissions.completions[0]()
        harness.scheduler.fire(0)
        harness.installer.onChange?()
    }

    // MARK: Camera installation

    func testTheInstallStateComesFromTheInstallerAndItsChangesReachTheWindow() {
        harness.installer.state = .installing
        let model = harness.makeModel()
        XCTAssertEqual(model.outputs.camera.installState, .installing, "as it stood when the model was made")
        let changes = Changes()
        withObservationTracking {
            _ = model.outputs.camera.installState
        } onChange: {
            changes.count += 1
        }
        harness.installer.state = .installed
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(model.outputs.camera.installState, .installed)
        model.outputs.camera.install()
        XCTAssertEqual(harness.installer.installCount, 1)
        model.outputs.camera.remove()
        XCTAssertEqual(harness.installer.removeCount, 1)
    }

    // MARK: Looks

    func testWhatIsOnAirIsAlwaysOneOfTheScenes() {
        let model = harness.makeModel()
        XCTAssertEqual(model.studio.buttons.map(\.name), ["Scene 1"])
        XCTAssertEqual(model.studio.sceneOnAir?.scene, model.scene)
        XCTAssertTrue(model.isEditingOnAir)

        // Changing what is on air changes the scene on air.
        model.steps.add(.source(.testCard))
        XCTAssertEqual(model.studio.sceneOnAir?.scene, model.scene)
        XCTAssertEqual(model.editedScene, model.scene)
    }

    func testAnotherSceneCanBeChangedOffAirAndThenPutOnAir() {
        let model = harness.makeModel()
        let onAir = model.scene
        harness.choices.cameraList = []
        model.refresh()
        model.addScene()
        let added = model.studio.buttons[1]
        XCTAssertEqual(added.name, "Scene 2")
        XCTAssertEqual(model.editedSceneID, added.id)
        XCTAssertFalse(model.isEditingOnAir)
        XCTAssertEqual(model.studioPreview, added.scene, "it shows in the preview while it is changed")

        // Steps added now go into the new scene, not the one on air.
        model.steps.add(.source(.colorBars))
        XCTAssertEqual(model.scene, onAir)
        XCTAssertEqual(model.editedScene.items.count, added.scene.items.count + 1)
        XCTAssertEqual(model.studioPreview, model.editedScene)
        if let step = model.editedScene.items.first?.id {
            model.steps.reset(id: step)
        }

        // A copy is made beside it and opened; removing the copy returns to the one on air.
        model.duplicateScene(id: added.id)
        XCTAssertEqual(model.studio.buttons.map(\.name), ["Scene 1", "Scene 2", "Scene 2 copy"])
        let copy = model.studio.buttons[2].id
        XCTAssertEqual(model.editedSceneID, copy)
        model.removeScene(id: copy)
        XCTAssertNil(model.editedSceneID)
        XCTAssertNil(model.studioPreview)
        model.removeScene(id: model.studio.onAirID ?? UUID())
        XCTAssertEqual(model.studio.buttons.count, 2, "the scene on air stays")

        // Going live cuts to it, and it is then the one being changed.
        model.editScene(id: added.id)
        model.selectedStepID = UUID()
        model.editScene(id: added.id)
        XCTAssertNil(model.selectedStepID)
        XCTAssertEqual(harness.rtmp.marked, ["Scene 1"], "only the scene the app opened on so far")
        model.goLive(withScene: added.id)
        XCTAssertEqual(model.studio.onAirID, added.id)
        XCTAssertEqual(harness.webStream.marked, ["Scene 1", "Scene 2"], "the streams are told a new scene is on air")
        XCTAssertEqual(harness.webMovie.marked, ["Scene 1", "Scene 2"])
        XCTAssertEqual(harness.rtmp.marked, ["Scene 1", "Scene 2"])
        XCTAssertEqual(model.scene, model.studio.buttons[1].scene)
        XCTAssertTrue(model.isEditingOnAir)
        XCTAssertNil(model.studioPreview)
        XCTAssertEqual(model.studio.buttons[0].scene, onAir, "the scene that went off air keeps what it had")
    }

    func testASceneWithATransitionArrivesWhenTheFadeLands() {
        let model = harness.makeModel()
        model.start()
        model.addScene()
        let id = model.studio.buttons[1].id
        model.studio.buttons[1].switchName = "Dissolve"
        model.studio.buttons[1].switchTime = 2
        model.goLive(withScene: id)
        XCTAssertTrue(model.isTransitioning)
        XCTAssertEqual(harness.renderer.transitions.last?.name, "Dissolve")
        XCTAssertEqual(harness.renderer.transitions.last?.duration, 2)
        XCTAssertNotEqual(model.studio.onAirID, id, "not on air until the fade lands")
        harness.renderer.finishTransition()
        XCTAssertEqual(model.studio.onAirID, id)
        XCTAssertFalse(model.isTransitioning)
    }

    func testAFreshStartBeginsWithTheBestCameraOrATestCard() {
        harness.choices.cameraList = [
            CameraChoice(id: "small", name: "Small", pixels: 100), CameraChoice(id: "big", name: "Big", pixels: 900),
        ]
        let model = harness.makeModel()
        model.start()
        XCTAssertEqual(model.scene.items.map(\.content), [.source(.camera(deviceID: "big"))])
        XCTAssertEqual(model.studio.buttons.map(\.name), ["Scene 1"])

        XCTAssertEqual(model.steps.newCameraSource, .camera(deviceID: "big"))
        XCTAssertEqual(model.steps.newImageSource, .image(path: ""), "nothing chosen yet")
        harness.choices.cameraList = []
        model.refresh()
        XCTAssertNil(model.steps.newCameraSource)

        let builder = StepBuilder(parameters: EffectParameters(library: harness.library))
        XCTAssertEqual(builder.startingScene(cameras: []).items.map(\.content), [.source(.testCard)])
        XCTAssertNil(builder.startingScene(cameras: []).items.first?.cutout)
        // A camera starts as it is, with its background left in.
        let small = CameraChoice(id: "small", name: "Small", pixels: 100)
        let large = CameraChoice(id: "large", name: "Large", pixels: 900)
        let opening = builder.startingScene(cameras: [small, large]).items
        XCTAssertEqual(opening.map(\.content), [.source(.camera(deviceID: "large"))])
        XCTAssertNil(opening.first?.cutout)
    }

    func testTheAppOpensAsNewWithTheFirstCameraOnAir() {
        harness.choices.cameraList = [CameraChoice(id: "cam", name: "Cam")]
        let model = harness.makeModel()
        model.start()
        XCTAssertTrue(model.startsAfresh)
        XCTAssertEqual(model.scene.items.map(\.content), [.source(.camera(deviceID: "cam"))])
        XCTAssertEqual(model.studio.buttons.map(\.name), ["Scene 1"])
    }

    func testASetupOpenedBeforeTheAppStartsIsNotReplacedByAFreshScene() throws {
        let model = harness.makeModel()
        model.scene = SceneConfiguration(items: [sourceItem(.testCard)])
        let url = URL(fileURLWithPath: "/setups/show.camtwisted")
        model.setups.save(to: url)
        let other = harness.makeModel()
        other.setups.open(url)
        other.start()
        XCTAssertFalse(other.startsAfresh)
        XCTAssertEqual(other.scene.items.map(\.content), [.source(.testCard)])
    }

    // MARK: Effects, folders and steps

    func testEffectListsAndControlsComeFromTheLibrary() {
        harness.library.listings = [EffectListing(name: "Blur", kind: .filter), EffectListing(name: "Wipe", kind: .transition)]
        harness.library.controls["Blur"] = [numberControl("amount", name: "Amount")]
        let model = harness.makeModel()
        model.refresh()
        XCTAssertEqual(model.choices.transitionNames, [StudioSettings.cutName, DissolveTransition.name, "Wipe"])
        XCTAssertEqual(model.choices.effects(of: .filter).map(\.name), ["Blur"])
        XCTAssertEqual(model.choices.parameters(forEffectNamed: "Blur").count, 1)
    }

    func testFoldersAreOpenedThroughTheFileRevealer() {
        let model = harness.makeModel()
        model.choices.openPicturesFolder()
        model.choices.openEffectsFolder()
        XCTAssertEqual(harness.files.opened, [harness.picturesFolder, harness.library.directory])
    }

    func testAddingAStepSelectsItAndOpensItsSettings() {
        harness.library.controls["Frosted Glass"] = [numberControl("Shadow_Offset", name: "Shadow Offset", value: 5)]
        let model = harness.makeModel()
        model.steps.add(.effect(name: "Frosted Glass", values: [:]))
        let item = model.scene.items.last
        XCTAssertEqual(model.selectedStepID, item?.id)
        XCTAssertEqual(model.expandedSteps, Set([item?.id].compactMap { $0 }))
        guard case .effect(_, let values) = item?.content else { return XCTFail("no effect") }
        XCTAssertFalse(values.isEmpty)
    }

    func testAddingAStepGoesIntoTheChosenBranchWhileItsSourceExists() {
        let model = harness.makeModel()
        let source = sourceItem(.testCard)
        model.scene = SceneConfiguration(items: [source])
        model.branchTarget = source.id
        model.steps.add(.effect(name: "Fx", values: ["a": .number(1)]))
        XCTAssertEqual(model.scene.item(id: source.id)?.branch?.count, 1)
        XCTAssertEqual(model.branchTarget, source.id)
    }

    func testAddingAStepForgetsABranchWhoseSourceIsGone() {
        let model = harness.makeModel()
        model.branchTarget = UUID()
        model.steps.add(.source(.colorBars))
        XCTAssertNil(model.branchTarget)
        XCTAssertEqual(model.scene.items.count, 2)
    }

    func testTextAndShapesStartPlacedInTheMiddleAndOtherSourcesFillThePicture() {
        let model = harness.makeModel()
        model.steps.add(.source(.text(TextSettings())))
        model.steps.add(.source(.shape(ShapeSettings())))
        model.steps.add(.source(.colorBars))
        func placement(of content: ChainItem.Content) -> PictureInPictureSettings? {
            model.scene.items.first { $0.content == content }?.pictureInPicture
        }
        let middle = CGPoint(x: 0.5, y: 0.5)
        XCTAssertEqual(placement(of: .source(.text(TextSettings()))), PictureInPictureSettings(center: middle, scale: 1))
        XCTAssertEqual(placement(of: .source(.shape(ShapeSettings()))), PictureInPictureSettings(center: middle))
        XCTAssertNil(placement(of: .source(.colorBars)))
    }

    func testResettingAStepKeepsWhatItShowsAndForgetsTheRest() {
        harness.library.controls["Fx"] = [numberControl("Amount", name: "Amount", value: 0)]
        let model = harness.makeModel()
        let inner = ChainItem(content: .source(.colorBars))
        var tinted = SourceAdjustments()
        tinted.brightness = 0.5
        let text = ChainItem(
            isEnabled: false,
            content: .source(.text(TextSettings(text: "On air", fontName: "Menlo", fontSize: 40))),
            pictureInPicture: PictureInPictureSettings(center: CGPoint(x: 0.1, y: 0.1), scale: 0.2, rotation: 30),
            branch: [inner],
            adjustments: tinted,
            animations: [SourceAnimation(property: .rotation, from: 0, to: 90)]
        )
        let shape = ChainItem(content: .source(.shape(ShapeSettings(kind: .star, opacity: 0.2))))
        let effect = ChainItem(content: .effect(name: "Fx", values: ["Amount": .number(9)]))
        let script = ChainItem(content: .script(source: "beep"))
        let bars = ChainItem(
            content: .source(.colorBars), pictureInPicture: PictureInPictureSettings(center: .zero)
        )
        model.scene = SceneConfiguration(items: [text, shape, effect, script, bars])
        for item in model.scene.items { model.steps.reset(id: item.id) }

        XCTAssertEqual(model.scene.item(id: text.id), ChainItem(
            id: text.id, isEnabled: false, content: .source(.text(TextSettings(text: "On air"))),
            pictureInPicture: PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5), scale: 1), branch: [inner]
        ))
        XCTAssertEqual(model.scene.item(id: shape.id)?.content, .source(.shape(ShapeSettings(kind: .star))))
        XCTAssertEqual(model.scene.item(id: effect.id)?.content, model.scene.item(id: effect.id).map { _ in
            StepBuilder(parameters: EffectParameters(library: harness.library))
                .item(for: .effect(name: "Fx", values: [:])).content
        })
        XCTAssertNotEqual(model.scene.item(id: effect.id)?.content, effect.content)
        XCTAssertEqual(model.scene.item(id: script.id), script)
        XCTAssertEqual(model.scene.item(id: bars.id), ChainItem(id: bars.id, content: .source(.colorBars)))
    }

    func testDroppedImagesAndVideosJoinTheSceneAndOtherFilesAreIgnored() {
        let model = harness.makeModel()
        let before = model.scene.items.count
        model.steps.addFiles(["/clips/intro.MOV", "/notes/readme.txt", "/pictures/logo.png"])
        XCTAssertEqual(model.scene.items.count, before + 2)
        XCTAssertTrue(model.scene.items.contains { $0.content == .source(.image(path: "/pictures/logo.png")) })
        XCTAssertTrue(model.scene.items.contains {
            $0.content == .source(.movie(MovieSettings(files: ["/clips/intro.MOV"])))
        })
    }

    func testAStepCanBeAddedBeforeAnother() {
        let model = harness.makeModel()
        let first = model.scene.items[0].id
        model.steps.add(.source(.testCard), before: first, inBranchOf: nil)
        XCTAssertEqual(model.scene.items.last?.id, first)
    }

    // MARK: Dragging

    func testDeleteRemovesTheSelectedStepUnlessTheSceneIsLocked() {
        let model = harness.makeModel()
        let card = sourceItem(.testCard)
        model.scene = SceneConfiguration(items: [card])
        model.picture.removeSelectedStep()
        XCTAssertNotNil(model.scene.item(id: card.id), "nothing is selected")
        model.selectedStepID = card.id
        model.studio.buttons[0].isLocked = true
        model.picture.removeSelectedStep()
        XCTAssertNotNil(model.scene.item(id: card.id), "a locked scene keeps its steps")
        XCTAssertEqual(model.selectedStepID, card.id)
        model.studio.buttons[0].isLocked = false
        model.picture.removeSelectedStep()
        XCTAssertNil(model.scene.item(id: card.id))
        XCTAssertNil(model.selectedStepID)
    }

    func testDraggingAndDrawingGoThroughTheModel() {
        let model = harness.makeModel()
        let pen = sourceItem(.telestrator(TelestratorSettings()))
        let small = sourceItem(.testCard, pip: PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5)))
        model.scene = SceneConfiguration(items: [pen, small])
        XCTAssertEqual(model.picture.activeTelestrator, pen.id)
        model.picture.addStroke([CGPoint.zero], to: pen.id)
        model.selectedStepID = small.id
        XCTAssertEqual(model.picture.dragTarget, .picture(small.id))
        XCTAssertEqual(model.picture.dragHint, "Drag Test card to move it, a corner to resize it, the knob to turn it")
        model.picture.drag(by: CGPoint(x: 0.1, y: 0))
        XCTAssertNotEqual(model.scene.item(id: small.id)?.pictureInPicture?.center, CGPoint(x: 0.5, y: 0.5))
        XCTAssertNil(model.picture.selectionOutline, "the source has no picture yet")
        harness.pictureSizes.sizes[small.id] = CGSize(width: 400, height: 400)
        XCTAssertEqual(model.picture.selectionOutline?.center.y, 0.5)
        let before = model.scene.item(id: small.id)?.pictureInPicture?.scale ?? 0
        model.picture.drag(from: CGPoint(x: 0.7, y: 0.5), to: CGPoint(x: 0.8, y: 0.5), mode: .resize)
        XCTAssertGreaterThan(model.scene.item(id: small.id)?.pictureInPicture?.scale ?? 0, before)
    }

    func testADragOnThePictureMovesTheStepInFocus() {
        let model = harness.makeModel()
        let small = sourceItem(.testCard, pip: PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5)))
        model.scene = SceneConfiguration(items: [small])
        model.selectedStepID = small.id
        let size = CGSize(width: 200, height: 100)
        let press = CGPoint(x: 100, y: 50)
        model.pictureDrag.changed(to: press, start: press, in: size)
        model.pictureDrag.changed(to: CGPoint(x: 120, y: 50), start: press, in: size)
        model.pictureDrag.ended(in: size)
        XCTAssertEqual(model.scene.item(id: small.id)?.pictureInPicture?.center.x ?? 0, 0.6, accuracy: 0.0001)
    }

    // MARK: Setups

    func testASetupFileKeepsEverySceneAndTheWindowAndOpensAgain() throws {
        let model = harness.makeModel()
        harness.windows.contentSize = CGSize(width: 1200, height: 700)
        model.scene = SceneConfiguration(items: [sourceItem(.testCard), effectItem("Fx")])
        model.addScene()
        model.preferences.mirrorsPreview = true
        model.preferences.rtmp.address = "rtmp://example.com/live"
        model.preferences.rtmp.streamKey = "secret"
        model.preferences.snapshotsFolder = "/snapshots"
        let kept = model.studio
        let url = URL(fileURLWithPath: "/setups/show.camtwisted")

        model.setups.save(to: url)
        XCTAssertEqual(model.documentURL, url)
        XCTAssertNil(model.setupProblem)
        let text = String(decoding: try XCTUnwrap(harness.filing.files[url]), as: UTF8.self)
        XCTAssertFalse(text.contains("secret"), "the stream key stays out of the file")
        XCTAssertFalse(text.contains("/snapshots"), "so does the snapshot folder")
        XCTAssertTrue(text.contains("rtmp://example.com/live"))

        let reopened = harness.makeModel()
        reopened.preferences.snapshotsFolder = "/elsewhere"
        reopened.preferences.rtmp.streamKey = "mine"
        reopened.setups.open(url)
        XCTAssertEqual(reopened.studio, kept)
        XCTAssertEqual(reopened.scene.items.count, 2)
        XCTAssertEqual(reopened.documentURL, url)
        XCTAssertFalse(reopened.startsAfresh)
        XCTAssertTrue(reopened.preferences.mirrorsPreview)
        XCTAssertTrue(harness.monitor.isMirrored)
        XCTAssertEqual(reopened.preferences.rtmp.address, "rtmp://example.com/live")
        XCTAssertEqual(reopened.preferences.snapshotsFolder, "/elsewhere", "this Mac's own choices stay")
        XCTAssertEqual(reopened.preferences.rtmp.streamKey, "mine")
        XCTAssertEqual(harness.windows.resizes, [CGSize(width: 1200, height: 700)])
    }

    func testSavingWithNoFileYetSaysSoAndSavingOverTheFileNeedsNoPlace() {
        let model = harness.makeModel()
        XCTAssertFalse(model.setups.saveToCurrentFile())
        XCTAssertTrue(harness.filing.files.isEmpty)
        let url = URL(fileURLWithPath: "/setups/show.camtwisted")
        model.setups.save(to: url)
        harness.filing.files[url] = nil
        XCTAssertTrue(model.setups.saveToCurrentFile())
        XCTAssertNotNil(harness.filing.files[url])
    }

    func testANewSetupStartsAgainButKeepsWhatStaysWithThisMac() {
        harness.choices.cameraList = [CameraChoice(id: "cam", name: "Cam")]
        let model = harness.makeModel()
        model.start()
        model.setups.open(URL(fileURLWithPath: "/missing.camtwisted"))
        model.preferences.mirrorsPreview = true
        model.preferences.snapshotsFolder = "/snapshots"
        model.addScene()
        model.selectedStepID = nil

        model.setups.startNew()
        XCTAssertNil(model.setupProblem)
        XCTAssertNil(model.documentURL)
        XCTAssertTrue(model.startsAfresh)
        XCTAssertEqual(model.studio.buttons.count, 1)
        XCTAssertEqual(model.scene.items.map(\.content), [.source(.camera(deviceID: "cam"))])
        XCTAssertNotNil(model.selectedStepID)
        XCTAssertFalse(model.preferences.mirrorsPreview)
        XCTAssertEqual(model.preferences.snapshotsFolder, "/snapshots")
        XCTAssertEqual(harness.windows.resetCount, 1)
    }

    func testWithAutosaveOnEveryChangeIsSavedAndOpeningAnotherSetupLeavesTheOldFileAlone() throws {
        let model = harness.makeModel()
        model.start()
        model.preferences.autosaves = true
        let first = URL(fileURLWithPath: "/setups/first.camtwisted")
        let second = URL(fileURLWithPath: "/setups/second.camtwisted")
        model.setups.save(to: first)
        let firstAsSaved = try XCTUnwrap(harness.filing.files[first])

        model.addScene()
        let firstAfterChange = try XCTUnwrap(harness.filing.files[first])
        XCTAssertNotEqual(firstAfterChange, firstAsSaved, "the new scene went straight into the file")

        let other = StudioButton(name: "Other", scene: SceneConfiguration(items: [sourceItem(.testCard)]))
        let made = SetupDocument(studio: StudioSettings(buttons: [other]), preferences: AppPreferences(), windowSize: nil)
        harness.filing.files[second] = try SetupDocumentCoder().encode(made)
        model.setups.open(second)
        XCTAssertEqual(harness.filing.files[first], firstAfterChange, "opening never writes over the old file")
        XCTAssertFalse(model.setups.hasUnsavedChanges)
    }

    func testAFileThatCannotBeOpenedLeavesTheSetupAloneAndSaysWhy() {
        let model = harness.makeModel()
        let before = model.scene
        model.setups.open(URL(fileURLWithPath: "/missing.camtwisted"))
        XCTAssertNotNil(model.setupProblem)
        XCTAssertEqual(model.scene, before)
        XCTAssertNil(model.documentURL)
    }

    func testAFileThatCannotBeSavedSaysWhyAndTheNextSuccessClearsIt() {
        let model = harness.makeModel()
        let url = URL(fileURLWithPath: "/setups/show.camtwisted")
        harness.filing.fails = true
        model.setups.save(to: url)
        XCTAssertNotNil(model.setupProblem)
        XCTAssertNil(model.documentURL)
        harness.filing.fails = false
        model.setups.save(to: url)
        XCTAssertNil(model.setupProblem)
        XCTAssertEqual(model.documentURL, url)
    }

    // MARK: Snapshots

    func testSnapshotsAreWrittenToTheChosenFolderAndShown() {
        let model = harness.makeModel()
        XCTAssertEqual(model.capture.snapshotsDirectory, FakeFolders().desktopDirectory)
        XCTAssertNil(model.capture.writeSnapshot())
        harness.renderer.latestProgramFrame = makePixelBuffer()
        harness.snapshots.result = URL(fileURLWithPath: "/desktop/a.png")
        model.capture.takeSnapshot()
        XCTAssertEqual(harness.files.revealed, [URL(fileURLWithPath: "/desktop/a.png")])
        XCTAssertEqual(model.capture.writeSnapshot(), harness.snapshots.result)
    }

    // MARK: Scripting

    func testScriptsFindSourcesByNameAndSetEffectControls() {
        harness.library.controls["Fx"] = [numberControl("amount", name: "Amount")]
        harness.choices.cameraList = [CameraChoice(id: "cam", name: "Camera")]
        let model = harness.makeModel()
        model.refresh()
        XCTAssertEqual(model.scripts.sources?.sourceSpec(named: "Webcam"), .camera(deviceID: "cam"))
        model.steps.add(.effect(name: "Fx", values: [:]))
        let id = model.scene.items.last?.id ?? UUID()
        XCTAssertEqual(model.scripts.actions?.setEffectProperty("amount", to: "2", ofStep: id), true)
        XCTAssertEqual(model.scripts.actions?.setEffectProperty("nope", to: "2", ofStep: id), false)
        // The door is the model's own, kept for as long as the model is.
        XCTAssertTrue(model.scripts.actions === model.scripts.actions)
        model.scripts.actions?.addStep(.source(.colorBars))
        XCTAssertEqual(model.scene.items.last?.content, .source(.colorBars))
        model.scripts.actions?.performOnMain(.clearScene)
        XCTAssertEqual(model.scripts.scenes?.scene, SceneConfiguration())
        harness.renderer.latestProgramFrame = makePixelBuffer()
        harness.snapshots.result = URL(fileURLWithPath: "/desktop/a.png")
        XCTAssertEqual(model.scripts.snapshots?.writeSnapshot(), harness.snapshots.result)
    }
}
