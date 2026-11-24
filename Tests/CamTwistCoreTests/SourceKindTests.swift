import XCTest
@testable import CamTwistCore

/// What is there, as a test says it is.
private struct Available: SourceAvailability {
    var cameras: Set<String> = []
    var screens: Set<UInt32> = []
    var microphones: Set<String> = []
    var files: Set<String> = []

    func hasCamera(_ deviceID: String) -> Bool { cameras.contains(deviceID) }
    func hasScreen(_ displayID: UInt32) -> Bool { screens.contains(displayID) }
    func hasMicrophone(_ deviceID: String) -> Bool { microphones.contains(deviceID) }
    func hasFile(atPath path: String) -> Bool { files.contains(path) }
}

final class SourceKindTests: XCTestCase {
    private let nothing = Available()

    func testEveryKindOfSourceHasItsOwnTitle() {
        XCTAssertEqual(SourceSpec.camera(deviceID: "cam").kind.title, "Camera")
        XCTAssertEqual(SourceSpec.display(DisplaySettings(displayID: 1)).kind.title, "Screen")
        XCTAssertEqual(SourceSpec.window(WindowSettings(titlePattern: "")).kind.title, "Window")
        XCTAssertEqual(SourceSpec.window(WindowSettings(titlePattern: "Notes")).kind.title, "Window: Notes")
        XCTAssertEqual(SourceSpec.movie(MovieSettings()).kind.title, "Video")
        XCTAssertEqual(SourceSpec.slideShow(SlideShowSettings()).kind.title, "Slide show")
        XCTAssertEqual(SourceSpec.website(url: "https://example.com").kind.title, "Website")
        XCTAssertEqual(SourceSpec.stream(StreamSettings()).kind.title, "Stream")
        XCTAssertEqual(SourceSpec.vnc(VNCSettings()).kind.title, "Another computer")
        XCTAssertEqual(SourceSpec.vnc(VNCSettings(address: "studio.example:5901")).kind.title, "Computer: studio.example")
        XCTAssertEqual(SourceSpec.microphone(deviceID: nil).kind.title, "Microphone")
        XCTAssertEqual(SourceSpec.telestrator(TelestratorSettings()).kind.title, "Telestrator")
        XCTAssertEqual(SourceSpec.colorBars.kind.title, "Colour bars")
        XCTAssertEqual(SourceSpec.testCard.kind.title, "Test card")
        XCTAssertEqual(SourceSpec.image(path: "").kind.title, "Image")
        XCTAssertEqual(SourceSpec.image(path: "/pictures/logo.png").kind.title, "Image: logo.png")
        XCTAssertEqual(SourceSpec.text(TextSettings(text: "Hello\nthere")).kind.title, "Text: Hello")
        XCTAssertEqual(SourceSpec.text(TextSettings(text: "")).kind.title, "Text: ")
        XCTAssertEqual(SourceSpec.shape(ShapeSettings(kind: .star)).kind.title, "Shape: Star")
    }

    func testADeviceThatIsNotConnectedIsMissing() {
        let connected = Available(cameras: ["cam"], screens: [7], microphones: ["mic"])
        XCTAssertNil(SourceSpec.camera(deviceID: "cam").kind.problem(given: connected))
        XCTAssertEqual(
            SourceSpec.camera(deviceID: "cam").kind.problem(given: nothing),
            "This camera is not connected. Choose another."
        )
        let screen = SourceSpec.display(DisplaySettings(displayID: 7))
        XCTAssertNil(screen.kind.problem(given: connected))
        XCTAssertEqual(screen.kind.problem(given: nothing), "This screen is not connected. Choose another.")
        XCTAssertNil(SourceSpec.microphone(deviceID: "mic").kind.problem(given: connected))
        XCTAssertEqual(
            SourceSpec.microphone(deviceID: "mic").kind.problem(given: nothing),
            "This microphone is not connected. Choose another."
        )
        XCTAssertNil(SourceSpec.microphone(deviceID: nil).kind.problem(given: nothing), "the system's own choice")
    }

    func testAFileThatHasGoneIsMissing() {
        let there = Available(files: ["/a.png", "/a.mov", "/slides"])
        XCTAssertNil(SourceSpec.image(path: "").kind.problem(given: nothing), "none chosen yet is not one gone")
        XCTAssertNil(SourceSpec.image(path: "/a.png").kind.problem(given: there))
        XCTAssertEqual(
            SourceSpec.image(path: "/a.png").kind.problem(given: nothing),
            "This picture's file has moved or gone. Choose it again."
        )
        XCTAssertNil(SourceSpec.movie(MovieSettings(files: ["/a.mov"])).kind.problem(given: there))
        XCTAssertEqual(
            SourceSpec.movie(MovieSettings(files: ["/a.mov", "/b.mov"])).kind.problem(given: there),
            "A video's file has moved or gone. Choose it again."
        )
        XCTAssertNil(SourceSpec.slideShow(SlideShowSettings(paths: ["/slides"])).kind.problem(given: there))
        XCTAssertEqual(
            SourceSpec.slideShow(SlideShowSettings(paths: ["/gone"])).kind.problem(given: there),
            "A picture or folder in this show has moved or gone. Choose it again."
        )
    }

    func testSourcesThatNeedNothingFromOutsideAreNeverMissing() {
        let specs: [SourceSpec] = [
            .window(WindowSettings(titlePattern: "")), .website(url: ""), .stream(StreamSettings()),
            .vnc(VNCSettings()), .telestrator(TelestratorSettings()), .colorBars, .testCard,
            .text(TextSettings()), .shape(ShapeSettings()),
        ]
        for spec in specs {
            XCTAssertNil(spec.kind.problem(given: nothing), spec.kind.title)
        }
    }

