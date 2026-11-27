import CamTwistCore
import XCTest
@testable import CamTwistRendering
@testable import CamTwistControl

/// The cameras and pictures a test says there are.
@MainActor
private final class FakeStartingChoices: StartingChoices {
    var cameras: [CameraChoice] = []
    var savedPictures: [SavedPicture] = []
}

@MainActor
final class StepsModelTests: XCTestCase {
    private let state = FakeState()
    private let choices = FakeStartingChoices()

    private func makeModel() -> StepsModel {
        StepsModel(
            state: state, builder: StepBuilder(parameters: EffectParameters(library: FakeEffectLibrary())),
            choices: choices, companions: CaptionsMicrophone()
        )
    }

    private let captions = ChainItem.Content.effect(name: LiveCaptionsEffect.name, values: [:])
    private let microphone = ChainItem.Content.source(.microphone(deviceID: nil))

    func testCaptionsWithNothingHeardAboveBringAMicrophoneJustAboveThem() throws {
        let camera = sourceItem(.camera(deviceID: "built-in"))
        state.scene = SceneConfiguration(items: [camera])
        makeModel().add(captions)
        XCTAssertEqual(state.scene.items.map(\.content), [camera.content, microphone, captions])
        XCTAssertEqual(state.selectedStepID, state.scene.items.last?.id, "the captions are what is chosen")
    }

    func testCaptionsBelowSomethingHeardComeAlone() {
        let video = sourceItem(.movie(MovieSettings()))
        state.scene = SceneConfiguration(items: [video])
        makeModel().add(captions)
        XCTAssertEqual(state.scene.items.map(\.content), [video.content, captions])
    }

    func testOnlyWhatIsAboveTheCaptionsCounts() throws {
        let camera = sourceItem(.camera(deviceID: "built-in"))
        let mic = sourceItem(.microphone(deviceID: nil))
        var muted = sourceItem(.microphone(deviceID: nil))
        muted.volume = SceneSound.silent
        var off = sourceItem(.microphone(deviceID: nil))
        off.isEnabled = false
        let picture = sourceItem(.image(path: "/pictures/logo.png"))
        state.scene = SceneConfiguration(items: [camera, picture, muted, off, mic])
        makeModel().add(captions, before: mic.id, inBranchOf: nil)
        XCTAssertEqual(state.scene.items.map(\.content), [
            camera.content, picture.content, muted.content, off.content, microphone, captions, mic.content,
        ])
    }

    func testCaptionsInABranchHearItsSource() throws {
        let mic = sourceItem(.microphone(deviceID: nil))
        let camera = sourceItem(.camera(deviceID: "built-in"))
        state.scene = SceneConfiguration(items: [mic, camera])
        let model = makeModel()
        model.add(captions, before: nil, inBranchOf: mic.id)
        XCTAssertEqual(state.scene.item(id: mic.id)?.branch?.map(\.content), [captions])
        model.add(captions, before: nil, inBranchOf: camera.id)
        XCTAssertEqual(state.scene.item(id: camera.id)?.branch?.map(\.content), [microphone, captions])
    }

    func testOtherStepsBringNothing() {
        makeModel().add(.effect(name: "Fx", values: [:]))
        XCTAssertEqual(state.scene.items.count, 1)
    }

    func testAnAddedStepIsSelectedWithItsSettingsOpen() throws {
        let model = makeModel()
        model.add(.source(.colorBars))
        let added = try XCTUnwrap(state.scene.items.last)
        XCTAssertEqual(added.content, .source(.colorBars))
        XCTAssertEqual(state.selectedStepID, added.id)
        XCTAssertEqual(state.expandedSteps, [added.id])
    }

    func testAStepGoesIntoTheChosenBranchWhileItsSourceIsThere() {
        let source = sourceItem(.testCard)
        state.scene = SceneConfiguration(items: [source])
        state.branchTarget = source.id
        let model = makeModel()
        model.add(.effect(name: "Fx", values: [:]))
        XCTAssertEqual(state.scene.item(id: source.id)?.branch?.count, 1)
        XCTAssertEqual(state.branchTarget, source.id)

        state.scene = SceneConfiguration()
        model.add(.source(.colorBars))
        XCTAssertNil(state.branchTarget, "a branch whose source has gone is forgotten")
        XCTAssertEqual(state.scene.items.count, 1)
    }

    func testAStepCanBeAddedBeforeAnother() {
        let first = sourceItem(.testCard)
        state.scene = SceneConfiguration(items: [first])
        makeModel().add(.source(.colorBars), before: first.id, inBranchOf: nil)
        XCTAssertEqual(state.scene.items.last?.id, first.id)
    }

    func testDroppedImagesAndVideosAreAddedAndOtherFilesAreNot() {
        makeModel().addFiles(["/clips/intro.MOV", "/notes/readme.txt", "/pictures/logo.png"])
        XCTAssertEqual(state.scene.items.map(\.content), [
            .source(.movie(MovieSettings(files: ["/clips/intro.MOV"]))), .source(.image(path: "/pictures/logo.png")),
        ])
    }

    func testEveryStepButAScriptCanBeResetAndAResetKeepsWhatItShows() {
        let model = makeModel()
        XCTAssertFalse(model.canReset(ChainItem(content: .script(source: ""))))
        XCTAssertTrue(model.canReset(sourceItem(.colorBars)))
        XCTAssertTrue(model.canReset(effectItem("Ring")))

        let text = sourceItem(.text(TextSettings(text: "Hello", fontSize: 30)))
        state.scene = SceneConfiguration(items: [text])
        model.reset(id: text.id)
        XCTAssertEqual(state.scene.item(id: text.id)?.content, .source(.text(TextSettings(text: "Hello"))))
    }

    func testNewSourcesAndScenesStartFromTheBestCameraOrTheDrawnTestCard() {
        let model = makeModel()
        XCTAssertNil(model.newCameraSource)
        XCTAssertEqual(model.newImageSource, .image(path: ""))
        XCTAssertEqual(model.startingScene().items.map(\.content), [.source(.testCard)])

        choices.savedPictures = [SavedPicture(name: "test-card", path: "/pictures/test-card.png")]
        XCTAssertEqual(model.newImageSource, .image(path: ""), "a picture's name no longer chooses it")
        XCTAssertEqual(model.startingScene().items.map(\.content), [.source(.testCard)])
        choices.cameras = [CameraChoice(id: "cam", name: "Camera")]
        XCTAssertEqual(model.newCameraSource, .camera(deviceID: "cam"))
        XCTAssertEqual(model.startingScene().items.map(\.content), [.source(.camera(deviceID: "cam"))])
    }
}

@MainActor
final class RefreshTriggersTests: XCTestCase {
    private static let interval: TimeInterval = 3

    func testAFreshLookIsAskedForOnceTheCameraIsAnsweredAndThenEverySoOften() {
        let permissions = FakePermissions()
        let scheduler = FakeScheduler()
        let triggers = RefreshTriggers(
            permissions: permissions, scheduler: scheduler, interval: Self.interval, queue: ImmediateQueue()
        )
        var refreshes = 0
        triggers.start { refreshes += 1 }
        XCTAssertEqual(refreshes, 0)
        permissions.completions[0]()
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(scheduler.timers.map(\.interval), [Self.interval])
        scheduler.fire(0)
        XCTAssertEqual(refreshes, 2)
    }
}
