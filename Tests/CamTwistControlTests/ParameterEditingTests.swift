import AppKit
import CamTwistCore
import XCTest
@testable import CamTwistControl

final class ParameterControlKindTests: XCTestCase {
    private func parameter(
        range: ClosedRange<Double>? = nil, choices: [String]? = nil, isFont: Bool = false, fileTypes: [String]? = nil
    ) -> EffectParameter {
        EffectParameter(
            key: "k", displayName: "K", kind: .string, defaultValue: .string(""), range: range, choices: choices,
            isFont: isFont, fileTypes: fileTypes
        )
    }

    func testNumbersTakeTheirOwnRangeOrTheFallback() {
        XCTAssertEqual(ParameterControlKind(parameter: parameter(range: 2...5), value: .number(3)), .number(2...5))
        XCTAssertEqual(
            ParameterControlKind(parameter: parameter(), value: .number(3)), .number(EffectParameterRange.fallback)
        )
    }

    func testBooleansAndColoursHaveTheirOwnControls() {
        XCTAssertEqual(ParameterControlKind(parameter: parameter(), value: .boolean(true)), .toggle)
        XCTAssertEqual(
            ParameterControlKind(parameter: parameter(), value: .color(red: 0, green: 0, blue: 0, alpha: 1)), .color
        )
    }

    func testTextIsAFileAFontAChoiceOrPlainText() {
        let text = EffectValue.string("x")
        XCTAssertEqual(ParameterControlKind(parameter: parameter(fileTypes: ["png"]), value: text), .file(types: ["png"]))
        XCTAssertEqual(ParameterControlKind(parameter: parameter(isFont: true), value: text), .font)
        XCTAssertEqual(ParameterControlKind(parameter: parameter(choices: ["a", "b"]), value: text), .choices(["a", "b"]))
        XCTAssertEqual(ParameterControlKind(parameter: parameter(), value: text), .text)
    }

    func testAFileSettingSaysWhatIsChosen() {
        XCTAssertEqual(FileSettingText.shown(path: ""), "None chosen")
        XCTAssertEqual(FileSettingText.shown(path: "/a/b.png"), "b.png")
        XCTAssertEqual(FileSettingText.chooseTitle(path: ""), "Choose file")
        XCTAssertEqual(FileSettingText.chooseTitle(path: "/a"), "Choose another file")
    }

    func testAPickedColourKeepsItsAlpha() {
        let value = EffectValue(picked: NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 0.5))
        guard case .color(let red, let green, let blue, let alpha) = value else { return XCTFail("not a colour") }
        XCTAssertEqual([red, green, blue, alpha].map { ($0 * 10).rounded() }, [1, 2, 3, 5])
    }

    func testAColourWithNoSRGBFormIsWhite() {
        let pattern = NSColor(patternImage: NSImage(size: NSSize(width: 1, height: 1)))
        XCTAssertEqual(EffectValue(picked: pattern), .color(red: 1, green: 1, blue: 1, alpha: 1))
    }
}

final class BranchAndPlacementEditingTests: XCTestCase {
    func testAnEmptyBranchIsStoredAsNone() {
        let item = ChainItem(content: .source(.colorBars))
        XCTAssertNil(BranchEditing.stored([]))
        XCTAssertEqual(BranchEditing.stored([item]), [item])
        XCTAssertEqual(BranchEditing.shown(nil), [])
        XCTAssertEqual(BranchEditing.shown([item]), [item])
    }

    func testThePressTogglesWhereNewStepsGo() {
        let id = UUID()
        XCTAssertEqual(BranchEditing.target(afterPressingFor: id, current: nil), id)
        XCTAssertEqual(BranchEditing.target(afterPressingFor: id, current: UUID()), id)
        XCTAssertNil(BranchEditing.target(afterPressingFor: id, current: id))
        XCTAssertEqual(BranchEditing.buttonTitle(isTarget: true, sourceTitle: "Camera"), "Stop adding here")
        XCTAssertEqual(BranchEditing.buttonTitle(isTarget: false, sourceTitle: "Camera"), "Add to Camera only")
    }

    func testPictureInPictureIsOnWhileSettingsExist() {
        XCTAssertFalse(PlacementEditing.isOn(nil))
        XCTAssertTrue(PlacementEditing.isOn(PictureInPictureSettings()))
        XCTAssertEqual(PlacementEditing.settings(whenOn: true), PictureInPictureSettings())
        XCTAssertNil(PlacementEditing.settings(whenOn: false))
    }

    func testEachPlacementSliderReadsAndWritesItsOwnSetting() {
        XCTAssertEqual(
            PlacementSlider.all.map(\.title), ["Position X", "Position Y", "Size", "Rotate", "Tilt", "Swing"]
        )
        for (index, slider) in PlacementSlider.all.enumerated() {
            var settings = PictureInPictureSettings()
            let before = settings
            let target = Double(index + 1) / 100
            slider.setValue(&settings, target)
            XCTAssertEqual(slider.value(settings), target, "\(slider.title)")
            XCTAssertNotEqual(settings, before, "\(slider.title) changed nothing")
            XCTAssertFalse(slider.range.isEmpty)
        }
    }
}
