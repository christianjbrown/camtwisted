import XCTest
@testable import CamTwistCore

final class EffectParameterRangeTests: XCTestCase {
    func testAControlWithNoLimitsRunsFromNoneToAll() {
        XCTAssertEqual(EffectParameterRange.fallback, 0...1)
    }
}

final class EffectStartingValuesTests: XCTestCase {
    private func parameter(_ key: String, _ kind: EffectParameterKind, _ value: EffectValue) -> EffectParameter {
        EffectParameter(key: key, displayName: key, kind: kind, defaultValue: value)
    }

    func testShadowsStartSwitchedOffAndNothingElseIsTouched() {
        let values = EffectStartingValues.values(for: [
            parameter("Shadow", .color, .color(red: 0, green: 0, blue: 0, alpha: 1)),
            parameter("Shadow_Offset", .number, .number(0.02)),
            parameter("Temp_Shadow", .boolean, .boolean(true)),
            parameter("Shadow_Name", .string, .string("soft")),
            parameter("Color", .color, .color(red: 1, green: 1, blue: 1, alpha: 1)),
            parameter("Font_Size", .number, .number(0.1)),
        ])

        XCTAssertEqual(values, [
            "Shadow": .color(red: 0, green: 0, blue: 0, alpha: 0),
            "Shadow_Offset": .number(0),
            "Temp_Shadow": .boolean(false),
        ])
    }
}

final class EffectParameterTests: XCTestCase {
    func testIdentityIsTheKey() {
        let parameter = EffectParameter(
            key: "Radius", displayName: "Radius", kind: .number, defaultValue: .number(2), range: 0...10
        )
        XCTAssertEqual(parameter.id, "Radius")
        XCTAssertEqual(parameter.range, 0...10)
        XCTAssertNil(EffectParameter(key: "On", displayName: "On", kind: .boolean, defaultValue: .boolean(true)).range)
    }
}

private struct StubListing: DirectoryListing {
    let result: Result<[URL], Error>

    func files(in directory: URL) throws -> [URL] {
        try result.get()
    }
}

private struct ListingFailure: Error {}

final class PictureCatalogTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/pictures")

    func testListsPicturesByNameAndSkipsEverythingElse() {
        let files = ["Zebra.png", "apple.JPG", "notes.txt", "clip.mov"].map { folder.appendingPathComponent($0) }
        let catalog = PictureCatalog(listing: StubListing(result: .success(files)))

        let pictures = catalog.pictures(in: folder)

        XCTAssertEqual(pictures.map(\.name), ["apple", "Zebra"])
        XCTAssertEqual(pictures.first?.path, "/pictures/apple.JPG")
        XCTAssertEqual(pictures.first?.id, "/pictures/apple.JPG")
    }

    func testAMissingFolderHasNoPictures() {
        let catalog = PictureCatalog(listing: StubListing(result: .failure(ListingFailure())))
        XCTAssertEqual(catalog.pictures(in: folder), [])
        XCTAssertEqual(PictureCatalog(listing: FileManagerDirectoryListing()).pictures(in: URL(fileURLWithPath: "/no/such/folder")), [])
    }
}

final class EffectCatalogTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/effects")

    func testListsEffectFilesSortedWithoutBackups() {
        let files = ["Zoom.html", "clock.HTML", "Clock~.html", "Bump.html", "notes.txt", "Flame.bundle"]
            .map { folder.appendingPathComponent($0) }
        let catalog = EffectCatalog(
            listing: StubListing(result: .success(files)), fileExtension: EffectCatalog.webPageExtension
        )

        let effects = catalog.effects(in: folder)

        XCTAssertEqual(effects.map(\.name), ["Bump", "clock", "Zoom"])
        XCTAssertEqual(effects.map(\.id), ["Bump", "clock", "Zoom"])
        XCTAssertEqual(effects.first?.url, folder.appendingPathComponent("Bump.html"))
    }

    func testAnotherFileTypeCanBeAskedFor() {
        let files = ["Zoom.html", "Ticker.page"].map { folder.appendingPathComponent($0) }
        let catalog = EffectCatalog(listing: StubListing(result: .success(files)), fileExtension: "page")
        XCTAssertEqual(catalog.effects(in: folder).map(\.name), ["Ticker"])
    }

    func testMissingFolderIsEmpty() {
        let catalog = EffectCatalog(listing: StubListing(result: .failure(ListingFailure())), fileExtension: "page")
        XCTAssertEqual(catalog.effects(in: folder), [])
    }

    func testRealListingReadsADirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appendingPathComponent("Ripple.page"))
        try Data().write(to: directory.appendingPathComponent(".hidden.page"))

        XCTAssertEqual(EffectCatalog(listing: FileManagerDirectoryListing(), fileExtension: "page").effects(in: directory).map(\.name), ["Ripple"])
    }
}

