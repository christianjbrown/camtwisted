import CamTwistCore
import CamTwistRendering
import XCTest
@testable import CamTwistControl

final class StepRowLogicTests: XCTestCase {
    func testSettingsHelpFollowsTheRow() {
        XCTAssertEqual(StepRowLogic.settingsHelp(isExpanded: true), "Hide settings")
        XCTAssertEqual(StepRowLogic.settingsHelp(isExpanded: false), "Show settings")
    }

    func testFillIsStoredAsNothing() {
        XCTAssertEqual(StepRowLogic.shownFit(nil), .fill)
        XCTAssertEqual(StepRowLogic.shownFit(.stretch), .stretch)
        XCTAssertNil(StepRowLogic.storedFit(.fill))
        XCTAssertEqual(StepRowLogic.storedFit(.fit), .fit)
    }

    func testAVolumeNotSetShowsTheStartingLevel() {
        XCTAssertEqual(StepRowLogic.shownVolume(nil, startingAt: 0.5), 0.5)
        XCTAssertEqual(StepRowLogic.shownVolume(0.2, startingAt: 0.5), 0.2)
    }

    func testTheEndDropBoxNamesWhereADropLands() {
        XCTAssertEqual(StepRowLogic.endDropText(parentTitle: "Camera", isEmpty: true), "Drop here to add to Camera only")
        XCTAssertEqual(
            StepRowLogic.endDropText(parentTitle: nil, isEmpty: true),
            "Nothing in this scene yet. Add a source or effect below."
        )
        XCTAssertEqual(StepRowLogic.endDropText(parentTitle: nil, isEmpty: false), "Drop here to add to the whole scene")
    }
}

final class ChainReorderingTests: XCTestCase {
    private let top = UUID()
    private let middle = UUID()
    private let bottom = UUID()
    private var frames: [UUID: CGRect] {
        [
            top: CGRect(x: 0, y: 0, width: 100, height: 40),
            middle: CGRect(x: 0, y: 40, width: 100, height: 40),
            bottom: CGRect(x: 0, y: 80, width: 100, height: 40),
        ]
    }

    func testDraggingDownTakesTheRowBelowOncePastItsMiddle() {
        XCTAssertNil(ChainReordering.passedRow(dragging: top, frames: frames, pointerY: 50))
        XCTAssertEqual(ChainReordering.passedRow(dragging: top, frames: frames, pointerY: 65), middle)
    }

    func testDraggingUpTakesTheRowAboveOncePastItsMiddle() {
        XCTAssertNil(ChainReordering.passedRow(dragging: bottom, frames: frames, pointerY: 70))
        XCTAssertEqual(ChainReordering.passedRow(dragging: bottom, frames: frames, pointerY: 55), middle)
    }

    func testARowNotMeasuredYetTakesNothing() {
        XCTAssertNil(ChainReordering.passedRow(dragging: UUID(), frames: frames, pointerY: 65))
        XCTAssertFalse(ChainReordering.crossesMiddle(of: frames[top]!, from: nil, pointer: 10))
    }

    func testTheDraggedRowKeepsItsGripOnThePointer() {
        XCTAssertEqual(ChainReordering.grabOffset(pressY: 50, rowTop: 40), 10)
        XCTAssertEqual(ChainReordering.grabOffset(pressY: 50, rowTop: nil), 50)
        XCTAssertEqual(ChainReordering.dragOffset(pointerY: 70, grabOffset: 10, rowTop: 40), 20)
        XCTAssertEqual(ChainReordering.dragOffset(pointerY: 70, grabOffset: 10, rowTop: nil), 60)
    }
}

final class AddPickerLogicTests: XCTestCase {
    private let image = SourceSpec.colorBars

    func testSourceOffersSkipACameraAndScreenThatAreNotThere() {
        let bare = SourceCatalog.offers(camera: nil, firstDisplayID: nil, image: image).map(\.title)
        XCTAssertFalse(bare.contains("Camera"))
        XCTAssertFalse(bare.contains("Screen"))
        XCTAssertEqual(bare.first, "Window")
        XCTAssertEqual(bare.last, "Colour bars")
    }

    func testSourceOffersLeadWithTheCameraAndScreen() {
        let offers = SourceCatalog.offers(camera: .camera(deviceID: "cam"), firstDisplayID: 7, image: image)
        XCTAssertEqual(offers.prefix(3).map(\.title), ["Camera", "Screen", "Window"])
        XCTAssertEqual(offers[0].content, .source(.camera(deviceID: "cam")))
        XCTAssertEqual(offers[1].content, .source(.display(DisplaySettings(displayID: 7))))
        XCTAssertEqual(offers.count, 14)
    }

    func testTheHelpAddsTheDetailWhenThereIsOne() {
        let offers = SourceCatalog.offers(camera: nil, firstDisplayID: nil, image: image)
        XCTAssertEqual(offers.first { $0.title == "Window" }?.help, "Window: one window, even when covered")
        XCTAssertEqual(offers.first { $0.title == "Video" }?.help, "Video")
        XCTAssertEqual(SourceCatalog.effectSymbol, "sparkles")
    }

    private let effects = [
        EffectListing(name: "Ring", kind: .overlay), EffectListing(name: "Fade", kind: .transition),
        EffectListing(name: "Tint", kind: .filter),
    ]

    func testTransitionsAreNotOfferedAsEffects() {
        let offers = EffectOffers(effects: effects, search: "")
        XCTAssertEqual(offers.shown.map(\.name), ["Ring", "Tint"])
        XCTAssertNil(offers.emptyMessage)
    }

    func testSearchingNarrowsTheEffectsWhateverTheCase() {
        XCTAssertEqual(EffectOffers(effects: effects, search: "rIN").shown.map(\.name), ["Ring"])
    }

    func testAnEmptyListSaysWhy() {
        XCTAssertEqual(EffectOffers(effects: effects, search: "zzz").emptyMessage, "No effect matches.")
        XCTAssertEqual(
            EffectOffers(effects: [], search: "").emptyMessage, "No effects yet."
        )
    }
}
