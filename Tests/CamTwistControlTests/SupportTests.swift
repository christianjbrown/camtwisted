import CamTwistCore
import XCTest
@testable import CamTwistRendering
@testable import CamTwistControl

final class ScriptingSupportTests: XCTestCase {
    private let library = FakeEffectLibrary()
    private lazy var scripting = ScriptingSupport(parameters: EffectParameters(library: library))
    private let camera = CameraChoice(id: "cam", name: "Camera")
    private let display = DisplayChoice(id: 7, name: "Main")

    private func spec(_ name: String, withDevices: Bool = true) -> SourceSpec? {
        scripting.sourceSpec(
            named: name,
            cameras: withDevices ? [camera] : [],
            displays: withDevices ? [display] : []
        )
    }

    func testNamesFindTheMatchingSourceWhateverTheCase() {
        XCTAssertEqual(spec("camera"), .camera(deviceID: "cam"))
        XCTAssertEqual(spec("SCREEN"), .display(DisplaySettings(displayID: 7)))
        XCTAssertEqual(spec("Video"), .movie(MovieSettings()))
        XCTAssertEqual(spec("Movie"), .movie(MovieSettings()), "another name still works")
        XCTAssertEqual(spec("Slide show"), .slideShow(SlideShowSettings()))
        XCTAssertEqual(spec("Website"), .website(url: ""))
        XCTAssertEqual(spec("Stream"), .stream(StreamSettings()))
        XCTAssertEqual(spec("Microphone"), .microphone(deviceID: nil))
        XCTAssertEqual(spec("Webcam"), .camera(deviceID: "cam"), "other names still work")
        XCTAssertEqual(spec("Desktop"), .display(DisplaySettings(displayID: 7)))
        XCTAssertEqual(spec("Telestrator"), .telestrator(TelestratorSettings()))
        XCTAssertEqual(spec("Test card"), .testCard)
        XCTAssertEqual(spec("Image"), .image(path: ""))
        XCTAssertEqual(spec("Text: Text"), .text(TextSettings()))
        XCTAssertEqual(spec("Shape: Rectangle"), .shape(ShapeSettings()))
        XCTAssertEqual(spec("Colour bars"), .colorBars)
        XCTAssertNil(spec("Nonsense"))
    }

    func testSourcesThatNeedADeviceAreMissingWhenThereIsNone() {
        XCTAssertNil(spec("Webcam", withDevices: false))
        XCTAssertNil(spec("Desktop", withDevices: false))
    }

    // MARK: Setting an effect control from text

    private func scene(with controls: [EffectParameter]) -> (SceneConfiguration, UUID) {
        library.controls["Fx"] = controls
        let item = effectItem("Fx")
        return (SceneConfiguration(items: [item]), item.id)
    }

    private func value(of key: String, in scene: SceneConfiguration, id: UUID) -> EffectValue? {
        guard case .effect(_, let values) = scene.item(id: id)?.content else { return nil }
        return values[key]
    }

    func testANumberIsSetFromTextByKeyOrByDisplayedName() {
        var (scene, id) = scene(with: [numberControl("amount", name: "Amount Shown")])
        XCTAssertTrue(scripting.setEffectProperty("AMOUNT", to: "3.5", ofStep: id, in: &scene))
        XCTAssertEqual(value(of: "amount", in: scene, id: id), .number(3.5))
        XCTAssertTrue(scripting.setEffectProperty("amount shown", to: "4", ofStep: id, in: &scene))
        XCTAssertEqual(value(of: "amount", in: scene, id: id), .number(4))
    }

    func testTextThatIsNotANumberIsRefused() {
        var (scene, id) = scene(with: [numberControl("amount", name: "Amount")])
        XCTAssertFalse(scripting.setEffectProperty("amount", to: "lots", ofStep: id, in: &scene))
    }

    func testASwitchAndAStringAreSetFromText() {
        var (scene, id) = scene(with: [
            EffectParameter(key: "on", displayName: "On", kind: .boolean, defaultValue: .boolean(false)),
            EffectParameter(key: "label", displayName: "Label", kind: .string, defaultValue: .string("")),
        ])
        XCTAssertTrue(scripting.setEffectProperty("on", to: "yes", ofStep: id, in: &scene))
        XCTAssertEqual(value(of: "on", in: scene, id: id), .boolean(true))
        XCTAssertTrue(scripting.setEffectProperty("label", to: "Hello", ofStep: id, in: &scene))
        XCTAssertEqual(value(of: "label", in: scene, id: id), .string("Hello"))
    }

