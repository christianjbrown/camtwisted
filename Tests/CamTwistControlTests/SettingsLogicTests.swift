import AppKit
import CamTwistCore
import XCTest
@testable import CamTwistControl
@testable import CamTwistRendering

final class SettingsLabelTests: XCTestCase {
    func testEveryChoiceHasItsOwnLabel() {
        XCTAssertEqual(Set(MoviePlayMode.allCases.map(\.label)), [
            "Play all and stop", "Play one and repeat", "Play one and stop", "Play all and repeat", "Shuffle",
        ])
        XCTAssertEqual(Set(CamTwistCore.TextAlignment.allCases.map(\.label)), ["Left", "Centre", "Right", "Justify"])
        XCTAssertEqual(
            Set(AnimatedProperty.allCases.map(\.label)),
            ["Position X", "Position Y", "Size", "Rotate", "Tilt", "Swing"]
        )
        XCTAssertEqual(
            Set(AnimationMode.allCases.map(\.label)), ["Stop at the end", "Start again", "Go back and forth"]
        )
        XCTAssertEqual(
            Set(Corner.allCases.map(\.label)), ["Top left", "Top right", "Bottom left", "Bottom right"]
        )
    }
}

final class DisplayRegionEditingTests: XCTestCase {
    func testFullScreenSwitchesBetweenTheWholeScreenAndTheCentreHalf() {
        XCTAssertTrue(DisplayRegionEditing.isFull(.full))
        XCTAssertFalse(DisplayRegionEditing.isFull(DisplayRegionEditing.centreHalf))
        XCTAssertEqual(DisplayRegionEditing.region(whenFull: true), .full)
        XCTAssertEqual(DisplayRegionEditing.region(whenFull: false), DisplayRegionEditing.centreHalf)
    }

    func testEachEdgeStaysOnTheScreen() {
        let region = UnitRect(x: 0.2, y: 0.3, width: 0.5, height: 0.4)
        XCTAssertEqual(DisplayRegionEditing.leftRange(region), 0...0.5)
        XCTAssertEqual(DisplayRegionEditing.bottomRange(region), 0...0.6)
        XCTAssertEqual(DisplayRegionEditing.widthRange(region), 0.05...0.8)
        XCTAssertEqual(DisplayRegionEditing.heightRange(region), 0.05...0.7)
    }
}

final class WindowSettingsEditingTests: XCTestCase {
    func testChoosingAWindowFixesItsTitleAndApplication() {
        let settings = WindowSettings(choosing: WindowChoice(title: "Notes", application: "Pages"))
        XCTAssertEqual(settings, WindowSettings(titlePattern: "Notes", isRegularExpression: false, applicationName: "Pages"))
        XCTAssertEqual(WindowChoice(title: "Notes", application: "Pages").menuTitle, "Pages: Notes")
    }

    func testTheApplicationFilterIsTypedAsTextAndEmptyMeansNone() {
        var settings = WindowSettings(titlePattern: "")
        XCTAssertEqual(settings.applicationText, "")
        settings.applicationText = "Pages"
        XCTAssertEqual(settings.applicationName, "Pages")
        settings.applicationText = ""
        XCTAssertNil(settings.applicationName)
    }

    func testTheMenuOffersAnotherWindowOnceOneIsChosen() {
        XCTAssertEqual(WindowSettings(titlePattern: "").chooserTitle, "Choose a window")
        XCTAssertEqual(WindowSettings(titlePattern: "x").chooserTitle, "Choose another window")
    }
}

final class MovieSettingsEditingTests: XCTestCase {
    func testCaptionsAreKeptByFileAndDroppedWhenEmpty() {
        var settings = MovieSettings(files: ["/a.mov", "/b.mov"])
        XCTAssertEqual(settings.captionText(for: "/a.mov"), "")
        settings.setCaption("Intro", for: "/a.mov")
        XCTAssertEqual(settings.captionText(for: "/a.mov"), "Intro")
        settings.setCaption("Outro", for: "/b.mov")
        settings.setCaption("", for: "/a.mov")
        XCTAssertEqual(settings.captions, ["/b.mov": "Outro"])
        settings.setCaption("", for: "/b.mov")
        XCTAssertNil(settings.captions)
    }

