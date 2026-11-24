import CamTwistCore
import CoreImage
import XCTest
@testable import CamTwistRendering

private final class FakeMasker: PersonMasking {
    var answer: CIImage?
    func mask(for image: CIImage) -> CIImage? { answer }
}

final class GradeAndBackgroundTests: XCTestCase {
    private let canvas = CGSize(width: 320, height: 180)
    private let access = makePixelAccess()
    private var bounds: CGRect { CGRect(origin: .zero, size: canvas) }

    private func pixel(_ image: CIImage, x: Int, y: Int) -> [Int] {
        let whole = image.composited(over: CIImage(color: .clear).cropped(to: bounds))
        let bytes = access.rgba(of: whole, width: 320, height: 180)
        return bytes[(y * 320 + x) * 4..<(y * 320 + x) * 4 + 4].map(Int.init)
    }

    /// A table that swaps red and blue.
    private var swapped: String {
        var lines = ["LUT_3D_SIZE 2"]
        for blue in 0..<2 {
            for green in 0..<2 {
                for red in 0..<2 {
                    lines.append("\(blue) \(green) \(red)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    func testALookUpTableGradesThePictureAndIsReadOnce() {
        var reads: [String] = []
        let effect = LUTEffect { path in
            reads.append(path)
            return path == "/luts/swap.cube" ? self.swapped : nil
        }
        let red = CIImage(color: .red).cropped(to: bounds)
        XCTAssertEqual(Array(pixel(effect.apply(to: red, time: 0), x: 10, y: 10).prefix(3)), [255, 0, 0], "no file, no grade")

        effect.setValues([LUTEffect.fileKey: .string("/luts/swap.cube")])
        XCTAssertEqual(Array(pixel(effect.apply(to: red, time: 0), x: 10, y: 10).prefix(3)), [0, 0, 255], "red comes out blue")
        _ = effect.apply(to: red, time: 1)
        XCTAssertEqual(reads, ["", "/luts/swap.cube"], "the file is read when it is chosen, not for every frame")

        // Half way, the grade is mixed half and half with the picture.
        effect.setValues([LUTEffect.fileKey: .string("/luts/swap.cube"), LUTEffect.amountKey: .number(0.5)])
        let mixed = pixel(effect.apply(to: red, time: 0), x: 10, y: 10)
        XCTAssertGreaterThan(mixed[0], 60)
        XCTAssertGreaterThan(mixed[2], 60)

        // A file that is no table leaves the picture alone.
        effect.setValues([LUTEffect.fileKey: .string("/luts/notes.txt")])
        XCTAssertEqual(Array(pixel(effect.apply(to: red, time: 0), x: 10, y: 10).prefix(3)), [255, 0, 0])

        XCTAssertEqual(LUTEffect.parameters.first?.fileTypes, ["cube"])
        XCTAssertEqual(NativeEffect.lut.name, "Apply LUT")
        XCTAssertTrue(NativeEffect.lut.make(canvas) is LUTEffect)
        XCTAssertEqual(LUTEffect().apply(to: red, time: 0), red, "the real reader finds no file of no name")
    }

    /// The person is the left half of the picture.
    private var leftHalfMask: CIImage {
        CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 160, height: 180))
            .composited(over: CIImage(color: .black).cropped(to: bounds))
    }

    func testTheBackgroundIsBlurredBehindThePerson() {
        // Red on the left, with a blue and white edge on the right to blur.
        let masker = FakeMasker()
        masker.answer = leftHalfMask
        let picture = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 160, height: 180))
            .composited(over: CIImage(color: .white).cropped(to: CGRect(x: 240, y: 0, width: 80, height: 180)))
            .composited(over: CIImage(color: .blue).cropped(to: bounds))

        let blur = BackgroundEffect(canvas: canvas, masker: masker)
        blur.setValues([BackgroundEffect.amountKey: .number(1)])
        let blurred = blur.apply(to: picture, time: 0)
        XCTAssertEqual(Array(pixel(blurred, x: 40, y: 90).prefix(3)), [255, 0, 0], "the person is left sharp")
        let edge = pixel(blurred, x: 236, y: 90)
        XCTAssertGreaterThan(edge[0], 20, "the edge behind them is smeared")
        XCTAssertLessThan(edge[0], 235)

        masker.answer = nil
        XCTAssertEqual(blur.apply(to: picture, time: 0), picture, "nobody found, so nothing changes")
        XCTAssertEqual(NativeEffect.backgrounds(masker: RenderingSupplies.system().makeMasker).map(\.name), ["Blur Background"])
    }

    func testTheRealBackgroundEffectRunsOnAPictureWithNobodyInIt() {
        // The system's person finder finds nobody in a plain picture: the
        // effect must still hand a picture of the right size back.
        let picture = EffectThumbnailer.sampleScene(size: canvas)
        for background in NativeEffect.backgrounds(masker: RenderingSupplies.system().makeMasker) {
            XCTAssertEqual(background.make(canvas).apply(to: picture, time: 0).extent, bounds, background.name)
        }
    }

