import CamTwistCore
import XCTest
@testable import CamTwistControl

final class NeutralStorableTests: XCTestCase {
    func testEditingFromNothingStoresTheChange() {
        let stored = SourceAdjustments.stored(afterEditing: nil) { $0.brightness = 0.3 }
        XCTAssertEqual(stored?.brightness, 0.3)
    }

    func testEditingBackToUntouchedStoresNothing() {
        var adjusted = SourceAdjustments()
        adjusted.zoom = 1.5
        XCTAssertNil(SourceAdjustments.stored(afterEditing: adjusted) { $0 = SourceAdjustments() })
    }

    func testACutoutThatCutsNothingIsStoredAsNothing() {
        let cut = SourceCutout.stored(afterEditing: nil) { $0.removesBackground = true }
        XCTAssertEqual(cut?.removesBackground, true)
        XCTAssertNil(SourceCutout.stored(afterEditing: cut) { $0.removesBackground = false })
    }
}

final class PercentTests: XCTestCase {
    func testFractionsAreShownAsRoundedPercentages() {
        XCTAssertEqual(Percent.shown(0.456), 46)
        XCTAssertEqual(Percent.fraction(25), 0.25)
        XCTAssertEqual(Percent.range, 0...100)
    }

    func testTypedNumbersAreHeldToTheRange() {
        XCTAssertEqual(clamped(5, to: 0...1), 1)
        XCTAssertEqual(clamped(-5, to: 0...1), 0)
        XCTAssertEqual(clamped(0.5, to: 0...1), 0.5)
    }
}

final class ChromaKeyEditingTests: XCTestCase {
    func testTheKeyShownIsTheSourcesOwnOrTheGreenScreen() {
        XCTAssertEqual(ChromaKeyEditing.shown(nil), .greenScreen)
        var cutout = SourceCutout()
        var key = ChromaKeySettings.greenScreen
        key.similarity = 0.9
        cutout.chromaKey = key
        XCTAssertEqual(ChromaKeyEditing.shown(cutout), key)
        XCTAssertTrue(ChromaKeyEditing.isOn(cutout))
        XCTAssertFalse(ChromaKeyEditing.isOn(nil))
    }

    func testTheSwitchStartsFromTheGreenScreen() {
        XCTAssertEqual(ChromaKeyEditing.switched(on: true), .greenScreen)
        XCTAssertNil(ChromaKeyEditing.switched(on: false))
    }

    func testTheGroupOpensWhenSomethingIsCutOutUntilSomebodyChoosesOtherwise() {
        XCTAssertTrue(ChromaKeyEditing.isGroupOpen(chosen: nil, cutout: SourceCutout()))
        XCTAssertFalse(ChromaKeyEditing.isGroupOpen(chosen: nil, cutout: nil))
        XCTAssertFalse(ChromaKeyEditing.isGroupOpen(chosen: false, cutout: SourceCutout()))
        XCTAssertTrue(ChromaKeyEditing.isGroupOpen(chosen: true, cutout: nil))
    }
}

final class AnimationListTests: XCTestCase {
    func testAddingStartsFromTheCurrentPlacement() {
        let list = AnimationList.adding(.size, around: 0.5, to: nil)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].property, .size)
        XCTAssertEqual(AnimationList.adding(.tilt, around: 0, to: list).count, 2)
    }

    func testRemovingTheLastOneStoresNothing() {
        let list = AnimationList.adding(.size, around: 0.5, to: AnimationList.adding(.tilt, around: 0, to: nil))
        let rest = AnimationList.removing(list[0].id, from: list)
        XCTAssertEqual(rest?.map(\.id), [list[1].id])
        XCTAssertNil(AnimationList.removing(list[1].id, from: rest))
        XCTAssertNil(AnimationList.removing(UUID(), from: nil))
    }

    func testTheCurrentAnimationIsTheListedOneOrTheOneGiven() {
        let list = AnimationList.adding(.size, around: 0.5, to: nil)
        var stale = list[0]
        stale.duration = 99
        XCTAssertEqual(AnimationList.current(stale, in: list), list[0])
        XCTAssertEqual(AnimationList.current(stale, in: nil), stale)
    }

    func testReplacingChangesOnlyAnAnimationThatIsStillThere() {
        let list = AnimationList.adding(.size, around: 0.5, to: nil)
        var changed = list[0]
        changed.duration = 7
        XCTAssertEqual(AnimationList.replacing(changed, in: list)?[0].duration, 7)
        XCTAssertEqual(AnimationList.replacing(changed, in: []), [])
        XCTAssertNil(AnimationList.replacing(changed, in: nil))
    }
}

private struct FakeFonts: FontListing {
    let styles: [String: [FontStyleChoice]]

    func families() -> [String] { Array(styles.keys).sorted() }
    func styles(ofFamily family: String) -> [FontStyleChoice] { styles[family] ?? [] }
    func family(ofFontNamed fontName: String) -> String? {
        styles.first { $0.value.contains { $0.fontName == fontName } }?.key
    }
}

final class FontSelectionTests: XCTestCase {
    private let selection = FontSelection(fonts: FakeFonts(styles: [
        "Sans": [FontStyleChoice(fontName: "Sans-Regular", styleName: "Regular"), FontStyleChoice(fontName: "Sans-Bold", styleName: "Bold")],
        "Serif": [FontStyleChoice(fontName: "Serif-Regular", styleName: "Regular"), FontStyleChoice(fontName: "Serif-Bold", styleName: "Bold")],
        "Mono": [FontStyleChoice(fontName: "Mono-Light", styleName: "Light")],
        "Empty": [],
    ]))

    func testAFontsFamilyIsLookedUpOrTakenFromItsName() {
        XCTAssertEqual(selection.family(ofFontNamed: "Sans-Bold"), "Sans")
        XCTAssertEqual(selection.family(ofFontNamed: "Unknown"), "Unknown")
    }

    func testChoosingAFamilyKeepsTheStyleWhenItHasIt() {
        XCTAssertEqual(selection.fontName(choosing: "Serif", whileUsing: "Sans-Bold"), "Serif-Bold")
    }

    func testChoosingAFamilyWithoutThatStyleTakesItsFirst() {
        XCTAssertEqual(selection.fontName(choosing: "Mono", whileUsing: "Sans-Bold"), "Mono-Light")
        XCTAssertEqual(selection.fontName(choosing: "Serif", whileUsing: "Unknown"), "Serif-Regular")
    }

    func testChoosingAFamilyWithNoFontsChangesNothing() {
        XCTAssertNil(selection.fontName(choosing: "Empty", whileUsing: "Sans-Bold"))
    }

    func testStylesAreOfferedOnlyWhenThereIsAChoice() {
        XCTAssertEqual(selection.stylesToOffer(forFontNamed: "Sans-Bold").count, 2)
        XCTAssertEqual(selection.stylesToOffer(forFontNamed: "Mono-Light"), [])
    }

    func testFamilyMembersAreReadFromTheSystemsRecords() {
        XCTAssertEqual(
            FontStyleChoice(member: ["Sans-Bold", "Bold", 700, 9]),
            FontStyleChoice(fontName: "Sans-Bold", styleName: "Bold")
        )
        XCTAssertNil(FontStyleChoice(member: ["Sans-Bold"]))
        XCTAssertNil(FontStyleChoice(member: [1, "Bold"]))
        XCTAssertNil(FontStyleChoice(member: ["Sans-Bold", 2]))
        XCTAssertEqual(FontStyleChoice(fontName: "A", styleName: "B").id, "A")
    }
}
