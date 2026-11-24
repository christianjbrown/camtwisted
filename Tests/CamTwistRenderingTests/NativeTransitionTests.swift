import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

final class NativeTransitionTests: XCTestCase {
    private let canvas = CGSize(width: 320, height: 180)
    private let access = makePixelAccess()
    private var bounds: CGRect { CGRect(origin: .zero, size: canvas) }
    private let library = NativeTransitionLibrary(directory: URL(fileURLWithPath: "/effects"))

    private var from: CIImage { EffectThumbnailer.sampleScene(size: canvas) }
    private var target: CIImage { CIImage(color: .white).cropped(to: bounds) }

    private func bytes(_ image: CIImage) -> [UInt8] {
        access.rgba(of: image, width: 320, height: 180)
    }

    private func pixel(_ image: CIImage, x: Int, y: Int) -> [UInt8] {
        let all = bytes(image)
        return Array(all[(y * 320 + x) * 4..<(y * 320 + x) * 4 + 4])
    }

    private func transition(_ name: String) throws -> TransitionEffect {
        try XCTUnwrap(library.makeTransition(named: name, canvas: canvas), name)
    }

    func testTheLibraryListsEveryTransitionAndNothingElse() {
        XCTAssertEqual(library.availableEffects().map(\.name), [
            "Dissolve", "Dip", "Flash", "Mod", "PageCurl", "Swipe", "CopyMachine", "Ripple",
        ])
        XCTAssertTrue(library.availableEffects().allSatisfy { $0.kind == .transition })
        XCTAssertEqual(library.directory, URL(fileURLWithPath: "/effects"))
        XCTAssertEqual(library.parameters(forEffectNamed: "Swipe"), [])
        XCTAssertNil(library.makeEffect(named: "Swipe", canvas: canvas))
        XCTAssertNil(library.makeTransition(named: "No such transition", canvas: canvas))
    }

    func testEveryTransitionStartsOnThePictureAndEndsOnTheTarget() throws {
        let start = bytes(from)
        let end = bytes(target)
        for listing in library.availableEffects() {
            let made = try transition(listing.name)
            let first = made.blend(from: from, to: target, progress: 0, time: 0)
            XCTAssertEqual(first.extent, bounds, listing.name)
            XCTAssertEqual(bytes(first), start, "\(listing.name) starts on the picture")
            XCTAssertEqual(bytes(made.blend(from: from, to: target, progress: 1, time: 0)), end, "\(listing.name) ends on the target")
        }
    }

    func testEveryTransitionIsSomethingInBetween() throws {
        for listing in library.availableEffects() {
            let middle = try transition(listing.name).blend(from: from, to: target, progress: 0.5, time: 0)
            XCTAssertEqual(middle.extent, bounds, listing.name)
            XCTAssertNotEqual(bytes(middle), bytes(from), "\(listing.name) has left the picture")
            XCTAssertNotEqual(bytes(middle), bytes(target), "\(listing.name) has not reached the target")
        }
    }

    func testProgressBeyondTheEndsIsHeldThere() throws {
        let made = try transition("Swipe")
        XCTAssertEqual(bytes(made.blend(from: from, to: target, progress: 2, time: 0)), bytes(target))
        XCTAssertEqual(bytes(made.blend(from: from, to: target, progress: -1, time: 0)), bytes(from))
    }

    func testDipGoesThroughBlackInTheMiddle() throws {
        let dip = try transition("Dip")
        XCTAssertEqual(Array(pixel(dip.blend(from: from, to: target, progress: 0.5, time: 0), x: 160, y: 90).prefix(3)), [0, 0, 0])
        // A quarter of the way it is half faded out.
        XCTAssertNotEqual(pixel(dip.blend(from: from, to: target, progress: 0.25, time: 0), x: 10, y: 10), pixel(from, x: 10, y: 10))
    }

    func testTheRippleSpreadsOutFromTheMiddle() throws {
        let ripple = try transition("Ripple")
        let early = ripple.blend(from: from, to: target, progress: 0.2, time: 0)
        // The middle has the new picture; a corner is still the old one.
        XCTAssertEqual(Array(pixel(early, x: 160, y: 90).prefix(3)), [255, 255, 255])
        XCTAssertEqual(pixel(early, x: 2, y: 2), pixel(from, x: 2, y: 2))
    }


}

private struct EmptyTransitions: TransitionFactory {
    func makeTransition(named name: String, canvas: CGSize) -> TransitionEffect? { nil }
}