    func testAResetKeepsTheWordsOfATextAndTheKindOfAShape() {
        let text = SourceSpec.text(TextSettings(text: "Hello", fontSize: 30, hasShadow: true))
        XCTAssertEqual(text.withSettingsReset, .text(TextSettings(text: "Hello")))
        let shape = SourceSpec.shape(ShapeSettings(kind: .circle, opacity: 0.2))
        XCTAssertEqual(shape.withSettingsReset, .shape(ShapeSettings(kind: .circle)))
        let movie = SourceSpec.movie(MovieSettings(files: ["/a.mov"], isMuted: true))
        XCTAssertNil(movie.kind.settingsReset, "its settings are all about what it shows")
        XCTAssertEqual(movie.withSettingsReset, movie)
    }

    func testTextAndShapesStartInTheMiddleAndTheRestFillThePicture() {
        let middle = CGPoint(x: 0.5, y: 0.5)
        XCTAssertEqual(
            SourceSpec.text(TextSettings()).kind.startingPlacement, PictureInPictureSettings(center: middle, scale: 1)
        )
        XCTAssertEqual(SourceSpec.shape(ShapeSettings()).kind.startingPlacement, PictureInPictureSettings(center: middle))
        XCTAssertNil(SourceSpec.colorBars.kind.startingPlacement)
    }

    func testOnlyAMicrophoneHasNoPicture() {
        XCTAssertTrue(SourceSpec.microphone(deviceID: nil).kind.isSoundOnly)
        XCTAssertFalse(SourceSpec.colorBars.kind.isSoundOnly)
    }

    func testTheVolumeHelpSaysWhatIsHeard() {
        XCTAssertTrue(SourceSpec.display(DisplaySettings(displayID: 1)).kind.volumeHelp.contains("this Mac is playing"))
        XCTAssertTrue(
            SourceSpec.window(WindowSettings(titlePattern: "")).kind.volumeHelp.contains("this window belongs to")
        )
        XCTAssertTrue(SourceSpec.camera(deviceID: "cam").kind.volumeHelp.contains("virtual microphone"))
    }

    func testEveryShapeHasAName() {
        XCTAssertEqual(
            ShapeKind.allCases.map { ShapeOutlines.outline(for: $0).name },
            ["Rectangle", "Square", "Circle", "Ellipse", "Triangle", "Diamond", "Star"]
        )
    }

    /// One source of every kind, with what each answers about its picture and its sound.
    private static let everyKind: [(spec: SourceSpec, canBeCutOut: Bool, startingVolume: Double?, level: Double?)] = [
        (.camera(deviceID: "a"), true, SceneSound.full, stepVolume),
        (.display(DisplaySettings(displayID: 1)), true, SceneSound.silent, stepVolume),
        (.window(WindowSettings(titlePattern: "")), true, SceneSound.silent, stepVolume),
        (.movie(MovieSettings(volume: ownVolume)), true, nil, ownVolume),
        (.slideShow(SlideShowSettings()), true, nil, nil),
        (.website(url: ""), true, nil, nil),
        (.stream(StreamSettings(address: "", volume: ownVolume)), true, nil, ownVolume),
        (.vnc(VNCSettings()), true, nil, nil),
        (.microphone(deviceID: nil), false, SceneSound.full, stepVolume),
        (.telestrator(TelestratorSettings()), false, nil, nil),
        (.colorBars, false, nil, nil),
        (.testCard, false, nil, nil),
        (.image(path: ""), true, nil, nil),
        (.text(TextSettings()), false, nil, nil),
        (.shape(ShapeSettings()), false, nil, nil),
    ]
    /// A volume set on a step, and one a video or stream carries itself.
    private static let stepVolume = 0.4
    private static let ownVolume = 0.7

    func testEveryKindSaysWhetherItsBackgroundCanBeTakenAway() {
        for kind in Self.everyKind {
            XCTAssertEqual(kind.spec.kind.canBeCutOut, kind.canBeCutOut, "\(kind.spec)")
            XCTAssertEqual(kind.spec.canBeCutOut, kind.canBeCutOut, "\(kind.spec)")
        }
    }

    func testEveryKindSaysHowLoudItStartsAndHowLoudItIs() {
        for kind in Self.everyKind {
            XCTAssertEqual(kind.spec.kind.startingVolume, kind.startingVolume, "\(kind.spec)")
            XCTAssertEqual(kind.spec.kind.level(stepVolume: Self.stepVolume), kind.level, "\(kind.spec)")
        }
    }

    func testASourceWithNoVolumeSetOnItsStepIsAsLoudAsItStarts() {
        XCTAssertEqual(SourceSpec.camera(deviceID: "a").kind.level(stepVolume: nil), SceneSound.full)
        XCTAssertEqual(SourceSpec.display(DisplaySettings(displayID: 1)).kind.level(stepVolume: nil), SceneSound.silent)
    }

    func testOnlyACameraIsACamera() {
        for kind in Self.everyKind {
            XCTAssertEqual(kind.spec.kind.isCamera, kind.spec == .camera(deviceID: "a"), "\(kind.spec)")
        }
    }

    func testAMutedVideoIsSilent() {
        let muted = SourceSpec.movie(MovieSettings(isMuted: true, volume: Self.ownVolume))
        XCTAssertEqual(muted.kind.level(stepVolume: Self.stepVolume), SceneSound.silent)
    }
}