    func testAColourCannotBeSetFromText() {
        var (scene, id) = scene(with: [
            EffectParameter(
                key: "tint", displayName: "Tint", kind: .color,
                defaultValue: .color(red: 0, green: 0, blue: 0, alpha: 1)
            ),
        ])
        XCTAssertFalse(scripting.setEffectProperty("tint", to: "red", ofStep: id, in: &scene))
    }

    func testAnUnknownControlOrAStepThatIsNotAnEffectIsRefused() {
        var (scene, id) = scene(with: [numberControl("amount", name: "Amount")])
        XCTAssertFalse(scripting.setEffectProperty("speed", to: "1", ofStep: id, in: &scene))
        XCTAssertFalse(scripting.setEffectProperty("amount", to: "1", ofStep: UUID(), in: &scene))
    }
}

final class StepBuilderTests: XCTestCase {
    private let library = FakeEffectLibrary()
    private lazy var builder = StepBuilder(parameters: EffectParameters(library: library))

    func testASourceKeepsItsContent() {
        XCTAssertEqual(builder.item(for: .source(.testCard)).content, .source(.testCard))
    }

    func testAnEffectWithValuesKeepsThem() {
        let content = ChainItem.Content.effect(name: "Fx", values: ["a": .number(1)])
        XCTAssertEqual(builder.item(for: content).content, content)
        XCTAssertTrue(library.parameterRequests.isEmpty)
    }

    func testAFreshEffectStartsWithItsStartingValues() {
        library.controls["Fx"] = [numberControl("amount", name: "Amount", value: 4)]
        let item = builder.item(for: .effect(name: "Fx", values: [:]))
        let expected = EffectStartingValues.values(for: library.controls["Fx"] ?? [])
        XCTAssertEqual(item.content, .effect(name: "Fx", values: expected))
    }

    func testTheBranchTargetIsKeptWhileItsSourceIsInTheScene() {
        let source = sourceItem(.testCard)
        let scene = SceneConfiguration(items: [source])
        XCTAssertEqual(builder.branchTarget(source.id, in: scene), source.id)
        XCTAssertNil(builder.branchTarget(UUID(), in: scene))
        XCTAssertNil(builder.branchTarget(nil, in: scene))
    }
}

@MainActor
final class PreferenceApplierTests: XCTestCase {
    func testPreferencesReachTheMonitorAndTheWindows() {
        let monitor = FakeMonitor()
        let windows = FakeWindows()
        let stream = FakeWebStream()
        let movie = FakeWebStream()
        let camera = FakeCameraConnection()
        let rtmp = FakeRTMP()
        let sound = FakeSound()
        let microphone = FakeMicrophone()
        let drawing = FakeDrawing()
        let applier = PreferenceApplier(
            monitor: monitor, windows: windows, webStream: stream, webMovie: movie, camera: camera,
            rtmp: rtmp,
            sound: sound,
            microphone: microphone,
            drawing: drawing,
            drawingSizes: DrawingSizeRule()
        )
        var preferences = AppPreferences()
        preferences.mirrorsPreview = true
        preferences.keepsWindowOnTop = true
        preferences.sendsToCamera = false
        applier.apply(preferences, isHeard: true, isRecording: false)
        XCTAssertFalse(camera.isEnabled)
        XCTAssertEqual(stream.sound, [true], "the streams carry sound when there is any to carry")
        applier.apply(AppPreferences(), isHeard: false, isRecording: false)
        XCTAssertEqual(stream.sound, [true, false], "with nothing in any scene to be heard, the streams have no sound")
        XCTAssertFalse(monitor.isMirrored)
        XCTAssertEqual(windows.calls, [true, false])
        XCTAssertEqual(stream.applied.count, 2)
        XCTAssertEqual(Set(movie.applied.map(\.port)), [WebStreamSettings.defaultMoviePort])
        XCTAssertTrue(camera.isEnabled, "the camera is on unless switched off")
        XCTAssertEqual(rtmp.applied.count, 2)
        XCTAssertEqual(rtmp.sound, [true, false])
        XCTAssertEqual(sound.applied.map(\.isOn), [true, false], "the mix runs only while something is heard")
        XCTAssertEqual(microphone.changes, [false, false], "the microphone is off unless switched on")

        XCTAssertEqual(drawing.sizes, [.fullHD, .fullHD])
        var withMicrophone = AppPreferences()
        withMicrophone.sendsToMicrophone = true
        applier.apply(withMicrophone, isHeard: true, isRecording: false)
        XCTAssertTrue(microphone.isEnabled)
    }

