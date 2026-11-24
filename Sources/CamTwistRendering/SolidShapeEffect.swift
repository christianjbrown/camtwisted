import CamTwistCore
import CoreImage
import Foundation
import Metal
import SceneKit

/// Wraps a picture round a solid and hands back a picture of the solid,
/// clear around it.
protocol SolidRendering {
    /// `turn` and `tilt` are degrees about the upright and the level axis;
    /// `size` is the solid's share of the picture's height; `position` is
    /// where its middle sits, in the units overlays are placed in.
    func picture(
        of image: CIImage, on shape: SolidShape, turn: Double, tilt: Double, size: Double, position: CGPoint
    ) -> CIImage?
}

/// Draws the solid with SceneKit, on the graphics card.
final class SceneKitSolidStage: SolidRendering {
    private enum Stage {
        /// Drawn at twice the size and scaled down, which smooths the edges.
        static let oversampling: CGFloat = 2
        /// Every solid fits a unit cube, so a round one is half a unit across its radius.
        static let unitLength: CGFloat = 1
        static let roundRadius: CGFloat = 0.5
        static let cameraDistance: Float = 3
        /// The camera sees this many units from top to bottom at the solid.
        static let viewHeight: Double = 2
        static let keyLight: CGFloat = 900
        static let fillLight: CGFloat = 500
        static let keyLightPosition = SCNVector3(2, 3, 4)
        static let roundSegments = 72
        static let degreesToRadians = Float.pi / 180
    }

    private let canvas: CGSize
    private let queue: MTLCommandQueue
    private let input: MTLTexture
    private let output: MTLTexture
    private let depth: MTLTexture
    private let context: CIContext
    private let renderer: SCNRenderer
    private let solid = SCNNode()
    private let eye = SCNNode()
    private var shape: SolidShape?

    /// Nil when this Mac has no graphics card to draw with.
    init?(device: MTLDevice?, canvas: CGSize) {
        let width = Int(canvas.width * Stage.oversampling)
        let height = Int(canvas.height * Stage.oversampling)
        func texture(_ format: MTLPixelFormat, _ usage: MTLTextureUsage) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: width, height: height, mipmapped: false
            )
            descriptor.usage = usage
            return device?.makeTexture(descriptor: descriptor)
        }
        guard let device, let queue = device.makeCommandQueue(),
              let input = texture(.bgra8Unorm, [.shaderRead, .shaderWrite, .renderTarget]),
              let output = texture(.bgra8Unorm, [.shaderRead, .renderTarget]),
              let depth = texture(.depth32Float, [.renderTarget])
        else { return nil }
        self.canvas = canvas
        self.queue = queue
        self.input = input
        self.output = output
        self.depth = depth
        context = CIContext(mtlDevice: device)
        renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = Self.scene(holding: solid, seenFrom: eye)
        renderer.pointOfView = eye
    }

    func picture(
        of image: CIImage, on shape: SolidShape, turn: Double, tilt: Double, size: Double, position: CGPoint
    ) -> CIImage? {
        if self.shape != shape {
            self.shape = shape
            solid.geometry = Self.geometry(for: shape, aspect: canvas.width / canvas.height)
            solid.geometry?.firstMaterial?.diffuse.contents = input
        }
        let scale = Float(size * Stage.viewHeight)
        solid.scale = SCNVector3(scale, scale, scale)
        // Overlay positions run from -1 to 1 across the picture on both
        // axes; the stage is `viewHeight` tall and wider by the picture's shape.
        let halfWidth = Stage.viewHeight / 2 * canvas.width / canvas.height
        solid.position = SCNVector3(Float(position.x * halfWidth), Float(position.y * halfWidth), 0)
        solid.eulerAngles = SCNVector3(
            Float(tilt) * Stage.degreesToRadians, Float(turn) * Stage.degreesToRadians, 0
        )
        // SceneKit applies changes at the end of a run loop turn, and this
        // runs where there is none, so they are pushed through by hand.
        SCNTransaction.flush()
        let bounds = CGRect(x: 0, y: 0, width: input.width, height: input.height)
        // Scaled up to the stage's size and turned over: Core Image's rows
        // run up, and a texture's run down.
        let stretched = image.transformed(
            by: CGAffineTransform(scaleX: Stage.oversampling, y: -Stage.oversampling)
                .concatenating(CGAffineTransform(translationX: 0, y: bounds.height))
        )
        return queue.makeCommandBuffer().flatMap { buffer in
            context.render(stretched, to: input, commandBuffer: buffer, bounds: bounds, colorSpace: SRGBColorSpace.shared)
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            pass.depthAttachment.texture = depth
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1
            renderer.render(atTime: 0, viewport: bounds, commandBuffer: buffer, passDescriptor: pass)
            buffer.commit()
            buffer.waitUntilCompleted()
            // Metal's rows run down and Core Image's up, so the picture is
            // turned the right way up as it is scaled back down.
            let shrink = 1 / Stage.oversampling
            return CIImage(mtlTexture: output, options: [.colorSpace: SRGBColorSpace.shared])
                .map { $0.transformed(by: CGAffineTransform(scaleX: shrink, y: -shrink)
                    .concatenating(CGAffineTransform(translationX: 0, y: canvas.height))) }
        }
    }

    private static func scene(holding solid: SCNNode, seenFrom eye: SCNNode) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = nil
        scene.rootNode.addChildNode(solid)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = false
        // The view is as tall as `viewHeight` where the solid stands.
        camera.fieldOfView = CGFloat(2 * atan(Stage.viewHeight / 2 / Double(Stage.cameraDistance)) * 180 / .pi)
        eye.camera = camera
        eye.position = SCNVector3(0, 0, Stage.cameraDistance)
        scene.rootNode.addChildNode(eye)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = Stage.keyLight
        key.position = Stage.keyLightPosition
        scene.rootNode.addChildNode(key)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = Stage.fillLight
        scene.rootNode.addChildNode(fill)
        return scene
    }

    /// Each solid is one unit tall. A cube's square faces show the middle
    /// of the picture, so it is not squashed; a box's faces take the
    /// picture's own shape and show all of it.
    private static func geometry(for shape: SolidShape, aspect: CGFloat) -> SCNGeometry {
        let geometry: SCNGeometry
        let material = SCNMaterial()
        switch shape {
        case .cube:
            geometry = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
            // A square as tall as the picture, cut from its middle.
            let share = 1 / aspect
            material.diffuse.contentsTransform = SCNMatrix4Translate(
                SCNMatrix4MakeScale(share, 1, 1), (1 - share) / 2, 0, 0
            )
        case .box:
            geometry = SCNBox(width: aspect, height: 1, length: aspect, chamferRadius: 0)
        case .sphere:
            let sphere = SCNSphere(radius: Stage.roundRadius)
            sphere.segmentCount = Stage.roundSegments
            geometry = sphere
        case .cylinder:
            let cylinder = SCNCylinder(radius: Stage.roundRadius, height: Stage.unitLength)
            cylinder.radialSegmentCount = Stage.roundSegments
            geometry = cylinder
        case .cone:
            let cone = SCNCone(topRadius: 0, bottomRadius: Stage.roundRadius, height: Stage.unitLength)
            cone.radialSegmentCount = Stage.roundSegments
            geometry = cone
        case .pyramid:
            geometry = SCNPyramid(width: Stage.unitLength, height: Stage.unitLength, length: Stage.unitLength)
        }
        material.lightingModel = .lambert
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }
}

