import CamTwistCore
import XCTest
@testable import CamTwistControl

final class SetupDocumentTests: XCTestCase {
    private let coder = SetupDocumentCoder()

    private func everyKindOfStep() -> SceneConfiguration {
            let stroke = DrawingStroke(points: [CGPoint(x: 0.1, y: 0.2)], color: RGBColor(red: 1, green: 0, blue: 0), width: 0.01)
            let scene = SceneConfiguration(items: [
                ChainItem(content: .source(.camera(deviceID: "a"))),
                ChainItem(content: .source(.display(DisplaySettings(displayID: 2, followsMouse: true)))),
                ChainItem(content: .source(.window(WindowSettings(titlePattern: "Notes", isRegularExpression: true)))),
                ChainItem(content: .source(.movie(MovieSettings(
                    files: ["/a.mov"], playMode: .shuffle, captions: ["/a.mov": "Intro"],
                    audioDeviceID: "speakers"
                )))),
                ChainItem(content: .script(source: "beep")),
                ChainItem(content: .source(.testCard)),
                ChainItem(content: .source(.image(path: "/pictures/logo.png"))),
                ChainItem(content: .source(.text(TextSettings(text: "On air", fontName: "Menlo")))),
                ChainItem(content: .source(.shape(ShapeSettings(kind: .star, opacity: 0.5)))),
                ChainItem(content: .source(.slideShow(SlideShowSettings(paths: ["/pics"], delay: 3)))),
                ChainItem(content: .source(.website(url: "https://example.com"))),
                ChainItem(content: .source(.telestrator(TelestratorSettings(strokes: [stroke])))),
                ChainItem(
                    isEnabled: false, content: .source(.colorBars),
                    pictureInPicture: PictureInPictureSettings(corner: .topLeft, scale: 0.4, margin: 0.02)
                ),
                ChainItem(content: .effect(name: "Text", values: [
                    "String": .string("hello"),
                    "Shadow": .boolean(true),
                    "Font_Size": .number(0.2),
                    "Color": .color(red: 1, green: 0.5, blue: 0, alpha: 1),
                ])),
            ])
        return scene
    }

    private func document(scene: SceneConfiguration) -> SetupDocument {
        SetupDocument(
            studio: StudioSettings(buttons: [StudioButton(name: "One", scene: scene)]),
            preferences: AppPreferences(),
            windowSize: SetupWindowSize(width: 800, height: 450)
        )
    }

    func testASetupRoundTripsEveryKindOfStep() throws {
        let original = document(scene: everyKindOfStep())
        XCTAssertEqual(try coder.decode(try coder.encode(original)), original)
    }

