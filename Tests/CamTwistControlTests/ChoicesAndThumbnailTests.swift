import CamTwistCore
import XCTest
@testable import CamTwistRendering
@testable import CamTwistControl

final class EffectParametersTests: XCTestCase {
    func testAnswersAreAskedOfTheLibraryOnlyOnce() {
        let library = FakeEffectLibrary()
        library.controls = ["Blur": [numberControl("amount", name: "Amount")]]
        let parameters = EffectParameters(library: library)
        XCTAssertEqual(parameters.parameters(forEffectNamed: "Blur").count, 1)
        XCTAssertEqual(parameters.parameters(forEffectNamed: "Blur").count, 1)
        XCTAssertEqual(library.parameterRequests, ["Blur"])
    }

    func testAnEmptyAnswerIsAskedAgainNextTime() {
        let library = FakeEffectLibrary()
        let parameters = EffectParameters(library: library)
        XCTAssertTrue(parameters.parameters(forEffectNamed: "Late").isEmpty)
        library.controls = ["Late": [numberControl("amount", name: "Amount")]]
        XCTAssertEqual(parameters.parameters(forEffectNamed: "Late").count, 1)
        XCTAssertEqual(library.parameterRequests, ["Late", "Late"])
    }
}

final class ChoiceCatalogTests: XCTestCase {
    func testEverythingToPickFromIsGathered() {
        let devices = FakeSourceChoices()
        devices.cameraList = [CameraChoice(id: "cam", name: "Camera")]
        devices.displayList = [DisplayChoice(id: 1, name: "Main")]
        devices.windowList = [WindowChoice(title: "Doc", application: "Editor")]
        devices.audioList = [AudioDeviceChoice(id: "out", name: "Speakers")]
        let library = FakeEffectLibrary()
        library.listings = [EffectListing(name: "Blur", kind: .filter), EffectListing(name: "Glow", kind: .filter)]
        let pictures = PictureCatalog(listing: FakeDirectoryListing(urlsByDirectory: [
            "/p": [URL(fileURLWithPath: "/p/cat.png"), URL(fileURLWithPath: "/p/test-card.png")],
            "/app": [URL(fileURLWithPath: "/app/test-card.png"), URL(fileURLWithPath: "/app/dog.png")],
        ]))

        let choices = ChoiceCatalog(
            devices: devices, pictures: pictures,
            picturesDirectories: [URL(fileURLWithPath: "/p"), URL(fileURLWithPath: "/app")],
            effectLibrary: library
        ).current()

        XCTAssertEqual(choices.cameras, devices.cameraList)
        XCTAssertEqual(choices.displays, devices.displayList)
        XCTAssertEqual(choices.windows, devices.windowList)
        XCTAssertEqual(choices.audioOutputs, devices.audioList)
        // The person's own test card stands in for the app's.
        XCTAssertEqual(choices.savedPictures.map(\.path), ["/p/cat.png", "/p/test-card.png", "/app/dog.png"])
        XCTAssertEqual(choices.effects.map(\.name), ["Blur", "Glow"])
    }
}

final class EffectMenuTests: XCTestCase {
    private let listings = [
        EffectListing(name: "Blur", kind: .filter),
        EffectListing(name: "Wipe", kind: .transition),
        EffectListing(name: "Dissolve", kind: .transition),
        EffectListing(name: StudioSettings.cutName, kind: .transition),
    ]

    func testTransitionsStartWithCutAndDissolveThenTheFolderOnes() {
        XCTAssertEqual(
            EffectMenu().transitionNames(from: listings),
            [StudioSettings.cutName, DissolveTransition.name, "Wipe"]
        )
    }

    func testEffectsCanBeListedByKind() {
        XCTAssertEqual(EffectMenu().effects(of: .filter, in: listings).map(\.name), ["Blur"])
    }
}

@MainActor
final class ThumbnailLoaderTests: XCTestCase {
    func testEachEffectIsAskedForOnceAndOnlyFinishedPicturesAreHandedOver() {
        let thumbnailer = FakeEffectThumbnailer()
        thumbnailer.images = ["Blur": makeImage()]
        var ready: [String] = []
        let loader = ThumbnailLoader(thumbnailer: thumbnailer, queue: ImmediateQueue()) { name, _ in
            ready.append(name)
        }
        thumbnailer.images["Swipe"] = makeImage()
        loader.requestMissing(among: ["Blur", "Glow"], transitions: ["Swipe"])
        loader.requestMissing(among: ["Blur", "Glow", "Wipe"], transitions: ["Swipe", "Cut"])
        loader.requestMissing(among: [], transitions: [])
        XCTAssertEqual(thumbnailer.asked, ["Blur", "Glow", "Wipe"])
        XCTAssertEqual(thumbnailer.askedTransitions, ["Swipe", "Cut"])
        XCTAssertEqual(ready, ["Blur", "Swipe"])
    }
}
