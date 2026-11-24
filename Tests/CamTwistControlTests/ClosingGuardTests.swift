import Foundation
import XCTest
@testable import CamTwistControl

@MainActor
private final class FakeClosingSetups: ClosingSetups {
    var hasUnsavedChanges = true
    var documentURL: URL?
    var savesSucceed = true
    var savedTo: [URL] = []
    var currentFileSaves = 0

    func saveToCurrentFile() -> Bool {
        guard documentURL != nil else { return false }
        currentFileSaves += 1
        if savesSucceed { hasUnsavedChanges = false }
        return true
    }

    func save(to url: URL) {
        savedTo.append(url)
        if savesSucceed { hasUnsavedChanges = false }
    }
}

@MainActor
private final class FakeAsker: SaveAsking {
    var answer = SaveAnswer.cancel
    var askedAbout: [String?] = []
    func askToSave(setupName: String?) -> SaveAnswer {
        askedAbout.append(setupName)
        return answer
    }
}

private final class FakeChooser: SetupFileChoosing {
    var chosen: URL?
    func chooseSetupToOpen() -> URL? { nil }
    func chooseSetupToSave(suggestedName: String?) -> URL? { chosen }
}

@MainActor
final class ClosingGuardTests: XCTestCase {
    private let setups = FakeClosingSetups()
    private let asker = FakeAsker()
    private let chooser = FakeChooser()
    private lazy var closing = ClosingGuard(setups: setups, asker: asker, chooser: chooser)
    private let url = URL(fileURLWithPath: "/setups/show.camtwisted")

    func testNothingUnsavedClosesWithoutAsking() {
        setups.hasUnsavedChanges = false
        XCTAssertTrue(closing.mayClose())
        XCTAssertTrue(asker.askedAbout.isEmpty)
    }

    func testDiscardingClosesAndCancellingStays() {
        setups.documentURL = url
        asker.answer = .discard
        XCTAssertTrue(closing.mayClose())
        XCTAssertEqual(asker.askedAbout, ["show.camtwisted"])
        asker.answer = .cancel
        XCTAssertFalse(closing.mayClose())
    }

    func testSavingASetupWithAFileSavesOverIt() {
        setups.documentURL = url
        asker.answer = .save
        XCTAssertTrue(closing.mayClose())
        XCTAssertEqual(setups.currentFileSaves, 1)
    }

    func testSavingANewSetupAsksWhereAndStaysWhenThatIsCancelled() {
        asker.answer = .save
        XCTAssertFalse(closing.mayClose())
        XCTAssertEqual(asker.askedAbout, [nil])
        chooser.chosen = url
        XCTAssertTrue(closing.mayClose())
        XCTAssertEqual(setups.savedTo, [url])
    }

    func testASaveThatFailsKeepsTheAppOpen() {
        setups.documentURL = url
        setups.savesSucceed = false
        asker.answer = .save
        XCTAssertFalse(closing.mayClose())
    }
}
