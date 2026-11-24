import CamTwistCore
import CoreGraphics
import XCTest
@testable import CamTwistControl

final class PictureDraggingTests: XCTestCase {
    private let library = FakeEffectLibrary()
    private lazy var dragging = PictureDragging(parameters: EffectParameters(library: library))
    private let pip = PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5))

    override func setUp() {
        library.controls = [
            "Overlay": [numberControl("px", name: "X Position", value: 0.25), numberControl("py", name: "Y Position")],
            "NoY": [numberControl("px", name: "X Position")],
            "Ring": [
                numberControl("px", name: "X Position", value: 0), numberControl("py", name: "Y Position", value: 0),
                EffectParameter(
                    key: "size", displayName: "Size", kind: .number, defaultValue: .number(0.4), range: 0.1...0.6
                ),
                numberControl("turn", name: "Rotation", value: 0),
            ],
            "Solid": [
                numberControl("px", name: "X Position", value: 0), numberControl("py", name: "Y Position", value: 0),
                numberControl("turn", name: "Turn", value: 170), numberControl("tilt", name: "Tilt", value: -170),
            ],
            "Turner": [
                numberControl("px", name: "X Position", value: 0), numberControl("py", name: "Y Position", value: 0),
                numberControl("turn", name: "Rotation", value: 0),
            ],
            "Sized": [
                numberControl("px", name: "X Position", value: 0), numberControl("py", name: "Y Position", value: 0),
                numberControl("size", name: "Size", value: 0.4),
            ],
            "TextY": [
                numberControl("px", name: "X Position"),
                EffectParameter(key: "py", displayName: "Y Position", kind: .string, defaultValue: .string("")),
            ],
        ]
    }

    // MARK: What a drag does

    func testNothingSelectedAndNoTelestratorMeansNoDragTarget() {
        let scene = SceneConfiguration(items: [sourceItem(.testCard)])
        XCTAssertNil(dragging.target(in: scene, selected: nil))
        XCTAssertNil(dragging.hint(in: scene, selected: nil))
    }

    func testWithNothingSelectedDrawingGoesToTheLastEnabledTelestrator() {
        let first = sourceItem(.telestrator(TelestratorSettings()))
        let off = sourceItem(.telestrator(TelestratorSettings()), enabled: false)
        let last = sourceItem(.telestrator(TelestratorSettings()))
        let scene = SceneConfiguration(items: [first, last, off, sourceItem(.testCard)])
        XCTAssertEqual(dragging.target(in: scene, selected: nil), .telestrator(last.id))
        XCTAssertEqual(dragging.target(in: scene, selected: UUID()), .telestrator(last.id))
        XCTAssertEqual(dragging.hint(in: scene, selected: nil), "Drag on the picture to draw")
    }

    func testASwitchedOffStepFallsBackToTheTelestrator() {
        let pen = sourceItem(.telestrator(TelestratorSettings()))
        let off = sourceItem(.testCard, enabled: false, pip: pip)
        let scene = SceneConfiguration(items: [pen, off])
        XCTAssertEqual(dragging.target(in: scene, selected: off.id), .telestrator(pen.id))
    }

    func testASelectedTelestratorIsTheTarget() {
        let pen = sourceItem(.telestrator(TelestratorSettings()))
        let scene = SceneConfiguration(items: [pen])
        XCTAssertEqual(dragging.target(in: scene, selected: pen.id), .telestrator(pen.id))
    }

    func testASelectedPictureInPictureSourceCanBeDragged() {
        let small = sourceItem(.testCard, pip: pip)
        let scene = SceneConfiguration(items: [small])
        XCTAssertEqual(dragging.target(in: scene, selected: small.id), .picture(small.id))
        XCTAssertEqual(
            dragging.hint(in: scene, selected: small.id),
            "Drag Test card to move it, a corner to resize it, the knob to turn it"
        )
    }

    func testADragCanMoveResizeOrTurnAPlacedSource() {
        let small = sourceItem(.testCard, pip: PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5), scale: 0.4))
        var scene = SceneConfiguration(items: [small])
        func placement() -> PictureInPictureSettings? { scene.item(id: small.id)?.pictureInPicture }

        dragging.drag(
            from: CGPoint(x: 0.6, y: 0.5), to: CGPoint(x: 0.7, y: 0.5), mode: .resize, in: &scene, selected: small.id
        )
        XCTAssertEqual(placement()?.scale ?? 0, 0.8, accuracy: 0.0001)
        XCTAssertEqual(placement()?.center, CGPoint(x: 0.5, y: 0.5))

        dragging.drag(
            from: CGPoint(x: 0.7, y: 0.5), to: CGPoint(x: 0.5, y: 0.3), mode: .turn, in: &scene, selected: small.id
        )
        XCTAssertGreaterThan(placement()?.rotation ?? 0, 0, "dragged clockwise")
        XCTAssertEqual(placement()?.scale ?? 0, 0.8, accuracy: 0.0001)

        dragging.drag(
            from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.3, y: 0.2), mode: .move, in: &scene, selected: small.id
        )
        XCTAssertEqual(placement()?.center.x ?? 0, 0.6, accuracy: 0.0001)
    }

    func testAnOverlayWithASizeAndARotationResizesAndTurnsToo() {
        let ring = ChainItem(content: .effect(name: "Ring", values: [:]))
        var scene = SceneConfiguration(items: [ring])
        func value(_ key: String) -> EffectValue? {
            guard case .effect(_, let values) = scene.item(id: ring.id)?.content else { return nil }
            return values[key]
        }
        XCTAssertEqual(
            dragging.hint(in: scene, selected: ring.id),
            "Drag Ring to move it, a corner to resize it, the knob to turn it"
        )

        // Its middle is the middle of the picture; twice as far out is twice
        // the size, held to the control's range.
        dragging.drag(
            from: CGPoint(x: 0.6, y: 0.5), to: CGPoint(x: 0.7, y: 0.5), mode: .resize, in: &scene, selected: ring.id
        )
        XCTAssertEqual(value("size"), .number(0.6))
        dragging.drag(
            from: CGPoint(x: 0.7, y: 0.5), to: CGPoint(x: 0.5, y: 0.3), mode: .turn, in: &scene, selected: ring.id
        )
        guard case .number(let turned)? = value("turn") else { return XCTFail("no rotation was set") }
        XCTAssertGreaterThan(turned, 0)
        XCTAssertNil(value("px"), "neither drag moved it")
    }

    func testAnOverlayWithOnlyASizeResizesAndIsMovedByATurn() {
        let sized = ChainItem(content: .effect(name: "Sized", values: [:]))
        var scene = SceneConfiguration(items: [sized])
        func value(_ key: String) -> EffectValue? {
            guard case .effect(_, let values) = scene.item(id: sized.id)?.content else { return nil }
            return values[key]
        }
        XCTAssertEqual(dragging.hint(in: scene, selected: sized.id), "Drag Sized to move it, a corner to resize it")
        dragging.drag(
            from: CGPoint(x: 0.6, y: 0.5), to: CGPoint(x: 0.7, y: 0.5), mode: .resize, in: &scene, selected: sized.id
        )
        XCTAssertEqual(value("size"), .number(0.8), "no range, so nothing holds it")
        dragging.drag(
            from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.6, y: 0.5), mode: .turn, in: &scene, selected: sized.id
        )
        XCTAssertNotNil(value("px"), "with nothing to turn, the drag moves it")
    }

    func testASolidTurnsAndTiltsWithATurningDrag() {
        let solid = ChainItem(content: .effect(name: "Solid", values: [:]))
        var scene = SceneConfiguration(items: [solid])
        XCTAssertEqual(dragging.hint(in: scene, selected: solid.id), "Drag Solid to move it, the knob to turn it")
        // A quarter of the picture across and up: 45 degrees each way, and
        // both come round past a half turn.
        dragging.drag(
            from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.75, y: 0.75), mode: .turn, in: &scene, selected: solid.id
        )
        guard case .effect(_, let values) = scene.item(id: solid.id)?.content else { return XCTFail("no effect") }
        XCTAssertEqual(values["turn"], .number(-145))
        XCTAssertEqual(values["tilt"], .number(145))
        XCTAssertNil(values["px"])
        dragging.drag(
            from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.6, y: 0.4), mode: .turn, in: &scene, selected: solid.id
        )
        guard case .effect(_, let again) = scene.item(id: solid.id)?.content else { return XCTFail("no effect") }
        XCTAssertEqual(again["turn"], .number(-127))
        XCTAssertEqual(again["tilt"], .number(163))
    }

    func testAnOverlayWithOnlyARotationTurns() {
        let turner = ChainItem(content: .effect(name: "Turner", values: [:]))
        var scene = SceneConfiguration(items: [turner])
        XCTAssertEqual(dragging.hint(in: scene, selected: turner.id), "Drag Turner to move it, the knob to turn it")
        dragging.drag(
            from: CGPoint(x: 0.7, y: 0.5), to: CGPoint(x: 0.5, y: 0.3), mode: .turn, in: &scene, selected: turner.id
        )
        guard case .effect(_, let values) = scene.item(id: turner.id)?.content else { return XCTFail("no effect") }
        XCTAssertNotNil(values["turn"])
        XCTAssertNil(values["px"])
    }

    func testTheOutlineIsTheBoxRoundWhatResizes() {
        let placed = PictureInPictureSettings(center: CGPoint(x: 0.25, y: 0.75), scale: 0.5, rotation: 30)
        let small = sourceItem(.testCard, pip: placed)
        let branched = ChainItem(
            content: .source(.testCard), pictureInPicture: placed, branch: [sourceItem(.colorBars)]
        )
        let ring = ChainItem(content: .effect(name: "Ring", values: [:]))
        let sized = ChainItem(content: .effect(name: "Sized", values: [:]))
        let overlay = ChainItem(content: .effect(name: "Overlay", values: [:]))
        let pen = sourceItem(.telestrator(TelestratorSettings()))
        let turner = ChainItem(content: .effect(name: "Turner", values: [:]))
        let scene = SceneConfiguration(items: [small, branched, ring, sized, overlay, pen, turner])
        let square = CGSize(width: 100, height: 100)
        var drawn: [String: CGRect] = [:]
        var measuredValues: [String: EffectValue] = [:]
        func outline(_ id: UUID, size: CGSize? = nil) -> SelectionOutline? {
            dragging.outline(in: scene, selected: id, pictureSize: { _ in size }, overlayBounds: { name, values in
                measuredValues = values
                return drawn[name]
            })
        }

        XCTAssertNil(outline(small.id), "no picture yet, so no box")
        // A square picture half the canvas wide is 640 points each way: half
        // the width of a 1280 by 720 canvas and eight ninths of its height.
        let box = outline(small.id, size: square)
        XCTAssertEqual(box?.center, placed.center)
        XCTAssertEqual(box?.size.width ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(box?.size.height ?? 0, 8.0 / 9, accuracy: 0.0001)
        XCTAssertEqual(box?.rotation, 30)
        XCTAssertEqual(box?.canTurn, true)
        XCTAssertEqual(outline(branched.id)?.size.height ?? 0, 0.5, accuracy: 0.0001, "a branch is canvas shaped")

        XCTAssertEqual(outline(ring.id), SelectionOutline(
            center: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 0.4, height: 0.4 * 1280 / 720), rotation: 0,
            canTurn: true, canResize: true
        ))
        XCTAssertEqual(outline(sized.id)?.canTurn, false)
        XCTAssertEqual(outline(sized.id)?.canResize, true)
        XCTAssertEqual(outline(turner.id)?.canResize, false, "it turns, so it has a box all the same")
        XCTAssertEqual(outline(turner.id)?.size.width, CGFloat(PictureInPictureSettings.defaultScale))
        XCTAssertNil(outline(overlay.id), "nothing to resize")
        XCTAssertNil(outline(pen.id))

        // Once an overlay can be measured, its box is round what it draws:
        // here a strip low on the picture, long and thin.
        drawn["Overlay"] = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.1)
        let strip = outline(overlay.id)
        XCTAssertEqual(strip?.center.x ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(strip?.center.y ?? 0, 0.15, accuracy: 0.0001)
        XCTAssertEqual(strip?.size, CGSize(width: 0.8, height: 0.1))
        XCTAssertEqual(strip?.canTurn, false)
        XCTAssertEqual(strip?.canResize, false)
        // One that turns is measured upright, and the box's middle is
        // carried round its position with it: a quarter turn clockwise
        // takes a middle above the position out to its right.
        drawn["Ring"] = CGRect(x: 0.4, y: 0.6, width: 0.2, height: 0.2)
        let turnedRing = ChainItem(content: .effect(name: "Ring", values: ["turn": .number(90)]))
        let turnedScene = SceneConfiguration(items: [turnedRing])
        let turned = dragging.outline(in: turnedScene, selected: turnedRing.id, pictureSize: { _ in nil }, overlayBounds: { name, values in
            measuredValues = values
            return drawn[name]
        })
        XCTAssertEqual(measuredValues["turn"], .number(0))
        XCTAssertEqual(turned?.rotation, 90)
        XCTAssertEqual(turned?.size, CGSize(width: 0.2, height: 0.2))
        XCTAssertEqual(turned?.center.x ?? 0, 0.5 + 0.2 * 720 / 1280, accuracy: 0.0001)
        XCTAssertEqual(turned?.center.y ?? 0, 0.5, accuracy: 0.0001)
    }

    func testResizingSomethingThatOnlyMovesMovesIt() {
        let full = sourceItem(.testCard)
        var scene = SceneConfiguration(items: [full])
        dragging.drag(from: .zero, to: CGPoint(x: 0.1, y: 0), mode: .resize, in: &scene, selected: full.id)
        XCTAssertEqual(scene.items, [full], "nothing placed, so nothing changes")
    }

    func testASourceFillingTheFrameCannotBeDragged() {
        let full = sourceItem(.testCard)
        XCTAssertNil(dragging.target(in: SceneConfiguration(items: [full]), selected: full.id))
    }

    func testAnEffectWithBothPositionControlsIsAnOverlay() {
        let overlay = effectItem("Overlay")
        let scene = SceneConfiguration(items: [overlay])
        XCTAssertEqual(dragging.target(in: scene, selected: overlay.id), .overlay(overlay.id, xKey: "px", yKey: "py"))
        XCTAssertEqual(dragging.hint(in: scene, selected: overlay.id), "Drag on the picture to move Overlay")
    }

    func testAnEffectMissingAPositionControlCannotBeDragged() {
        for name in ["NoY", "TextY", "Unknown"] {
            let item = effectItem(name)
            XCTAssertNil(dragging.target(in: SceneConfiguration(items: [item]), selected: item.id), name)
        }
    }

    func testAScriptCannotBeDragged() {
        let script = ChainItem(content: .script(source: "beep"))
        XCTAssertNil(dragging.target(in: SceneConfiguration(items: [script]), selected: script.id))
    }

    // MARK: Moving

    func testDraggingAPictureMovesItsCentre() {
        let small = sourceItem(.testCard, pip: pip)
        var scene = SceneConfiguration(items: [small])
        dragging.drag(by: CGPoint(x: 0.1, y: 0), in: &scene, selected: small.id)
        let center = scene.item(id: small.id)?.pictureInPicture?.center
        XCTAssertEqual(center, OverlayPosition.moved(center: pip.center, by: CGPoint(x: 0.1, y: 0)))
    }

    func testDraggingAnOverlayMovesItsTwoControlsFromTheirCurrentValues() {
        let overlay = effectItem("Overlay", values: ["px": .number(10), "py": .number(20)])
        var scene = SceneConfiguration(items: [overlay])
        let delta = CGPoint(x: 0.1, y: 0.1)
        dragging.drag(by: delta, in: &scene, selected: overlay.id)
        let expected = OverlayPosition.moved(x: 10, y: 20, by: delta, canvas: CameraContract.size)
        guard case .effect(_, let values) = scene.item(id: overlay.id)?.content else { return XCTFail("no effect") }
        XCTAssertEqual(values["px"], .number(expected.x))
        XCTAssertEqual(values["py"], .number(expected.y))
    }

    func testDraggingAnOverlayStartsFromTheControlsDefaultsWhenNoValueIsSet() {
        let overlay = effectItem("Overlay")
        var scene = SceneConfiguration(items: [overlay])
        let delta = CGPoint(x: 0.1, y: 0.1)
        dragging.drag(by: delta, in: &scene, selected: overlay.id)
        let expected = OverlayPosition.moved(x: 0.25, y: 0.5, by: delta, canvas: CameraContract.size)
        guard case .effect(_, let values) = scene.item(id: overlay.id)?.content else { return XCTFail("no effect") }
        XCTAssertEqual(values["px"], .number(expected.x))
    }

    func testDraggingAnOverlayWhoseValueIsNotANumberStartsFromZero() {
        let overlay = effectItem("Overlay", values: ["px": .string("left"), "py": .number(0)])
        var scene = SceneConfiguration(items: [overlay])
        let delta = CGPoint(x: 0.1, y: 0)
        dragging.drag(by: delta, in: &scene, selected: overlay.id)
        let expected = OverlayPosition.moved(x: 0, y: 0, by: delta, canvas: CameraContract.size)
        guard case .effect(_, let values) = scene.item(id: overlay.id)?.content else { return XCTFail("no effect") }
        XCTAssertEqual(values["px"], .number(expected.x))
    }

    func testDraggingATelestratorOrNothingChangesNothing() {
        let pen = sourceItem(.telestrator(TelestratorSettings()))
        var scene = SceneConfiguration(items: [pen])
        let before = scene
        dragging.drag(by: CGPoint(x: 1, y: 1), in: &scene, selected: pen.id)
        dragging.drag(by: CGPoint(x: 1, y: 1), in: &scene, selected: UUID())
        var plain = SceneConfiguration(items: [sourceItem(.testCard)])
        let plainBefore = plain
        dragging.drag(by: CGPoint(x: 1, y: 1), in: &plain, selected: nil)
        XCTAssertEqual(scene.items.count, before.items.count)
        XCTAssertEqual(plain, plainBefore)
    }

    // MARK: Telestrator

    func testAStrokeIsAddedInThePensColourAndWidth() {
        let pen = sourceItem(.telestrator(TelestratorSettings(penWidth: 0.02)))
        var scene = SceneConfiguration(items: [pen])
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]
        dragging.addStroke(points, to: pen.id, in: &scene)
        guard case .source(.telestrator(let settings)) = scene.item(id: pen.id)?.content else { return XCTFail("no pen") }
        XCTAssertEqual(settings.strokes, [DrawingStroke(points: points, color: settings.penColor, width: 0.02)])
    }

    func testAStrokeForAStepThatIsNotATelestratorIsIgnored() {
        let other = sourceItem(.testCard)
        var scene = SceneConfiguration(items: [other])
        dragging.addStroke([CGPoint.zero], to: other.id, in: &scene)
        XCTAssertEqual(scene.items, [other])
    }
}
