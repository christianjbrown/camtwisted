import XCTest
@testable import CamTwistCore

private final class MemoryStore: KeyValueStore {
    var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data?, forKey key: String) { values[key] = data }
}

final class ChainItemTests: XCTestCase {
    func testSourceAndEffectTellThemselvesApart() {
        let source = ChainItem(content: .source(.colorBars))
        let effect = ChainItem(content: .effect(name: "Zoom", values: [:]))

        XCTAssertEqual(source.source, .colorBars)
        XCTAssertTrue(source.isSource)
        XCTAssertNil(effect.source)
        XCTAssertFalse(effect.isSource)
        XCTAssertTrue(source.isEnabled)
        XCTAssertNil(source.pictureInPicture)
    }

    func testDuplicateKeepsEverythingButTheIdentity() {
        let item = ChainItem(
            isEnabled: false, content: .source(.camera(deviceID: "a")),
            pictureInPicture: PictureInPictureSettings(corner: .topLeft)
        )
        let copy = item.duplicated()

        XCTAssertNotEqual(copy.id, item.id)
        XCTAssertEqual(copy.content, item.content)
        XCTAssertEqual(copy.isEnabled, item.isEnabled)
        XCTAssertEqual(copy.pictureInPicture, item.pictureInPicture)
    }
}

final class SceneConfigurationTests: XCTestCase {
    func testInitialSceneShowsColorBars() {
        XCTAssertEqual(SceneConfiguration.initial.items.map(\.content), [.source(.colorBars)])
        XCTAssertEqual(SceneConfiguration().items, [])
    }

    func testAddAppendsInOrder() {
        var scene = SceneConfiguration()
        scene.add(.source(.colorBars))
        scene.add(.effect(name: "Zoom", values: [:]))
        XCTAssertEqual(scene.items.map(\.content), [.source(.colorBars), .effect(name: "Zoom", values: [:])])
    }

    func testInsertPlacesAStepBeforeAnotherOrAtTheEnd() {
        var scene = SceneConfiguration()
        scene.add(.source(.colorBars))
        let first = scene.items[0].id
        let zoom = ChainItem(content: .effect(name: "Zoom", values: [:]))
        let bump = ChainItem(content: .effect(name: "Bump", values: [:]))
        let text = ChainItem(content: .effect(name: "Text", values: [:]))

        scene.insert(zoom, before: first)
        scene.insert(bump, before: nil)
        scene.insert(text, before: UUID())

        XCTAssertEqual(scene.items.map(\.id), [zoom.id, first, bump.id, text.id])
    }

    func testSetMainSourceReplacesTheFirstSourceOrAddsOne() {
        var scene = SceneConfiguration()
        scene.add(.effect(name: "Zoom", values: [:]))
        scene.setMainSource(.colorBars)
        XCTAssertEqual(scene.items.first?.content, .source(.colorBars))
        XCTAssertEqual(scene.items.count, 2)

        let id = scene.items[0].id
        scene.setMainSource(.camera(deviceID: "a"))
        XCTAssertEqual(scene.items.count, 2)
        XCTAssertEqual(scene.items[0].id, id)
        XCTAssertEqual(scene.items[0].content, .source(.camera(deviceID: "a")))
    }

    func testRemoveAndUpdate() {
        var scene = SceneConfiguration()
        scene.add(.source(.colorBars))
        scene.add(.effect(name: "Zoom", values: [:]))
        let ids = scene.items.map(\.id)

        scene.update(id: ids[0]) { $0.isEnabled = false }
        scene.update(id: UUID()) { $0.isEnabled = false }
        XCTAssertEqual(scene.items.map(\.isEnabled), [false, true])

        scene.remove(id: ids[0])
        XCTAssertEqual(scene.items.map(\.id), [ids[1]])
    }

    func testDraggingAStepTakesThePlaceOfTheOneItIsDroppedOn() {
        var scene = SceneConfiguration()
        scene.add(.source(.colorBars))
        scene.add(.effect(name: "Zoom", values: [:]))
        scene.add(.effect(name: "Bump", values: [:]))
        let ids = scene.items.map(\.id)

        scene.move(id: ids[0], toPositionOf: ids[2])
        XCTAssertEqual(scene.items.map(\.id), [ids[1], ids[2], ids[0]], "dragged down, it lands after")
        scene.move(id: ids[0], toPositionOf: ids[1])
        XCTAssertEqual(scene.items.map(\.id), [ids[0], ids[1], ids[2]], "dragged up, it lands before")
        scene.move(id: ids[0], toPositionOf: ids[0])
        scene.move(id: UUID(), toPositionOf: ids[0])
        scene.move(id: ids[0], toPositionOf: UUID())
        XCTAssertEqual(scene.items.map(\.id), ids)
    }

    func testSetValueOnlyTouchesEffects() {
        var scene = SceneConfiguration()
        scene.add(.source(.colorBars))
        scene.add(.effect(name: "Zoom", values: [:]))
        let ids = scene.items.map(\.id)

        scene.setValue(.number(2), forKey: "Scale", ofEffect: ids[1])
        scene.setValue(.number(9), forKey: "Scale", ofEffect: ids[0])

        XCTAssertEqual(scene.items[1].content, .effect(name: "Zoom", values: ["Scale": .number(2)]))
        XCTAssertEqual(scene.items[0].content, .source(.colorBars))
    }