/// The picture wrapped round a turning solid: a cube, sphere, cylinder,
/// cone or pyramid.
public final class SolidShapeEffect: ImageEffect {
    public static let name = "3D Shape"
    public static let shapeKey = "Shape"
    public static let turnRateKey = "Turns_A_Second"
    public static let tumbleRateKey = "Tumbles_A_Second"
    public static let turnKey = "Turn"
    public static let tiltKey = "Tilt"
    public static let sizeKey = EffectParameterKey.size
    public static let xKey = EffectParameterKey.xPosition
    public static let yKey = EffectParameterKey.yPosition

    /// One turn, and one tumble, every twenty seconds.
    private static let defaultRate = 0.05
    private static let rateRange: ClosedRange<Double> = 0...1
    private static let defaultTilt = 15.0
    private static let angleRange: ClosedRange<Double> = -180...180
    private static let defaultSize = 0.6
    private static let sizeRange: ClosedRange<Double> = 0.1...1.5

    public static let parameters = [
        EffectParameter(
            key: shapeKey, displayName: "Shape", kind: .string, defaultValue: .string(SolidShape.cube.rawValue),
            choices: SolidShape.allCases.map(\.rawValue)
        ),
        EffectParameter(
            key: turnRateKey, displayName: "Turns a second", kind: .number, defaultValue: .number(defaultRate),
            range: rateRange
        ),
        EffectParameter(
            key: tumbleRateKey, displayName: "Tumbles a second", kind: .number, defaultValue: .number(defaultRate),
            range: rateRange
        ),
        EffectParameter(key: turnKey, displayName: "Turn", kind: .number, defaultValue: .number(0), range: angleRange),
        EffectParameter(
            key: tiltKey, displayName: "Tilt", kind: .number, defaultValue: .number(defaultTilt), range: angleRange
        ),
        EffectParameter(key: sizeKey, displayName: "Size", kind: .number, defaultValue: .number(defaultSize), range: sizeRange),
        EffectParameter(key: xKey, displayName: "X Position", kind: .number, defaultValue: .number(0), range: OverlayRange.position),
        EffectParameter(key: yKey, displayName: "Y Position", kind: .number, defaultValue: .number(0), range: OverlayRange.position),
    ]

    private let stage: SolidRendering?
    private var values: [String: EffectValue] = [:]

    init(stage: SolidRendering?) {
        self.stage = stage
    }

    public func setValues(_ values: [String: EffectValue]) {
        self.values = values
    }

    public func apply(to image: CIImage, time: TimeInterval) -> CIImage {
        let turn = SolidSpin.angle(
            at: time, turnsPerSecond: values.number(Self.turnRateKey, default: Self.defaultRate),
            startingAt: values.number(Self.turnKey, default: 0)
        )
        let picture = stage?.picture(
            of: image, on: SolidShape(named: values.string(Self.shapeKey, default: SolidShape.cube.rawValue)),
            turn: turn,
            tilt: SolidSpin.angle(
                at: time, turnsPerSecond: values.number(Self.tumbleRateKey, default: Self.defaultRate),
                startingAt: values.number(Self.tiltKey, default: Self.defaultTilt)
            ),
            size: values.number(Self.sizeKey, default: Self.defaultSize),
            position: CGPoint(x: values.number(Self.xKey, default: 0), y: values.number(Self.yKey, default: 0))
        )
        // With no graphics card to draw on, the picture passes through.
        return picture ?? image
    }
}

public extension NativeEffect {
    /// The picture on a turning cube, sphere, cylinder, cone or pyramid.
    static var solidShape: NativeEffect {
        NativeEffect(name: SolidShapeEffect.name, kind: .filter, parameters: SolidShapeEffect.parameters) {
            SolidShapeEffect(stage: SceneKitSolidStage(device: MTLCreateSystemDefaultDevice(), canvas: $0))
        }
    }
}