final class EffectCreditsTests: XCTestCase {
    func testEffectsThatFollowOtherWorkAreCredited() {
        XCTAssertEqual(EffectCredits.credit(forEffectNamed: "Flame")?.contains("xflame"), true)
        XCTAssertEqual(EffectCredits.credit(forEffectNamed: "Matrix")?.contains("Monji Kimura"), true)
    }

    func testOtherEffectsHaveNoCredit() {
        XCTAssertNil(EffectCredits.credit(forEffectNamed: "Monochrome"))
        XCTAssertNil(EffectCredits.credit(forEffectNamed: ""))
    }
}

final class EffectNamingTests: XCTestCase {
    private func name(_ original: String) -> String {
        EffectNaming.title(for: original)
    }

    func testPlainNamesAreLeftAlone() {
        XCTAssertEqual(name("Monochrome"), "Monochrome")
        XCTAssertEqual(name("Freeze Frame"), "Freeze Frame")
        XCTAssertEqual(name("RSS Reader"), "RSS Reader")
        XCTAssertEqual(name("PillarBox"), "Pillarbox")
        XCTAssertEqual(name("Mirror"), "Mirror")
    }

    func testVersionNumbersAndRunTogetherWordsAreTidied() {
        XCTAssertEqual(name("BulletHole"), "Bullet Hole")
        XCTAssertEqual(name("PageCurl"), "Page Curl")
        XCTAssertEqual(name("Old movie"), "Old movie")
        XCTAssertEqual(name("some_thing_2.5"), "Some Thing")
        XCTAssertEqual(name("quiet"), "Quiet")
        XCTAssertEqual(name("Dodgy Signal"), "Dodgy Signal")
    }

    func testAwkwardNamesHaveTheirOwnWording() {
        XCTAssertEqual(name("Mod"), "Mod Wipe")
        XCTAssertEqual(name("Sobel"), "Sobel Edges")
        XCTAssertEqual(name("Dip"), "Dip to Colour")
    }

    func testANameWithNothingLeftIsKept() {
        XCTAssertEqual(name("_"), "_")
        XCTAssertEqual(name(""), "")
    }
}

final class SourceCutoutTests: XCTestCase {
    func testACutoutThatCutsNothingIsNeutral() {
        XCTAssertTrue(SourceCutout().isNeutral)
        XCTAssertFalse(SourceCutout(removesBackground: true).isNeutral)
        XCTAssertFalse(SourceCutout(chromaKey: .greenScreen).isNeutral)
        XCTAssertEqual(ChromaKeySettings.greenScreen.green, 1)
        XCTAssertEqual(ChromaKeySettings.range, 0...1)
    }

    func testOnlyPicturesFromOutsideCanBeCutOut() {
        let can: [SourceSpec] = [
            .camera(deviceID: "cam"), .display(DisplaySettings(displayID: 1)), .window(WindowSettings(titlePattern: "")),
            .movie(MovieSettings()), .slideShow(SlideShowSettings()), .website(url: ""), .stream(StreamSettings()),
            .image(path: ""),
        ]
        let cannot: [SourceSpec] = [
            .microphone(deviceID: nil), .telestrator(TelestratorSettings()), .colorBars, .testCard,
            .shape(ShapeSettings()), .text(TextSettings()),
        ]
        XCTAssertTrue(can.allSatisfy(\.canBeCutOut))
        XCTAssertFalse(cannot.contains(where: \.canBeCutOut))
    }

    func testASceneKnowsWhetherItHasACameraEvenInABranch() {
        let camera = ChainItem(content: .source(.camera(deviceID: "cam")))
        XCTAssertFalse(SceneConfiguration(items: [ChainItem(content: .source(.colorBars))]).hasCamera)
        XCTAssertTrue(SceneConfiguration(items: [camera]).hasCamera)
        XCTAssertTrue(SceneConfiguration(items: [ChainItem(content: .source(.colorBars), branch: [camera])]).hasCamera)
        XCTAssertFalse(SceneConfiguration(items: [ChainItem(content: .effect(name: "Blur", values: [:]))]).hasCamera)
    }

    func testACopyOfAStepKeepsItsVolumeAndItsCutout() {
        let step = ChainItem(
            content: .source(.camera(deviceID: "cam")), volume: 0.4,
            cutout: SourceCutout(removesBackground: true, chromaKey: .greenScreen)
        )
        let copy = step.duplicated()
        XCTAssertNotEqual(copy.id, step.id)
        XCTAssertEqual(copy.volume, 0.4)
        XCTAssertEqual(copy.cutout, step.cutout)
    }
}
