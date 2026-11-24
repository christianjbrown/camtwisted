import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

/// The app has to be complete on its own: with an empty effects folder it
/// still offers every effect and transition.
final class BuiltInEffectsTests: XCTestCase {
    private let canvas = CGSize(width: 320, height: 180)
    private let tuning = EffectTuning(
        slowMotionFramesPerSecond: 12, slowMotionLongestLag: 2.5, slowMotionWidestFrame: 1280, faceFramesHeld: 10,
        characterSmoothing: 0.6, wornSmoothing: 0.85
    )

    /// A folder that exists and has nothing in it, as the effects folder is on a fresh Mac.
    private func emptyFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// Made as the app makes its libraries, over a folder with no files in it.
    private func appLibrary(folder: URL) -> CombinedEffectLibrary {
        CombinedEffectLibrary(primary: BuiltInEffects.library(directory: folder, tuning: tuning, supplies: .system()), others: [
            BuiltInEffects.transitionLibrary(directory: folder),
            makeHTMLEffectLibrary(directory: folder),
        ])
    }

    /// Effects that used to come from files and are now built in.
    private let formerEffects = [
        "Dodge bullets", "Earthquake", "Glowing Edges", "Edges", "Freeze Frame", "LetterBox", "Monochrome",
        "Frosted Glass", "Old movie", "Credits Roll", "Spinning Text", "Scrolling Text", "Snowfall", "Sobel",
        "Searchlights", "Text", "Watercolor", "Ink Noir", "Liquid Metal", "Troll", "Ablaze",
        "Goo", "Whirlpool", "Colour Burst",
        "Bump", "Clock", "ComicBook", "Countdown", "Halo", "Mirror", "Dodgy Signal", "Charcoal sketch",
        "Thought bubble",
    ]
    private let formerTransitions = ["CopyMachine", "Dip", "Dissolve", "Flash", "Mod", "PageCurl", "Ripple", "Swipe"]

    func testWithNoEffectFilesEveryEffectAndTransitionIsStillOffered() throws {
        let library = appLibrary(folder: try emptyFolder())
        let listed = Dictionary(uniqueKeysWithValues: library.availableEffects().map { ($0.name, $0.kind) })
        for name in formerEffects {
            XCTAssertNotNil(listed[name], "\(name) is offered")
            XCTAssertNotEqual(listed[name], .transition, name)
        }
        for name in formerTransitions { XCTAssertEqual(listed[name], .transition, name) }
    }

    func testWithNoEffectFilesEveryEffectCanBeMadeAndRun() throws {
        let library = appLibrary(folder: try emptyFolder())
        let scene = EffectThumbnailer.sampleScene(size: canvas)
        for listing in library.availableEffects() where listing.kind != .transition {
            let effect = try XCTUnwrap(library.makeEffect(named: listing.name, canvas: canvas), listing.name)
            effect.setValues(EffectStartingValues.values(for: library.parameters(forEffectNamed: listing.name)))
            XCTAssertFalse(effect.apply(to: scene, time: 0.5).extent.isEmpty, listing.name)
        }
    }

    func testAnEffectIsKnownByItsName() {
        XCTAssertEqual(EffectListing(name: "Blur", kind: .filter).id, "Blur")
    }

    func testWithNoEffectFilesEveryTransitionCanBeMade() throws {
        let transitions = BuiltInEffects.transitionLibrary(directory: try emptyFolder())
        for name in formerTransitions { XCTAssertNotNil(transitions.makeTransition(named: name, canvas: canvas), name) }
    }

    func testTheEffectPickerThumbnailsEveryBuiltInEffectAndTransition() throws {
        let folder = try emptyFolder()
        let library = appLibrary(folder: folder)
        let transitions = BuiltInEffects.transitionLibrary(directory: folder)
        let thumbnailer = EffectThumbnailer(factory: library, transitions: transitions, size: canvas)
        for name in formerEffects { XCTAssertNotNil(thumbnailer.thumbnail(forEffectNamed: name), name) }
        for name in formerTransitions { XCTAssertNotNil(thumbnailer.thumbnail(forTransitionNamed: name), name) }
    }

    func testTheLibraryShowsTheFolderItWasGiven() throws {
        let folder = try emptyFolder()
        XCTAssertEqual(BuiltInEffects.library(directory: folder, tuning: tuning, supplies: .system()).directory, folder)
    }
}

final class RenderingSuppliesTests: XCTestCase {
    func testTheSystemSuppliesAreTheSystemsOwn() {
        let supplies = RenderingSupplies.system()

        XCTAssertTrue(supplies.pixels is CoreImagePixelAccess)
        XCTAssertNotEqual(supplies.seed(), 0)
        XCTAssertLessThan(abs(supplies.now().timeIntervalSinceNow), 5)
        XCTAssertTrue(supplies.makeMasker() is VisionPersonMasker)
        XCTAssertTrue(supplies.makeFaceTracker() is VisionFaceTracker)
    }
}