    func testASourceIsCutOutToItsPeopleAndItsKeyColourIsCleared() {
        let masker = FakeMasker()
        let cutter = SourceCutter(masker: masker)
        let source = UUID()
        // Red on the left, where the person is, and green on the right.
        let picture = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 160, height: 180))
            .composited(over: CIImage(color: .green).cropped(to: bounds))

        XCTAssertEqual(cutter.cut(picture, by: SourceCutout(), forSource: source), picture, "nothing to cut")

        masker.answer = leftHalfMask
        let person = cutter.cut(picture, by: SourceCutout(removesBackground: true), forSource: source)
        XCTAssertEqual(pixel(person, x: 40, y: 90), [255, 0, 0, 255], "the person stays")
        XCTAssertEqual(pixel(person, x: 300, y: 90)[3], 0, "what is behind them goes")
        XCTAssertEqual(person.extent, bounds)

        masker.answer = nil
        let nobody = cutter.cut(picture, by: SourceCutout(removesBackground: true), forSource: source)
        XCTAssertEqual(pixel(nobody, x: 300, y: 90)[3], 255, "with nobody found the picture is left alone")

        let keyed = cutter.cut(picture, by: SourceCutout(chromaKey: .greenScreen), forSource: source)
        XCTAssertEqual(pixel(keyed, x: 300, y: 90)[3], 0, "green is keyed out")
        XCTAssertGreaterThan(pixel(keyed, x: 40, y: 90)[0], 240, "red is kept")
        // The same key again is drawn from what was kept the first time.
        XCTAssertEqual(pixel(cutter.cut(picture, by: SourceCutout(chromaKey: .greenScreen), forSource: source), x: 300, y: 90)[3], 0)

        var onRed = ChromaKeySettings.greenScreen
        (onRed.red, onRed.green) = (1, 0)
        let other = cutter.cut(picture, by: SourceCutout(chromaKey: onRed), forSource: source)
        XCTAssertEqual(pixel(other, x: 40, y: 90)[3], 0, "keyed on red instead")
        XCTAssertEqual(pixel(other, x: 300, y: 90)[3], 255)

        cutter.keepOnly([])
        XCTAssertEqual(pixel(cutter.cut(picture, by: SourceCutout(chromaKey: onRed), forSource: source), x: 40, y: 90)[3], 0)
    }

    func testASceneCutsItsSourcesOutBeforeItPlacesThem() {
        let registry = SourceRegistry(providers: [ShapeSourceProvider()])
        let renderer = SceneRenderer(
            sources: registry, effectFactory: NoEffectsAtAll(), canvas: canvas, cutter: SourceCutter(masker: FakeMasker())
        )
        let backdrop = ChainItem(
            content: .source(.shape(ShapeSettings(kind: .rectangle, color: RGBColor(red: 0, green: 0, blue: 1))))
        )
        var front = ChainItem(
            content: .source(.shape(ShapeSettings(kind: .rectangle, color: RGBColor(red: 0, green: 1, blue: 0)))),
            pictureInPicture: PictureInPictureSettings(center: CGPoint(x: 0.5, y: 0.5), scale: 0.5)
        )
        func middle() -> [Int] {
            let scene = SceneConfiguration(items: [backdrop, front])
            registry.setSourcesInUse(scene.sourcesInUse)
            return pixel(renderer.render(scene, time: 0), x: 160, y: 90)
        }
        XCTAssertGreaterThan(middle()[1], 200, "the green picture sits in front")
        front.cutout = SourceCutout(chromaKey: .greenScreen)
        let cut = middle()
        XCTAssertGreaterThan(cut[2], 200, "keyed out, the backdrop shows through it")
        XCTAssertLessThan(cut[1], 50)
    }
}

private final class NoEffectsAtAll: ImageEffectFactory {
    func makeEffect(named name: String, canvas: CGSize) -> ImageEffect? { nil }
}

final class SourceFitInASceneTests: XCTestCase {
    func testASquarePictureFillsTheFrameOrSitsBetweenBars() {
        let canvas = CGSize(width: 320, height: 180)
        let compositor = Compositor(canvas: canvas)
        let square = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        func red(_ fit: SourceFit, atX x: Int) -> Int {
            let frame = compositor.compose([.picture(square, placement: nil, fit: fit)], time: 0)
            return Int(makePixelAccess().rgba(of: frame, width: 320, height: 180)[(90 * 320 + x) * 4])
        }
        XCTAssertGreaterThan(red(.fill, atX: 10), 200, "filling, it reaches the sides")
        XCTAssertLessThan(red(.fit, atX: 10), 50, "fitted, there are bars at the sides")
        XCTAssertGreaterThan(red(.fit, atX: 160), 200)
        XCTAssertGreaterThan(red(.stretch, atX: 10), 200, "stretched, it reaches the sides too")
    }
}

final class CropInASceneTests: XCTestCase {
    func testCropOnTheMainChainBlanksTheSidesItTakesOff() {
        let canvas = CGSize(width: 320, height: 180)
        let library = NativeEffectLibrary(directory: URL(fileURLWithPath: "/effects"), effects: NativeEffect.studioFilters)
        let registry = SourceRegistry(providers: [ShapeSourceProvider()])
        let renderer = SceneRenderer(sources: registry, effectFactory: library, canvas: canvas, supplies: .system())
        let scene = SceneConfiguration(items: [
            ChainItem(content: .source(.shape(ShapeSettings(kind: .rectangle, color: RGBColor(red: 1, green: 0, blue: 0))))),
            ChainItem(content: .effect(name: "Crop", values: ["Left": .number(0.5)])),
        ])
        registry.setSourcesInUse(scene.sourcesInUse)
        let frame = renderer.render(scene, time: 0)
        XCTAssertEqual(frame.extent, CGRect(origin: .zero, size: canvas), "the frame is still the whole canvas")
        let bytes = makePixelAccess().rgba(of: frame, width: 320, height: 180)
        func red(atX x: Int) -> Int { Int(bytes[(90 * 320 + x) * 4]) }
        XCTAssertLessThan(red(atX: 40), 50, "the left half is gone")
        XCTAssertGreaterThan(red(atX: 280), 200, "the right half is still there")
    }
}