    func testAFileIsIndentedWithSortedKeysSoSavesDiffCleanly() throws {
        let made = document(scene: .initial)
        let data = try coder.encode(made)
        XCTAssertEqual(data, try coder.encode(made))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\n  \""))
        let preferences = try XCTUnwrap(text.range(of: "\"preferences\""))
        let studio = try XCTUnwrap(text.range(of: "\"studio\""))
        XCTAssertLessThan(preferences.lowerBound, studio.lowerBound)
    }

    func testTheGlobalPreferencesAreStrippedWhenADocumentIsMade() {
        var preferences = AppPreferences()
        preferences.snapshotsFolder = "/snapshots"
        preferences.rtmp.streamKey = "secret"
        let made = SetupDocument(studio: StudioSettings(), preferences: preferences, windowSize: nil)
        XCTAssertEqual(made.version, SetupDocument.formatVersion)
        XCTAssertNil(made.preferences.snapshotsFolder)
        XCTAssertEqual(made.preferences.rtmp.streamKey, "")
    }

    func testASetupSavedWhenThePictureSizeWasChosenByHandStillOpens() throws {
        var preferences = AppPreferences()
        preferences.webMovie.isOn = true
        let made = SetupDocument(studio: StudioSettings(), preferences: preferences, windowSize: nil)
        let text = String(decoding: try coder.encode(made), as: UTF8.self)
        // The key such a file still carries, which nothing reads any more.
        let old = text.replacingOccurrences(of: "\"preferences\" : {", with: "\"preferences\" : {\n    \"drawingSize\" : \"ultraHD\",")
        XCTAssertTrue(old.contains("drawingSize"))
        XCTAssertEqual(try coder.decode(Data(old.utf8)), made)
    }

    func testAFileThatIsNotASetupIsRefused() {
        XCTAssertThrowsError(try coder.decode(Data("not json".utf8))) {
            XCTAssertEqual($0 as? SetupFileError, .notASetup)
        }
        XCTAssertThrowsError(try coder.decode(Data(#"{"name":"a recipe"}"#.utf8))) {
            XCTAssertEqual($0 as? SetupFileError, .notASetup)
        }
    }

    func testAFileWithTheRightVersionButNothingInItIsRefused() {
        XCTAssertThrowsError(try coder.decode(Data(#"{"version":1}"#.utf8))) {
            XCTAssertEqual($0 as? SetupFileError, .notASetup)
        }
    }

    func testAFileFromANewerVersionIsRefusedWithAClearMessage() {
        let data = Data(#"{"version":\#(SetupDocument.formatVersion + 1),"future":true}"#.utf8)
        XCTAssertThrowsError(try coder.decode(data)) {
            XCTAssertEqual($0 as? SetupFileError, .newerVersion)
            XCTAssertEqual($0.localizedDescription, "That setup was saved by a newer CamTwisted. Update the app to open it.")
        }
    }

    func testEveryRefusalHasAMessage() {
        XCTAssertEqual(SetupFileError.notASetup.localizedDescription, "That file is not a CamTwisted setup.")
        XCTAssertEqual(SetupFileError.noScenes.localizedDescription, "That setup has no scenes in it.")
    }

    func testTheSceneOnAirIsShownWhenOpenedAndTheFirstWhenItIsGone() {
        let bars = StudioButton(name: "Bars", scene: SceneConfiguration(items: [sourceItem(.colorBars)]))
        let card = StudioButton(name: "Card", scene: SceneConfiguration(items: [sourceItem(.testCard)]))
        var made = SetupDocument(
            studio: StudioSettings(buttons: [bars, card], onAirID: card.id), preferences: AppPreferences(), windowSize: nil
        )
        XCTAssertEqual(made.sceneToShow, card.scene)
        made.studio.onAirID = UUID()
        XCTAssertEqual(made.sceneToShow, bars.scene)
        made.studio.buttons = []
        XCTAssertNil(made.sceneToShow)
    }
}

@MainActor
final class SetupDocumentsTests: XCTestCase {
    private let state = FakeState()
    private let filing = FakeSetupFiling()
    private let windows = FakeWindows()
    private lazy var documents = SetupDocuments(state: state, filing: filing, windows: windows, coder: SetupDocumentCoder())
    private let url = URL(fileURLWithPath: "/setups/show.camtwisted")

    func testASetupWithNoScenesIsRefusedAndChangesNothing() throws {
        let empty = SetupDocument(studio: StudioSettings(), preferences: AppPreferences(), windowSize: nil)
        filing.files[url] = try SetupDocumentCoder().encode(empty)
        state.scene = SceneConfiguration(items: [sourceItem(.testCard)])
        documents.open(url)
        XCTAssertEqual(state.setupProblem, "That setup has no scenes in it.")
        XCTAssertEqual(state.scene.items.count, 1)
        XCTAssertNil(state.documentURL)
    }

    func testOpeningClosesWhateverWasBeingEdited() throws {
        let card = StudioButton(name: "Card", scene: SceneConfiguration(items: [sourceItem(.testCard)]))
        let made = SetupDocument(studio: StudioSettings(buttons: [card]), preferences: AppPreferences(), windowSize: nil)
        filing.files[url] = try SetupDocumentCoder().encode(made)
        state.editedSceneID = UUID()
        state.studioPreview = .initial
        documents.open(url)
        XCTAssertNil(state.editedSceneID)
        XCTAssertNil(state.studioPreview)
        XCTAssertEqual(state.scene, card.scene)
        XCTAssertEqual(windows.resizes, [], "a setup with no size leaves the window alone")
    }

    func testAFileThatIsNotASetupSaysSo() {
        filing.files[url] = Data("hello".utf8)
        documents.open(url)
        XCTAssertEqual(state.setupProblem, "That file is not a CamTwisted setup.")
    }

    func testStartingNewTakesAFreshSceneAndTheUsualWindow() {
        state.documentURL = url
        state.setupProblem = "old"
        documents.startNew()
        XCTAssertNil(state.documentURL)
        XCTAssertNil(state.setupProblem)
        XCTAssertTrue(state.startsAfresh)
        XCTAssertEqual(state.freshScenes, 1)
        XCTAssertEqual(windows.resetCount, 1)
    }

    func testAFreshSetupHasNothingToSaveUntilItChanges() {
        XCTAssertFalse(documents.hasUnsavedChanges, "nothing to compare with before a start")
        documents.startNew()
        XCTAssertFalse(documents.hasUnsavedChanges)
        state.studio.buttons.append(StudioButton(name: "More", scene: SceneConfiguration()))
        XCTAssertTrue(documents.hasUnsavedChanges)
    }

    func testPuttingAnotherSceneOnAirIsNotAChange() {
        let first = StudioButton(name: "One", scene: SceneConfiguration())
        state.studio = StudioSettings(buttons: [first])
        documents.markSaved()
        state.studio.onAirID = first.id
        XCTAssertFalse(documents.hasUnsavedChanges)
    }

    func testSettingsThatStayOnThisMacAreNotAChange() {
        documents.markSaved()
        state.preferences.autosaves = true
        XCTAssertFalse(documents.hasUnsavedChanges)
    }

    func testSavingAndOpeningLeaveNothingUnsaved() {
        documents.markSaved()
        state.studio.buttons.append(StudioButton(name: "Card", scene: SceneConfiguration(items: [sourceItem(.testCard)])))
        documents.save(to: url)
        XCTAssertFalse(documents.hasUnsavedChanges)
        XCTAssertEqual(documents.documentURL, url)
        state.studio.buttons = []
        documents.open(url)
        XCTAssertFalse(documents.hasUnsavedChanges)
    }

    func testAutosaveWritesAChangeOnlyWhenOnAndTheSetupHasAFile() throws {
        documents.markSaved()
        state.studio.buttons.append(StudioButton(name: "Card", scene: SceneConfiguration(items: [sourceItem(.testCard)])))
        documents.autosave()
        XCTAssertTrue(filing.files.isEmpty, "autosave is off")
        state.preferences.autosaves = true
        documents.autosave()
        XCTAssertTrue(filing.files.isEmpty, "never saved or opened, so there is no file")
        state.documentURL = url
        documents.autosave()
        XCTAssertNotNil(filing.files[url])
        XCTAssertFalse(documents.hasUnsavedChanges)
        filing.files = [:]
        documents.autosave()
        XCTAssertTrue(filing.files.isEmpty, "nothing changed since")
    }

    func testACopyOpensAsANewSetupThatNeverWritesOverTheOriginal() throws {
        let card = StudioButton(name: "Card", scene: SceneConfiguration(items: [sourceItem(.testCard)]))
        let made = SetupDocument(studio: StudioSettings(buttons: [card]), preferences: AppPreferences(), windowSize: nil)
        filing.files[url] = try SetupDocumentCoder().encode(made)
        state.preferences.autosaves = true
        documents.openCopy(of: url)
        XCTAssertEqual(state.scene, card.scene)
        XCTAssertNil(documents.documentURL, "saving asks where, like a new setup")
        XCTAssertFalse(documents.hasUnsavedChanges)
        state.studio.buttons = []
        documents.autosave()
        XCTAssertEqual(filing.files.count, 1, "autosave waits for a file of its own")
    }

    func testACopyThatCannotBeOpenedChangesNothing() {
        state.documentURL = URL(fileURLWithPath: "/setups/mine.camtwisted")
        documents.openCopy(of: url)
        XCTAssertNotNil(state.setupProblem)
        XCTAssertEqual(state.documentURL, URL(fileURLWithPath: "/setups/mine.camtwisted"))
    }
}