    func testThePictureIsDrawnWithTheDetailTheOutputsAskFor() {
        let drawing = FakeDrawing()
        let applier = PreferenceApplier(
            monitor: FakeMonitor(), windows: FakeWindows(), webStream: FakeWebStream(), webMovie: FakeWebStream(),
            camera: FakeCameraConnection(), rtmp: FakeRTMP(), sound: FakeSound(), microphone: FakeMicrophone(),
            drawing: drawing, drawingSizes: DrawingSizeRule()
        )
        var preferences = AppPreferences()
        preferences.webStream.options.height = PictureHeight.ultraHD
        preferences.webMovie.options.height = PictureHeight.ultraHD
        preferences.rtmp.options.height = PictureHeight.ultraHD
        preferences.recording.height = PictureHeight.ultraHD
        applier.apply(preferences, isHeard: false, isRecording: false)
        XCTAssertEqual(drawing.sizes.last, .fullHD, "outputs that are off ask for nothing")

        applier.apply(preferences, isHeard: false, isRecording: true)
        XCTAssertEqual(drawing.sizes.last, .ultraHD, "a 4K recording under way is drawn in 4K")

        preferences.recording.height = PictureHeight.fullHD
        applier.apply(preferences, isHeard: false, isRecording: true)
        XCTAssertEqual(drawing.sizes.last, .fullHD)

        for switchOn: (inout AppPreferences) -> Void in [
            { $0.webStream.isOn = true }, { $0.webMovie.isOn = true }, { $0.rtmp.isOn = true },
            { $0.sendsToAirPlay = true }, { $0.sendsToCast = true },
        ] {
            var withOne = preferences
            switchOn(&withOne)
            applier.apply(withOne, isHeard: false, isRecording: false)
            XCTAssertEqual(drawing.sizes.last, .ultraHD, "each stream that is on and taller than Full HD asks for 4K")
        }

        preferences.webStream.isOn = true
        preferences.webStream.options.height = 720
        applier.apply(preferences, isHeard: false, isRecording: false)
        XCTAssertEqual(drawing.sizes.last, .fullHD)
    }

    func testTheMicrophoneIsFollowedThroughInstallingAndRemoving() {
        let installer = FakeMicrophoneInstaller()
        let output = FakeMicrophone()
        let setup = MicrophoneSetup(installer: installer, output: output)
        XCTAssertEqual(setup.state, .notInstalled)
        installer.isInstalled = true
        XCTAssertEqual(setup.state, .installed)

        var finished = 0
        setup.install { finished += 1 }
        XCTAssertEqual(setup.state, .installing)
        installer.installs[0]("no administrator")
        XCTAssertEqual(setup.state, .failed("no administrator"))
        XCTAssertEqual(finished, 1)

        setup.remove { finished += 1 }
        XCTAssertEqual(setup.state, .installing, "trying again clears the last failure")
        installer.isInstalled = false
        installer.removals[0](nil)
        XCTAssertEqual(setup.state, .notInstalled)
        XCTAssertEqual(finished, 2)
        XCTAssertEqual(output.changes, [false, false], "what played to the microphone starts afresh each time")
    }
}

final class SnapshotTakerTests: XCTestCase {
    private let renderer = FakeRenderer()
    private let writer = FakeSnapshotWriter()
    private let files = FakeFiles()
    private lazy var taker = SnapshotTaker(frames: renderer, writer: writer, folders: FakeFolders(), files: files)
    private let folder = URL(fileURLWithPath: "/pictures")

    func testSnapshotsGoToTheChosenFolderOrTheDesktop() {
        var preferences = AppPreferences()
        XCTAssertEqual(taker.directory(for: preferences), FakeFolders().desktopDirectory)
        preferences.snapshotsFolder = ""
        XCTAssertEqual(taker.directory(for: preferences), FakeFolders().desktopDirectory)
        preferences.snapshotsFolder = "/pictures"
        XCTAssertEqual(taker.directory(for: preferences), folder)
    }

