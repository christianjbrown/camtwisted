import CamTwistCore
import CoreGraphics
import XCTest
@testable import CamTwistRendering

final class EffectControlTests: XCTestCase {
    func testANumberControlDeclaresAndReadsBackTheSameStartingValue() {
        let control = NumberControl(key: "Amount", displayName: "Amount", start: 0.3, range: 0...1)
        XCTAssertEqual(control.parameter.defaultValue, .number(0.3))
        XCTAssertEqual(control.parameter.range, 0...1)
        XCTAssertEqual(control.parameter.displayName, "Amount")
        XCTAssertEqual(control.value(in: [:]), 0.3)
        XCTAssertEqual(control.value(in: ["Amount": .number(0.8)]), 0.8)
    }

    func testASwitchControlStartsOffAndReadsItsValue() {
        let control = SwitchControl(key: "Flip", displayName: "Flip it")
        XCTAssertEqual(control.parameter.defaultValue, .boolean(false))
        XCTAssertEqual(control.parameter.kind, .boolean)
        XCTAssertFalse(control.isOn(in: [:]))
        XCTAssertTrue(control.isOn(in: ["Flip": .boolean(true)]))
    }

    func testAColorControlDeclaresAndReadsBackTheSameStartingColour() {
        let control = ColorControl(key: "Color", displayName: "Colour", red: 0.2, green: 0.5, blue: 1)
        XCTAssertEqual(control.parameter.defaultValue, .color(red: 0.2, green: 0.5, blue: 1, alpha: 1))
        XCTAssertEqual(control.parameter.kind, .color)
        XCTAssertEqual(control.value(in: [:]), CGColor(srgbRed: 0.2, green: 0.5, blue: 1, alpha: 1))
        let red = EffectValue.color(red: 1, green: 0, blue: 0, alpha: 1)
        XCTAssertEqual(control.value(in: ["Color": red]), CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    }
}
