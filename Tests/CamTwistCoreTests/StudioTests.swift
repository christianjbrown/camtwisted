import XCTest
@testable import CamTwistCore

private let bars = SceneConfiguration(items: [ChainItem(content: .source(.colorBars))])
private let camera = SceneConfiguration(items: [ChainItem(content: .source(.camera(deviceID: "a")))])
private let zoom = SceneConfiguration(items: [ChainItem(content: .effect(name: "Zoom", values: [:]))])

private final class MemoryStore: KeyValueStore {
    var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data?, forKey key: String) { values[key] = data }
}

final class CodableStoreTests: XCTestCase {
    func testLoadsTheFallbackUntilSomethingIsSaved() {
        let memory = MemoryStore()
        let store = CodableStore<[String]>(store: memory, key: "names", fallback: ["none"])
        XCTAssertEqual(store.load(), ["none"])

        store.save(["a", "b"])
        XCTAssertEqual(store.load(), ["a", "b"])

        memory.values["names"] = Data("broken".utf8)
        XCTAssertEqual(store.load(), ["none"])
    }
}

final class StudioTests: XCTestCase {
    func testButtonsAreFoundByNameAndNote() {
        let studio = StudioSettings(buttons: [
            StudioButton(name: "Wide", scene: bars, midiNote: 60),
            StudioButton(name: "Close", scene: camera),
        ])
        XCTAssertEqual(studio.button(named: "Close")?.scene, camera)
        XCTAssertNil(studio.button(named: "Missing"))
        XCTAssertEqual(studio.button(forMIDINote: 60)?.name, "Wide")
        XCTAssertNil(studio.button(forMIDINote: 61))
        XCTAssertEqual(studio.transitionName, StudioSettings.defaultTransitionName)
        XCTAssertEqual(studio.transitionTime, StudioSettings.defaultTransitionTime)
        XCTAssertFalse(studio.swapMode)
    }

    func testTheLookOnAirIsFoundByItsScene() {
        let studio = StudioSettings(buttons: [
            StudioButton(name: "Wide", scene: bars), StudioButton(name: "Close", scene: camera),
        ])
        XCTAssertEqual(studio.button(showing: camera)?.name, "Close")
        XCTAssertNil(studio.button(showing: zoom))
    }

    func testCutIsTheInstantTransition() {
        XCTAssertFalse(StudioSettings().cutsInstantly)
        XCTAssertTrue(StudioSettings(transitionName: StudioSettings.cutName).cutsInstantly)
    }

    func testDuplicateButtonGetsANewIdentityAndName() {
        let button = StudioButton(name: "Wide", scene: bars, midiNote: 60, thumbnail: Data([1, 2, 3]))
        let copy = button.duplicated()
        XCTAssertEqual(copy.thumbnail, Data([1, 2, 3]))
        XCTAssertNotEqual(copy.id, button.id)
        XCTAssertEqual(copy.name, "Wide copy")
        XCTAssertEqual(copy.scene, bars)
        XCTAssertNil(copy.midiNote)
    }

    func testASceneComesOnAirWithACutUnlessATransitionIsChosen() {
        var scene = StudioButton(name: "Wide", scene: SceneConfiguration())
        XCTAssertTrue(scene.cutsInstantly)
        XCTAssertEqual(scene.switchName, StudioSettings.cutName)
        XCTAssertEqual(scene.switchTime, StudioSettings.defaultTransitionTime)
        scene.switchName = "Dissolve"
        scene.switchTime = 3
        XCTAssertFalse(scene.cutsInstantly)
        XCTAssertEqual(scene.transitionName, "Dissolve")
        XCTAssertEqual(scene.transitionTime, 3)
        let copy = scene.duplicated()
        XCTAssertEqual(copy.switchName, "Dissolve")
        XCTAssertEqual(copy.switchTime, 3)
    }