    func testSourcesInUseSkipsDisabledStepsAndEffects() {
        var scene = SceneConfiguration()
        scene.add(.source(.colorBars))
        scene.add(.source(.camera(deviceID: "a")))
        scene.add(.effect(name: "Zoom", values: [:]))
        scene.update(id: scene.items[0].id) { $0.isEnabled = false }

        XCTAssertEqual(scene.sourcesInUse, [scene.items[1].id: .camera(deviceID: "a")])
    }

    func testScriptsRunOnlyWhenTheirStepComesOn() {
        var before = SceneConfiguration()
        before.add(.script(source: "beep"))
        before.add(.script(source: "say 1"))
        before.add(.effect(name: "Zoom", values: [:]))
        before.update(id: before.items[1].id) { $0.isEnabled = false }
        XCTAssertEqual(before.scriptsToRun(after: SceneConfiguration()), ["beep"])

        var after = before
        after.update(id: after.items[1].id) { $0.isEnabled = true }
        after.add(.script(source: "say 2"))
        XCTAssertEqual(after.scriptsToRun(after: before), ["say 1", "say 2"])
        XCTAssertEqual(after.scriptsToRun(after: after), [])
        XCTAssertFalse(after.items[0].isSource)
    }


}

final class SourceSettingsDefaultsTests: XCTestCase {
    func testDefaults() {
        let movie = MovieSettings()
        XCTAssertEqual(movie.files, [])
        XCTAssertNil(movie.hotFolder)
        XCTAssertEqual(movie.playMode, .playAllAndRepeat)
        XCTAssertTrue(movie.isPlaying)
        XCTAssertFalse(movie.hidesWhenStopped)
        XCTAssertFalse(movie.isMuted)
        XCTAssertEqual(movie.volume, MovieSettings.fullVolume)
        XCTAssertNil(movie.captions)
        XCTAssertNil(movie.audioDeviceID)

        let slides = SlideShowSettings()
        XCTAssertEqual(slides.delay, SlideShowSettings.defaultDelay)
        XCTAssertFalse(slides.isPaused)
        XCTAssertTrue(slides.loops)
        let old = Data(#"{"paths":["/pics"],"delay":3,"isPaused":false}"#.utf8)
        XCTAssertEqual(
            try? JSONDecoder().decode(SlideShowSettings.self, from: old), SlideShowSettings(paths: ["/pics"], delay: 3)
        )
        let once = SlideShowSettings(paths: ["/pics"], loops: false)
        XCTAssertEqual(try? JSONDecoder().decode(SlideShowSettings.self, from: JSONEncoder().encode(once)), once)

        let display = DisplaySettings(displayID: 1)
        XCTAssertEqual(display.region, .full)
        XCTAssertFalse(display.followsMouse)
        XCTAssertEqual(display.followFraction, DisplaySettings.defaultFollowFraction)
        XCTAssertTrue(display.showsCursor)

        let window = WindowSettings(titlePattern: "x")
        XCTAssertFalse(window.isRegularExpression)
        XCTAssertNil(window.applicationName)

        let words = TextSettings()
        XCTAssertEqual(words.text, TextSettings.defaultText)
        XCTAssertEqual(words.fontName, TextSettings.defaultFontName)
        XCTAssertEqual(words.color, TextSettings.defaultColor)
        XCTAssertEqual(words.fontSize, TextSettings.defaultFontSize)
        XCTAssertEqual(words.lineHeight, TextSettings.defaultLineHeight)
        XCTAssertFalse(words.hasShadow)
    }

    func testTextSavedBeforeItHadASizeGetsTheStartingValues() throws {
        let old = Data(#"{"text":"Hi","fontName":"Menlo","color":{"red":1,"green":0,"blue":0}}"#.utf8)
        let text = try JSONDecoder().decode(TextSettings.self, from: old)
        XCTAssertEqual(text, TextSettings(text: "Hi", fontName: "Menlo", color: RGBColor(red: 1, green: 0, blue: 0)))

        XCTAssertEqual(text.alignment, .center)
        let styled = TextSettings(text: "Hi", fontSize: 40, lineHeight: 2, hasShadow: true, alignment: .justified)
        let copy = try JSONDecoder().decode(TextSettings.self, from: JSONEncoder().encode(styled))
        XCTAssertEqual(copy, styled)
    }

    func testTheTelestratorStartsWithItsDefaults() {

        let telestrator = TelestratorSettings()
        XCTAssertEqual(telestrator.strokes, [])
        XCTAssertEqual(telestrator.penColor, TelestratorSettings.defaultColor)
        XCTAssertEqual(telestrator.penWidth, TelestratorSettings.defaultPenWidth)
    }
}

final class SavedDataCompatibilityTests: XCTestCase {
    func testMovieSettingsSavedBeforeTheNewerFieldsStillLoad() throws {
        let older = #"{"files":["/a.mov"],"playMode":"shuffle","isPlaying":true,"hidesWhenStopped":false,"isMuted":false,"volume":1}"#
        let settings = try JSONDecoder().decode(MovieSettings.self, from: Data(older.utf8))
        XCTAssertEqual(settings, MovieSettings(files: ["/a.mov"], playMode: .shuffle))
    }
}

final class BranchTests: XCTestCase {
    private let zoom = ChainItem(content: .effect(name: "Zoom", values: [:]))
    private let logo = ChainItem(content: .source(.image(path: "/logo.png")))
    private let script = ChainItem(content: .script(source: "beep"))

    /// Colour bars, then a camera whose branch holds an effect and a logo.
    private func branched() -> (scene: SceneConfiguration, bars: UUID, camera: UUID) {
        let bars = ChainItem(content: .source(.colorBars))
        let camera = ChainItem(
            content: .source(.camera(deviceID: "a")), pictureInPicture: PictureInPictureSettings(),
            branch: [zoom, logo]
        )
        return (SceneConfiguration(items: [bars, camera]), bars.id, camera.id)
    }

    func testStepsAreFoundWhereverTheyAre() {
        let (scene, bars, camera) = branched()
        XCTAssertEqual(scene.allItems.map(\.id), [bars, camera, zoom.id, logo.id])
        XCTAssertEqual(scene.item(id: logo.id)?.source, .image(path: "/logo.png"))
        XCTAssertNil(scene.item(id: UUID()))
    }

    func testInsertGoesIntoABranchWhenGivenAParent() {
        var (scene, bars, camera) = branched()
        scene.insert(script, before: logo.id, inBranchOf: camera)
        scene.insert(ChainItem(content: .effect(name: "Bump", values: [:])), inBranchOf: bars)
        scene.insert(ChainItem(content: .effect(name: "Lost", values: [:])), inBranchOf: UUID())

        XCTAssertEqual(scene.item(id: camera)?.branch?.map(\.id), [zoom.id, script.id, logo.id])
        XCTAssertEqual(scene.item(id: bars)?.branch?.count, 1, "a source with no branch grows one")
        XCTAssertEqual(scene.items.count, 2, "an unknown parent adds nothing")
    }

    func testNestedStepsCanBeChangedMovedAndRemoved() {
        var (scene, _, camera) = branched()

        scene.setValue(.number(3), forKey: "Scale", ofEffect: zoom.id)
        XCTAssertEqual(scene.item(id: zoom.id)?.content, .effect(name: "Zoom", values: ["Scale": .number(3)]))

        scene.move(id: logo.id, toPositionOf: zoom.id)
        XCTAssertEqual(scene.item(id: camera)?.branch?.map(\.id), [logo.id, zoom.id])
        scene.move(id: logo.id, toPositionOf: camera)
        XCTAssertEqual(scene.item(id: camera)?.branch?.map(\.id), [logo.id, zoom.id], "not across lists")

        scene.remove(id: logo.id)
        XCTAssertEqual(scene.item(id: camera)?.branch?.map(\.id), [zoom.id])
        scene.remove(id: zoom.id)
        XCTAssertNil(scene.item(id: camera)?.branch, "an emptied branch is gone")
        scene.remove(id: camera)
        XCTAssertEqual(scene.items.count, 1)
    }

    func testSourcesAndScriptsInBranchesCountOnlyWhileTheirParentIsOn() {
        var (scene, bars, camera) = branched()
        scene.insert(script, inBranchOf: camera)
        XCTAssertEqual(Set(scene.sourcesInUse.keys), [bars, camera, logo.id])
        XCTAssertEqual(scene.scriptsToRun(after: SceneConfiguration()), ["beep"])

        var off = scene
        off.update(id: camera) { $0.isEnabled = false }
        XCTAssertEqual(Set(off.sourcesInUse.keys), [bars])
        XCTAssertEqual(scene.scriptsToRun(after: off), ["beep"], "switching the parent on runs its scripts")
        XCTAssertEqual(off.scriptsToRun(after: scene), [])
    }

    func testDuplicatingCopiesTheBranchUnderNewIdentities() throws {
        let (scene, _, camera) = branched()
        let copy = try XCTUnwrap(scene.item(id: camera)).duplicated()

        XCTAssertNotEqual(copy.id, camera)
        XCTAssertEqual(copy.branch?.map(\.content), [zoom.content, logo.content])
        XCTAssertNotEqual(copy.branch?.first?.id, zoom.id)
    }

    func testAScenWithBranchesRoundTripsAndOlderScenesStillLoad() throws {
        let (scene, _, _) = branched()
        let data = try JSONEncoder().encode(scene)
        XCTAssertEqual(try JSONDecoder().decode(SceneConfiguration.self, from: data), scene)

        let older = #"{"items":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","isEnabled":true,"content":{"source":{"_0":{"colorBars":{}}}}}]}"#
        let loaded = try JSONDecoder().decode(SceneConfiguration.self, from: Data(older.utf8))
        XCTAssertNil(loaded.items.first?.branch)
    }
}
