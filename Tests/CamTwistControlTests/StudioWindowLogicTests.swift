import CamTwistCore
import XCTest
@testable import CamTwistControl

final class StudioWindowLogicTests: XCTestCase {
    func testATileIsOutlinedByWhereItStands() {
        XCTAssertEqual(StudioTile(sceneName: "A", isOnAir: true, isLinedUp: true).outline, .onAir)
        XCTAssertEqual(StudioTile(sceneName: "A", isOnAir: false, isLinedUp: true).outline, .linedUp)
        XCTAssertEqual(StudioTile(sceneName: "A", isOnAir: false, isLinedUp: false).outline, .quiet)
        XCTAssertTrue(StudioTile(sceneName: "A", isOnAir: true, isLinedUp: false).isEmphasised)
        XCTAssertTrue(StudioTile(sceneName: "A", isOnAir: false, isLinedUp: true).isEmphasised)
        XCTAssertFalse(StudioTile(sceneName: "A", isOnAir: false, isLinedUp: false).isEmphasised)
    }

    func testATileSaysWhatClickingDoes() {
        XCTAssertEqual(StudioTile(sceneName: "Wide", isOnAir: true, isLinedUp: false).help, "Wide is on air")
        XCTAssertEqual(
            StudioTile(sceneName: "Wide", isOnAir: false, isLinedUp: false).help,
            "Click to preview Wide, double click to put it on air"
        )
    }

    func testTheMonitorsNameTheirScenes() {
        let first = StudioButton(name: "One", scene: SceneConfiguration())
        let second = StudioButton(name: "Two", scene: SceneConfiguration())
        let monitors = StudioMonitors(
            scenes: [first, second], onAirID: first.id, previewedID: second.id, hasPreview: true, isTransitioning: false
        )
        XCTAssertEqual(monitors.onAirName, "One")
        XCTAssertEqual(monitors.previewedName, "Two")
        XCTAssertEqual(monitors.goLiveTitle, "Go live")
        XCTAssertTrue(monitors.canSwitch)
    }

    func testTheMonitorsAreBlankWithoutScenesAndLockWhileSwitching() {
        let monitors = StudioMonitors(scenes: [], onAirID: nil, previewedID: nil, hasPreview: false, isTransitioning: true)
        XCTAssertEqual(monitors.onAirName, "")
        XCTAssertEqual(monitors.previewedName, "")
        XCTAssertEqual(monitors.goLiveTitle, "Switching")
        XCTAssertFalse(monitors.canSwitch)
        XCTAssertFalse(
            StudioMonitors(scenes: [], onAirID: nil, previewedID: nil, hasPreview: false, isTransitioning: false).canSwitch
        )
        XCTAssertFalse(
            StudioMonitors(scenes: [], onAirID: nil, previewedID: nil, hasPreview: true, isTransitioning: true).canSwitch
        )
    }

    func testThePictureBarShowsAProblemBeforeAHintBeforeNothing() {
        XCTAssertEqual(PictureBarText.hint(setupProblem: "Bad file", dragHint: "Drag"), "Bad file")
        XCTAssertEqual(PictureBarText.hint(setupProblem: nil, dragHint: "Drag"), "Drag")
        XCTAssertEqual(PictureBarText.hint(setupProblem: nil, dragHint: nil), PictureBarText.blankHint)
        XCTAssertEqual(PictureBarText.snapshotHelp(folderName: "Desktop"), "Save the picture to Desktop")
    }
}

final class StudioTransitionChoiceTests: XCTestCase {
    func testEachSceneItsOwnWayHasNoTimeToSet() {
        let own = StudioTransitionChoice(chosen: nil, seconds: 1)
        XCTAssertFalse(own.showsSeconds)
        XCTAssertEqual(own.goLiveHelp, "Put the scene in the preview on air the way that scene comes on air")
        XCTAssertEqual(StudioTransitionChoice.scenesOwnTitle, "Scene's own")
        XCTAssertEqual(own.title, "Scene's own")
        XCTAssertEqual(own.caption, "Each scene its own way")
    }

    func testAChosenTransitionHasATimeUnlessItIsACut() {
        let dissolve = StudioTransitionChoice(chosen: StudioSettings.defaultTransitionName, seconds: 1)
        XCTAssertTrue(dissolve.showsSeconds)
        XCTAssertEqual(dissolve.goLiveHelp, "Put the scene in the preview on air with Dissolve")
        XCTAssertEqual(dissolve.title, "Dissolve")
        XCTAssertEqual(dissolve.caption, "Dissolve · 1 s")
        XCTAssertEqual(StudioTransitionChoice(chosen: StudioSettings.cutName, seconds: 1).caption, "Cut", "a cut takes no time")
        XCTAssertFalse(StudioTransitionChoice(chosen: StudioSettings.cutName, seconds: 1).showsSeconds)
    }
}

final class StudioHintTests: XCTestCase {
    func testTheHintWaitsForScenesToSwitchBetween() {
        XCTAssertFalse(StudioHint.shows(sceneCount: 1, hasOpenedStudio: false))
        XCTAssertTrue(StudioHint.shows(sceneCount: 2, hasOpenedStudio: false))
    }

    func testTheHintStopsOnceTheStudioHasBeenOpened() {
        XCTAssertFalse(StudioHint.shows(sceneCount: 3, hasOpenedStudio: true))
    }
}