    func testScenesSavedBeforeTheyHadASwitchStillLoad() throws {
        let old = Data(#"{"buttons":[],"transitionName":"Dissolve","transitionTime":1,"swapMode":false}"#.utf8)
        let studio = try JSONDecoder().decode(StudioSettings.self, from: old)
        XCTAssertNil(studio.onAirID)
        XCTAssertNil(studio.sceneOnAir)
    }

    func testWhatIsOnAirBecomesASceneAndTheSceneOnAirFollowsIt() {
        let bars = SceneConfiguration(items: [ChainItem(content: .source(.colorBars))])
        let card = SceneConfiguration(items: [ChainItem(content: .source(.testCard))])
        var studio = StudioSettings()
        studio.adoptProgram(bars)
        XCTAssertEqual(studio.buttons.map(\.name), ["Scene 1"])
        XCTAssertEqual(studio.sceneOnAir?.scene, bars)

        // What goes on air next is the same scene, changed.
        studio.adoptProgram(card)
        XCTAssertEqual(studio.buttons.count, 1)
        XCTAssertEqual(studio.sceneOnAir?.scene, card)

        // With nothing marked, a scene already showing the program is the one on air.
        var saved = StudioSettings(buttons: [
            StudioButton(name: "Wide", scene: bars), StudioButton(name: "Close", scene: card),
        ])
        saved.adoptProgram(card)
        XCTAssertEqual(saved.sceneOnAir?.name, "Close")
        XCTAssertEqual(saved.buttons.count, 2)

        // And when none shows it, it joins them at the top.
        var others = StudioSettings(buttons: [StudioButton(name: "Scene 2", scene: bars)])
        others.adoptProgram(card)
        XCTAssertEqual(others.buttons.map(\.name), ["Scene 3", "Scene 2"])
        XCTAssertEqual(others.sceneOnAir?.scene, card)
    }

    func testTheSceneShowingAProgramIsMarkedOnAir() {
        let bars = SceneConfiguration(items: [ChainItem(content: .source(.colorBars))])
        let card = SceneConfiguration(items: [ChainItem(content: .source(.testCard))])
        let wide = StudioButton(name: "Wide", scene: bars)
        let twin = StudioButton(name: "Twin", scene: bars)
        let close = StudioButton(name: "Close", scene: card)
        var studio = StudioSettings(buttons: [wide, twin, close], onAirID: twin.id)
        studio.markOnAir(showing: bars)
        XCTAssertEqual(studio.onAirID, twin.id, "the one on air already shows it, so it stays")
        studio.markOnAir(showing: card)
        XCTAssertEqual(studio.onAirID, close.id)
        studio.markOnAir(showing: SceneConfiguration())
        XCTAssertEqual(studio.onAirID, close.id, "no scene shows that, so nothing changes")
    }

    func testScenesAreAddedCopiedAndRemovedButNeverTheOneOnAir() {
        var studio = StudioSettings()
        studio.adoptProgram(SceneConfiguration())
        let onAir = studio.onAirID
        let added = studio.addScene(SceneConfiguration(items: [ChainItem(content: .source(.testCard))]))
        XCTAssertEqual(studio.buttons.map(\.name), ["Scene 1", "Scene 2"])
        let copy = studio.duplicateScene(id: added)
        XCTAssertEqual(studio.buttons.map(\.name), ["Scene 1", "Scene 2", "Scene 2 copy"])
        XCTAssertNotNil(copy)
        XCTAssertNil(studio.duplicateScene(id: UUID()))
        XCTAssertEqual(studio.nextSceneName, "Scene 4")

        studio.removeScene(id: added)
        XCTAssertEqual(studio.buttons.map(\.name), ["Scene 1", "Scene 2 copy"])
        studio.removeScene(id: onAir ?? UUID())
        XCTAssertEqual(studio.buttons.count, 2, "the scene on air stays")
        // A name freed by a removal is not handed out twice.
        XCTAssertEqual(studio.nextSceneName, "Scene 3")
    }

    func testASceneMovesToWhereAnotherIs() {
        let names = ["A", "B", "C", "D"]
        var studio = StudioSettings(buttons: names.map { StudioButton(name: $0, scene: SceneConfiguration()) })
        let ids = studio.buttons.map(\.id)
        studio.moveScene(id: ids[0], toPositionOf: ids[2])
        XCTAssertEqual(studio.buttons.map(\.name), ["B", "C", "A", "D"])
        studio.moveScene(id: ids[3], toPositionOf: ids[1])
        XCTAssertEqual(studio.buttons.map(\.name), ["D", "B", "C", "A"])
        studio.moveScene(id: ids[1], toPositionOf: ids[1])
        studio.moveScene(id: UUID(), toPositionOf: ids[1])
        studio.moveScene(id: ids[1], toPositionOf: UUID())
        XCTAssertEqual(studio.buttons.map(\.name), ["D", "B", "C", "A"])
    }

    func testCutPutsThePreviewOnAir() {
        let bus = StudioBus(program: bars, preview: camera)
        XCTAssertEqual(bus.cutting(swapMode: false), StudioBus(program: camera, preview: camera))
        XCTAssertEqual(bus.cutting(swapMode: true), StudioBus(program: camera, preview: bars))
        XCTAssertEqual(StudioBus(program: bars).cutting(swapMode: true), StudioBus(program: bars))
    }

    func testLandingATransitionMatchesACut() {
        let bus = StudioBus(program: bars, preview: camera)
        XCTAssertEqual(bus.landing(on: camera, swapMode: true), StudioBus(program: camera, preview: bars))
        XCTAssertEqual(bus.landing(on: camera, swapMode: false), StudioBus(program: camera, preview: camera))
    }
}

final class TriggerActionTests: XCTestCase {
    func testActionsSurviveARoundTrip() throws {
        let actions: [TriggerAction] = [
            .clearScene, .studioPreview(button: "c"), .studioPunch(button: "d"),
            .studioTransition, .studioCut, .studioClear, .runAppleScript("beep"),
        ]
        let data = try JSONEncoder().encode(actions)
        XCTAssertEqual(try JSONDecoder().decode([TriggerAction].self, from: data), actions)
    }
}

final class StudioSwitchTests: XCTestCase {
    private static let sceneSeconds = 4.0
    private static let studioSeconds = 2.0

