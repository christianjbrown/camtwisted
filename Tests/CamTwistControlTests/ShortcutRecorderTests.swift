import CamTwistCore
import XCTest
@testable import CamTwistControl

final class ShortcutRecorderTests: XCTestCase {
    // Where these keys are on a Mac keyboard.
    private static let letterK: UInt16 = 40
    private static let escape: UInt16 = 53
    private static let f5: UInt16 = 96
    private static let space: UInt16 = 49
    private static let upArrow: UInt16 = 126

    private let recorder = ShortcutRecorder()

    private func outcome(_ keyCode: UInt16, _ characters: String, _ modifiers: ShortcutModifiers) -> ShortcutOutcome {
        recorder.outcome(of: KeyPress(
            keyCode: keyCode, characters: characters, modifiers: modifiers, isTyping: false, isSheetUp: false
        ))
    }

    func testAKeyHeldWithCommandControlOrOptionIsAShortcut() {
        XCTAssertEqual(
            outcome(Self.letterK, "k", [.command, .shift]),
            .record(SceneShortcut(keyCode: Int(Self.letterK), key: "K", modifiers: [.command, .shift]))
        )
        XCTAssertEqual(
            outcome(Self.space, " ", [.control]),
            .record(SceneShortcut(keyCode: Int(Self.space), key: "Space", modifiers: [.control]))
        )
        XCTAssertEqual(
            outcome(Self.upArrow, "\u{F700}", [.option]),
            .record(SceneShortcut(keyCode: Int(Self.upArrow), key: "↑", modifiers: [.option]))
        )
    }

    func testAFunctionKeyIsAShortcutOnItsOwn() {
        XCTAssertEqual(
            outcome(Self.f5, "\u{F708}", []),
            .record(SceneShortcut(keyCode: Int(Self.f5), key: "F5", modifiers: []))
        )
    }

    func testTypingIsNotAShortcut() {
        XCTAssertEqual(outcome(Self.letterK, "k", []), .ignore)
        XCTAssertEqual(outcome(Self.letterK, "K", [.shift]), .ignore, "Shift alone only makes a capital")
        XCTAssertEqual(outcome(Self.letterK, "", [.command]), .ignore, "a key that types nothing has no name")
    }

    func testEscapeOnItsOwnGivesUp() {
        XCTAssertEqual(outcome(Self.escape, "\u{1B}", []), .cancel)
        XCTAssertEqual(
            outcome(Self.escape, "\u{1B}", [.command]),
            .record(SceneShortcut(keyCode: Int(Self.escape), key: "⎋", modifiers: [.command]))
        )
    }
}