    func testWithNothingOnAirNothingIsWritten() {
        XCTAssertNil(taker.write(to: folder))
        XCTAssertTrue(writer.written.isEmpty)
    }

    func testTheFrameOnAirIsWrittenAndTheFileReturned() {
        renderer.latestProgramFrame = makePixelBuffer()
        writer.result = folder.appendingPathComponent("a.png")
        XCTAssertEqual(taker.write(to: folder), writer.result)
    }

    func testTakingASnapshotShowsTheFile() {
        renderer.latestProgramFrame = makePixelBuffer()
        writer.result = folder.appendingPathComponent("a.png")
        taker.take(to: folder)
        XCTAssertEqual(files.revealed, [folder.appendingPathComponent("a.png")])
    }

    func testAFailedSnapshotShowsNothing() {
        renderer.latestProgramFrame = makePixelBuffer()
        taker.take(to: folder)
        XCTAssertTrue(files.revealed.isEmpty)
    }
}

@MainActor
final class FullScreenControllerTests: XCTestCase {
    private let output = FakeFullScreen()
    private lazy var controller = FullScreenController(output: output)

    func testCoveringAConnectedDisplayKeepsIt() {
        output.connected = [3]
        XCTAssertEqual(controller.cover(3), 3)
    }

    func testCoveringADisplayThatIsNotThereGivesNothing() {
        XCTAssertNil(controller.cover(3))
        XCTAssertEqual(output.shown, [3])
    }

    func testAskingForNoDisplayUncoversTheScreens() {
        XCTAssertNil(controller.cover(nil))
        XCTAssertEqual(output.hideCount, 1)
    }

    func testTheCoveredDisplayIsKeptOnlyWhileItIsConnected() {
        let displays = [DisplayChoice(id: 3, name: "Side")]
        XCTAssertEqual(controller.stillConnected(3, among: displays), 3)
        XCTAssertNil(controller.stillConnected(4, among: displays))
        XCTAssertNil(controller.stillConnected(nil, among: displays))
    }
}

final class TitleTests: XCTestCase {
    func testEverySourceHasANameForTheList() {
        var star = ShapeSettings()
        star.kind = .star
        var windowed = WindowSettings(titlePattern: "Notes")
        windowed.isRegularExpression = false
        let titles: [(SourceSpec, String)] = [
            (.camera(deviceID: "x"), "Camera"),
            (.display(DisplaySettings(displayID: 1)), "Screen"),
            (.microphone(deviceID: nil), "Microphone"),
            (.window(windowed), "Window: Notes"),
            (.window(WindowSettings(titlePattern: "")), "Window"),
            (.movie(MovieSettings()), "Video"),
            (.slideShow(SlideShowSettings()), "Slide show"),
            (.stream(StreamSettings()), "Stream"),
            (.website(url: ""), "Website"),
            (.telestrator(TelestratorSettings()), "Telestrator"),
            (.colorBars, "Colour bars"),
            (.testCard, "Test card"),
            (.shape(star), "Shape: Star"),
            (.text(TextSettings()), "Text: Text"),
            (.image(path: ""), "Image"),
            (.image(path: "/a/b/cat.png"), "Image: cat.png"),
        ]
        for (spec, title) in titles {
            XCTAssertEqual(spec.title, title)
        }
    }

    func testTextWithNothingInItIsNamedByItsPrefixAlone() {
        var text = TextSettings()
        text.text = ""
        XCTAssertEqual(SourceSpec.text(text).title, "Text: ")
    }

    func testEveryShapeHasALabel() {
        let labels = ShapeKind.allCases.map(\.label)
        XCTAssertEqual(labels, ["Rectangle", "Square", "Circle", "Ellipse", "Triangle", "Diamond", "Star"])
    }

    func testStepsAreNamedByWhatTheyAre() {
        XCTAssertEqual(ChainItem(content: .script(source: "x")).title, "AppleScript")
        XCTAssertEqual(effectItem("Frosted Glass").title, "Frosted Glass")
        XCTAssertEqual(sourceItem(.testCard).title, "Test card")
    }

    func testScriptsKnowAnEffectByItsFileNameAndOtherStepsByTheirTitle() {
        XCTAssertEqual(effectItem("Frosted Glass").scriptName, "Frosted Glass")
        XCTAssertEqual(sourceItem(.testCard).scriptName, "Test card")
    }
}
