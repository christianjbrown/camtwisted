import CamTwistCore
import XCTest
@testable import CamTwistControl

@MainActor
private final class FakeHandler: ActionHandling {
    let claims: Bool
    var seen: [TriggerAction] = []
    init(claims: Bool) { self.claims = claims }
    func handle(_ action: TriggerAction) -> Bool {
        seen.append(action)
        return claims
    }
}

@MainActor
final class ActionRouterTests: XCTestCase {
    func testTheFirstHandlerThatKnowsTheActionIsTheOnlyOneToAct() {
        let first = FakeHandler(claims: false)
        let second = FakeHandler(claims: true)
        let third = FakeHandler(claims: true)
        ActionRouter(handlers: [first, second, third]).perform(.clearScene)
        XCTAssertEqual(first.seen, [.clearScene])
        XCTAssertEqual(second.seen, [.clearScene])
        XCTAssertEqual(third.seen, [])
    }
}

@MainActor
final class SceneActionHandlerTests: XCTestCase {
    private let state = FakeState()
    private lazy var handler = SceneActionHandler(state: state)

    func testClearingEmptiesTheScene() {
        state.scene = SceneConfiguration(items: [effectItem("Blur")])
        XCTAssertTrue(handler.handle(.clearScene))
        XCTAssertEqual(state.scene, SceneConfiguration())
    }

    func testOtherActionsAreNotItsBusiness() {
        XCTAssertFalse(handler.handle(.studioCut))
    }
}

@MainActor
final class StudioActionHandlerTests: XCTestCase {
    private let wide = SceneConfiguration(items: [sourceItem(.testCard)])
    private let state = FakeState()
    private let renderer = FakeRenderer()
    private lazy var handler = StudioActionHandler(
        state: state, transitions: TransitionRunner(state: state, renderer: renderer)
    )

    override func setUp() async throws {
        state.studio = StudioSettings(buttons: [StudioButton(name: "Wide", scene: wide)])
    }

    func testPreviewingALookLinesItUp() {
        XCTAssertTrue(handler.handle(.studioPreview(button: "Wide")))
        XCTAssertEqual(state.studioPreview, wide)
    }

    func testPreviewingAnUnknownLookDoesNothing() {
        XCTAssertTrue(handler.handle(.studioPreview(button: "Nope")))
        XCTAssertNil(state.studioPreview)
    }

    func testPunchingALookPutsItStraightOnAir() {
        XCTAssertTrue(handler.handle(.studioPunch(button: "Wide")))
        XCTAssertEqual(state.scene, wide)
        XCTAssertEqual(state.studio.onAirID, state.studio.buttons.first?.id)
    }

    func testPunchingAnUnknownLookDoesNothing() {
        XCTAssertTrue(handler.handle(.studioPunch(button: "Nope")))
        XCTAssertEqual(state.scene, SceneConfiguration())
    }

    func testCuttingSwapsThePreviewOntoAir() {
        state.studioPreview = wide
        XCTAssertTrue(handler.handle(.studioCut))
        XCTAssertEqual(state.scene, wide)
        XCTAssertEqual(state.studio.onAirID, state.studio.buttons.first?.id, "the scene it shows is now on air")
    }

    func testCuttingWithNothingInPreviewKeepsTheProgram() {
        XCTAssertTrue(handler.handle(.studioCut))
        XCTAssertEqual(state.scene, SceneConfiguration())
    }

    func testGoingLiveWithASceneThatCutsCutsAtOnce() {
        state.studioPreview = wide
        XCTAssertTrue(handler.handle(.studioTransition))
        XCTAssertEqual(state.scene, wide)
        XCTAssertTrue(renderer.transitions.isEmpty)
    }

    func testGoingLiveUsesTheScenesOwnTransition() {
        state.studio.buttons[0].switchName = "Wipe"
        state.studio.buttons[0].switchTime = 4
        state.studioPreview = wide
        XCTAssertTrue(handler.handle(.studioTransition))
        XCTAssertTrue(state.isTransitioning)
        XCTAssertEqual(renderer.transitions.first?.name, "Wipe")
        XCTAssertEqual(renderer.transitions.first?.duration, 4)
    }

    func testAPreviewThatIsNoSavedSceneUsesTheStudiosTransition() {
        let loose = SceneConfiguration(items: [sourceItem(.colorBars)])
        state.studio.transitionTime = 3
        state.studioPreview = loose
        XCTAssertTrue(handler.handle(.studioTransition))
        XCTAssertEqual(renderer.transitions.first?.name, StudioSettings.defaultTransitionName)
        XCTAssertEqual(renderer.transitions.first?.duration, 3)

        state.isTransitioning = false
        state.studio.transitionName = StudioSettings.cutName
        XCTAssertTrue(handler.handle(.studioTransition))
        XCTAssertEqual(state.scene, loose)
        XCTAssertEqual(renderer.transitions.count, 1)
    }

    func testTheTransitionChosenInTheStudioWinsOverTheScenesOwn() {
        state.studio.buttons[0].switchName = "Wipe"
        state.studio.choose(transition: "Page Curl")
        state.studio.transitionTime = 2
        state.studioPreview = wide
        XCTAssertTrue(handler.handle(.studioTransition))
        XCTAssertEqual(renderer.transitions.first?.name, "Page Curl")
        XCTAssertEqual(renderer.transitions.first?.duration, 2)

        state.isTransitioning = false
        state.scene = SceneConfiguration()
        state.studio.choose(transition: StudioSettings.cutName)
        XCTAssertTrue(handler.handle(.studioTransition))
        XCTAssertEqual(state.scene, wide, "a chosen cut is instant, whatever the scene asks for")
        XCTAssertEqual(renderer.transitions.count, 1)
    }

    func testGoingLiveWithoutAPreviewDoesNothing() {
        XCTAssertTrue(handler.handle(.studioTransition))
        XCTAssertFalse(state.isTransitioning)
    }

    func testGoingLiveWhileAlreadyFadingDoesNothing() {
        state.studioPreview = wide
        state.isTransitioning = true
        XCTAssertTrue(handler.handle(.studioTransition))
        XCTAssertTrue(renderer.transitions.isEmpty)
    }

    func testClearingTheStudioDropsThePreview() {
        state.studioPreview = wide
        XCTAssertTrue(handler.handle(.studioClear))
        XCTAssertNil(state.studioPreview)
    }

    func testOtherActionsAreNotItsBusiness() {
        XCTAssertFalse(handler.handle(.clearScene))
    }
}

@MainActor
final class ScriptHandlerTests: XCTestCase {
    func testRunningAppleScriptHandsTheSourceToTheRunner() {
        let scripts = FakeScripts()
        XCTAssertTrue(ScriptActionHandler(scripts: scripts).handle(.runAppleScript("beep")))
        XCTAssertEqual(scripts.sources, ["beep"])
    }

    func testTheScriptHandlerLeavesOtherActionsAlone() {
        XCTAssertFalse(ScriptActionHandler(scripts: FakeScripts()).handle(.clearScene))
    }
}
