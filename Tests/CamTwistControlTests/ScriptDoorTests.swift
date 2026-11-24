import CamTwistCore
@testable import CamTwistRendering
import XCTest
@testable import CamTwistControl

@MainActor
private final class FakeScriptChoices: ScriptSourceChoices {
    var cameras: [CameraChoice] = []
    var displays: [DisplayChoice] = []
}

@MainActor
private final class FakeSnapshotSaver: SnapshotSaving {
    var result: URL?
    func writeSnapshot() -> URL? { result }
}

@MainActor
final class ScriptDoorTests: XCTestCase {
    private let state = FakeState()
    private let library = FakeEffectLibrary()
    private let choices = FakeScriptChoices()
    private let snapshots = FakeSnapshotSaver()
    private let steps = FakeStepAdder()

    private func makeDoor() -> ScriptDoor {
        ScriptDoor(
            state: state, scripting: ScriptingSupport(parameters: EffectParameters(library: library)),
            choices: choices, snapshots: snapshots, steps: steps
        )
    }

    func testAScriptSeesAndChangesTheSceneAndTheScenes() {
        let door = makeDoor()
        let scene = SceneConfiguration(items: [sourceItem(.testCard)])
        door.scene = scene
        XCTAssertEqual(state.scene, scene)
        XCTAssertEqual(door.scene, scene)
        door.studio.transitionName = "Wipe"
        XCTAssertEqual(state.studio.transitionName, "Wipe")
        XCTAssertEqual(door.studio, state.studio)
    }

    func testActionsGoToTheModelAndNewStepsToWhateverAddsThem() {
        let door = makeDoor()
        door.performOnMain(.studioCut)
        door.addStep(.source(.colorBars))
        XCTAssertEqual(state.performed, [.studioCut])
        XCTAssertEqual(steps.added, [.source(.colorBars)])
    }

    func testSourcesAreFoundByNameAmongWhatIsConnected() {
        let door = makeDoor()
        XCTAssertNil(door.sourceSpec(named: "Webcam"), "no camera is connected")
        choices.cameras = [CameraChoice(id: "cam", name: "Camera")]
        choices.displays = [DisplayChoice(id: 1, name: "Main")]
        XCTAssertEqual(door.sourceSpec(named: "Webcam"), .camera(deviceID: "cam"))
        XCTAssertEqual(door.sourceSpec(named: "Desktop"), .display(DisplaySettings(displayID: 1)))
    }

    func testAnEffectControlIsSetInTheSceneBeingChanged() {
        library.controls["Fx"] = [numberControl("amount", name: "Amount")]
        let effect = effectItem("Fx")
        state.scene = SceneConfiguration(items: [effect])
        let door = makeDoor()
        XCTAssertTrue(door.setEffectProperty("amount", to: "2", ofStep: effect.id))
        XCTAssertEqual(state.scene.item(id: effect.id)?.content, .effect(name: "Fx", values: ["amount": .number(2)]))
        XCTAssertFalse(door.setEffectProperty("nope", to: "2", ofStep: effect.id))
    }

    func testASnapshotIsSavedThroughTheDoor() {
        let door = makeDoor()
        XCTAssertNil(door.writeSnapshot())
        snapshots.result = URL(fileURLWithPath: "/desktop/a.png")
        XCTAssertEqual(door.writeSnapshot(), snapshots.result)
    }

    func testACommandCanBeHandedOnlyTheSliceItUses() {
        let door = makeDoor()
        let scenes: ScriptedScenes = door
        let actions: ScriptActing = door
        let sources: ScriptSourceFinding = door
        let snapshotting: ScriptSnapshotting = door
        let slices = ScriptSlices(scenes: door, actions: door, sources: door, snapshots: door)
        scenes.studio.transitionName = "Wipe"
        actions.performOnMain(.studioCut)
        XCTAssertEqual(slices.scenes?.studio.transitionName, "Wipe")
        XCTAssertNotNil(slices.actions)
        XCTAssertNotNil(slices.sources)
        XCTAssertNotNil(slices.snapshots)
        XCTAssertEqual(state.performed, [.studioCut])
        XCTAssertNil(sources.sourceSpec(named: "Webcam"))
        XCTAssertNil(snapshotting.writeSnapshot())
    }
}
