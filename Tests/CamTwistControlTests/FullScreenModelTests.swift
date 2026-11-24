@testable import CamTwistRendering
import XCTest
@testable import CamTwistControl

@MainActor
final class FullScreenModelTests: XCTestCase {
    private static let side: UInt32 = 2
    private static let missing: UInt32 = 9

    private let output = FakeFullScreen()

    private func makeModel() -> FullScreenModel {
        FullScreenModel(covering: FullScreenController(output: output), output: output)
    }

    func testChoosingADisplayCoversItOnceAndClearingUncoversIt() {
        output.connected = [Self.side]
        let model = makeModel()
        model.displayID = Self.side
        model.displayID = Self.side
        XCTAssertEqual(output.shown, [Self.side])
        XCTAssertEqual(model.displayID, Self.side)
        model.displayID = nil
        XCTAssertEqual(output.hideCount, 1)
    }

    func testADisplayThatIsNotConnectedIsGivenUpOn() {
        let model = makeModel()
        model.displayID = Self.missing
        XCTAssertNil(model.displayID)
    }

    func testTheOutputClosingItselfClearsTheChoiceOnceListenedFor() {
        output.connected = [Self.side]
        let model = makeModel()
        XCTAssertNil(output.onClose, "nothing listens until it is started")
        model.start()
        model.displayID = Self.side
        output.onClose?()
        XCTAssertNil(model.displayID)
    }

    func testRefreshUncoversADisplayThatHasGoneAndLeavesOneThatIsThere() {
        output.connected = [Self.side]
        let model = makeModel()
        model.displayID = Self.side
        model.refresh(among: [DisplayChoice(id: Self.side, name: "Side")])
        XCTAssertEqual(model.displayID, Self.side)
        model.refresh(among: [])
        XCTAssertNil(model.displayID)
        XCTAssertEqual(output.hideCount, 1)
    }

    func testAModelThatHasGoneIsNotKeptByTheOutput() {
        var model: FullScreenModel? = makeModel()
        model?.start()
        weak var probe = model
        model = nil
        XCTAssertNil(probe)
        output.onClose?()
    }
}