    func testRemovingAFileTakesItsCaptionToo() {
        var settings = MovieSettings(files: ["/a.mov", "/b.mov"], captions: ["/a.mov": "Intro"])
        settings.remove(file: "/a.mov")
        XCTAssertEqual(settings.files, ["/b.mov"])
        XCTAssertEqual(settings.captions, [:])
        var bare = MovieSettings(files: ["/a.mov"])
        bare.remove(file: "/a.mov")
        XCTAssertNil(bare.captions)
    }

    func testAddingFilesSkipsOnesAlreadyThere() {
        var settings = MovieSettings(files: ["/a.mov"])
        settings.add(files: ["/a.mov", "/b.mov"])
        XCTAssertEqual(settings.files, ["/a.mov", "/b.mov"])
    }

    func testTheHotFolderButtonSelectsOrClears() {
        var settings = MovieSettings()
        XCTAssertEqual(settings.hotFolderButtonTitle, "Select hot folder")
        settings.toggleHotFolder { "/clips" }
        XCTAssertEqual(settings.hotFolder, "/clips")
        XCTAssertEqual(settings.hotFolderButtonTitle, "Clear hot folder")
        settings.toggleHotFolder { XCTFail("clearing needs no choice"); return nil }
        XCTAssertNil(settings.hotFolder)
        settings.toggleHotFolder { nil }
        XCTAssertNil(settings.hotFolder)
    }

    func testTheAudioOutputPickerStoresTheDefaultAsNothing() {
        var settings = MovieSettings()
        XCTAssertEqual(settings.audioDeviceChoice, MovieSettings.systemDefaultDevice)
        settings.audioDeviceChoice = "speakers"
        XCTAssertEqual(settings.audioDeviceID, "speakers")
        XCTAssertEqual(settings.audioDeviceChoice, "speakers")
        settings.audioDeviceChoice = MovieSettings.systemDefaultDevice
        XCTAssertNil(settings.audioDeviceID)
    }
}

final class SlideShowAndImageEditingTests: XCTestCase {
    func testAddingPathsSkipsOnesAlreadyThere() {
        var settings = SlideShowSettings(paths: ["/a"])
        settings.add(paths: ["/a", "/b"])
        XCTAssertEqual(settings.paths, ["/a", "/b"])
    }

    func testTheImageButtonOffersAnotherOnceOneIsChosen() {
        XCTAssertEqual(ImageSourceText.chooseButtonTitle(path: ""), "Choose image")
        XCTAssertEqual(ImageSourceText.chooseButtonTitle(path: "/a.png"), "Choose another image")
    }
}

final class PickedColorTests: XCTestCase {
    func testAColorIsReadInSRGB() {
        let color = RGBColor(picked: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1), fallback: RGBColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(color.red, 0.2, accuracy: 0.001)
        XCTAssertEqual(color.green, 0.4, accuracy: 0.001)
        XCTAssertEqual(color.blue, 0.6, accuracy: 0.001)
    }

    func testAColorWithNoSRGBFormTakesTheFallback() {
        let pattern = NSColor(patternImage: NSImage(size: NSSize(width: 1, height: 1)))
        let color = RGBColor(picked: pattern, fallback: RGBColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(color, RGBColor(red: 1, green: 0, blue: 0))
    }

    func testTheWellShowsTheColorOpaque() {
        let well = RGBColor(red: 0.1, green: 0.2, blue: 0.3).wellColor
        XCTAssertEqual(well.alphaComponent, 1)
        XCTAssertEqual(well.greenComponent, 0.2, accuracy: 0.001)
    }
}