    private func scene() -> StudioButton {
        StudioButton(
            name: "Wide", scene: SceneConfiguration(), transitionName: "Wipe", transitionTime: Self.sceneSeconds
        )
    }

    func testEachSceneComesOnAirItsOwnWayUntilTheStudioChoosesOne() {
        var studio = StudioSettings(transitionTime: Self.studioSeconds)
        XCTAssertNil(studio.chosenTransition)
        XCTAssertEqual(studio.studioSwitch(to: scene()), StudioSwitch(name: "Wipe", duration: Self.sceneSeconds))
        XCTAssertEqual(
            studio.studioSwitch(to: nil),
            StudioSwitch(name: StudioSettings.defaultTransitionName, duration: Self.studioSeconds),
            "a preview that is no saved scene uses the studio's usual one"
        )
        studio.choose(transition: "Page Curl")
        XCTAssertEqual(studio.transitionName, "Page Curl")
        XCTAssertEqual(studio.studioSwitch(to: scene()), StudioSwitch(name: "Page Curl", duration: Self.studioSeconds))
        XCTAssertEqual(studio.studioSwitch(to: nil), StudioSwitch(name: "Page Curl", duration: Self.studioSeconds))
        studio.chosenTransition = nil
        XCTAssertEqual(studio.studioSwitch(to: scene()).name, "Wipe", "Scene's own again")
    }

    func testOnlyACutIsInstant() {
        XCTAssertTrue(StudioSwitch(name: StudioSettings.cutName, duration: Self.studioSeconds).cutsInstantly)
        XCTAssertFalse(StudioSwitch(name: "Wipe", duration: Self.studioSeconds).cutsInstantly)
    }
}
