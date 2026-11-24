import CamTwistCore
import XCTest
@testable import CamTwistControl

final class LaunchOptionsTests: XCTestCase {
    private func defaults(_ values: [String: Any]) -> UserDefaults {
        let suite = UserDefaults(suiteName: "launch-options-\(UUID().uuidString)")!
        for (key, value) in values { suite.set(value, forKey: key) }
        return suite
    }

    func testNothingSetOpensPlainly() {
        XCTAssertEqual(LaunchOptions.load(defaults: defaults([:])), LaunchOptions())
    }

    func testEachDefaultTurnsOnItsOwnOption() {
        let options = LaunchOptions.load(defaults: defaults([
            "OpenOnPane": "Output", "OpenStudioWindow": true, "OpenPicker": true, "ShowEffects": true,
            "OpenStepSettings": true, "OpenSettings": true, "OpenRecordingOptions": true, "SelectStep": 2,
            "OpenSetup": "/shows/demo.camtwisted",
        ]))
        XCTAssertEqual(options, LaunchOptions(
            pane: "Output", opensStudioWindow: true, opensPicker: true, showsEffects: true,
            opensStepSettings: true, opensSettings: true, opensRecordingOptions: true, selectedStep: 2,
            setupToOpen: URL(fileURLWithPath: "/shows/demo.camtwisted")
        ))
    }

    func testTheSelectedStepIsCountedFromOne() {
        let first = ChainItem(content: .source(.testCard))
        let second = ChainItem(content: .source(.colorBars))
        let scene = SceneConfiguration(items: [first, second])
        XCTAssertNil(LaunchOptions().stepToSelect(in: scene))
        XCTAssertEqual(LaunchOptions(selectedStep: 2).stepToSelect(in: scene), second.id)
        XCTAssertNil(LaunchOptions(selectedStep: 3).stepToSelect(in: scene))
    }

    func testSavePanelsStartWithAPlainNameWhenNothingIsOpen() {
        XCTAssertEqual(SetupFileName.suggested(forOpenFile: nil), "Untitled.camtwisted")
        XCTAssertEqual(SetupFileName.suggested(forOpenFile: "Show.camtwisted"), "Show.camtwisted")
        XCTAssertEqual(SetupFileName.fileExtension, "camtwisted")
    }
}
