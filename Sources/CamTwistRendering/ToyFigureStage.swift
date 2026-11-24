import AppKit
import CamTwistCore
import CoreImage
import Foundation
import Metal
import SceneKit

/// A figure made of solids, standing in a scene of its own, that can be
/// stood somewhere, turned, and given a face.
protocol FigureModel {
    /// The scene the figure stands in, and where it is looked at from.
    var scene: SCNScene { get }
    var eye: SCNNode { get }
    /// Stands the figure where the pose says and wraps the face round its head.
    func take(_ pose: ToyFigurePose, face: CGImage)
}

/// The toy figure as solids: a lathe-turned head with a stud, a neck, a
/// shirt, arms and hands. The camera has no perspective, so one unit of
/// the scene is one point of the picture and the figure lands exactly on
/// the face.
final class ToyFigureModel: FigureModel {
    private enum Stage {
        /// The camera stands well back from the figure, and sees this far.
        static let cameraDistance: CGFloat = 10_000
        static let nearest: Double = 1
        static let furthest: Double = 20_000
        static let keyLight: CGFloat = 450
        static let fillLight: CGFloat = 650
        /// The key light comes down from over the viewer's left shoulder.
        static let keyLightAngles = SCNVector3(-0.6, -0.5, 0)
        /// A little shine, as plastic has.
        static let shine = NSColor(white: 0.35, alpha: 1)
        static let shininess: CGFloat = 0.6
    }

    /// The parts of the figure. Lengths are shares of the head's height,
    /// measured from the middle of the head.
    private enum Part {
        static let roundSegments = 72
        static let rimSteps = 8
        static let studRadius: CGFloat = 0.3
        static let studHeight: CGFloat = 0.2
        static let studUp: CGFloat = 0.6
        static let neckRadius: CGFloat = 0.33
        /// The head turns about the middle of the shirt's top, this far
        /// below the middle of the head, and the neck turns with it.
        static let headAbovePivot: CGFloat = 0.65
        /// The neck runs from a little inside the shirt to a little inside the head.
        static let neckHeight: CGFloat = 0.35
        static let neckAbovePivot: CGFloat = 0.075
        /// The shirt, seen from the front, and how deep it is front to back.
        static let torso = [
            CGPoint(x: -0.72, y: -0.65), CGPoint(x: 0.72, y: -0.65), CGPoint(x: 0.95, y: -2.4), CGPoint(x: -0.95, y: -2.4),
        ]
        static let torsoDepth: CGFloat = 0.8
        static let armRadius: CGFloat = 0.17
        static let armLength: CGFloat = 1.2
        static let armPlace = SCNVector3(0.98, -1.3, 0)
        static let armLean: CGFloat = 0.3
        static let handRadius: CGFloat = 0.2
        static let handPlace = SCNVector3(1.17, -1.95, 0)
        static let sides: [CGFloat] = [-1, 1]
    }

    let scene = SCNScene()
    let eye = SCNNode()
    private let canvas: CGSize
    private let figure = SCNNode()
    /// Where the neck meets the shirt. The neck and the head hang off it.
    private let neck = SCNNode()
    private let face = SCNMaterial()

    init(canvas: CGSize) {
        self.canvas = canvas
        setUpEye()
        setUpScene()
        build()
    }

    func take(_ pose: ToyFigurePose, face image: CGImage) {
        face.diffuse.contents = image
        figure.scale = SCNVector3(pose.headHeight, pose.headHeight, pose.headHeight)
        // Turning about the level axis the right-handed way tips the face
        // down, so looking up is a turn the other way.
        neck.eulerAngles = SCNVector3(-pose.pitch, pose.yaw, pose.roll)
        // The head swings on its neck, so the whole figure is moved to
        // keep the middle of the head on the middle of the face.
        let swung = neck.simdConvertPosition(SIMD3(0, Float(Part.headAbovePivot), 0), to: figure)
        figure.position = SCNVector3(
            pose.centre.x - canvas.width / 2 - CGFloat(swung.x) * pose.headHeight,
            pose.centre.y - canvas.height / 2 - CGFloat(swung.y) * pose.headHeight,
            0
        )
    }

    private func setUpEye() {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        // Half the height of what the camera sees: the whole picture.
        camera.orthographicScale = Double(canvas.height / 2)
        camera.zNear = Stage.nearest
        camera.zFar = Stage.furthest
        eye.camera = camera
        eye.position = SCNVector3(0, 0, Stage.cameraDistance)
    }

    private func setUpScene() {
        scene.background.contents = nil
        scene.rootNode.addChildNode(figure)
        scene.rootNode.addChildNode(eye)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = Stage.keyLight
        key.eulerAngles = Stage.keyLightAngles
        scene.rootNode.addChildNode(key)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = Stage.fillLight
        scene.rootNode.addChildNode(fill)
    }

    private static func finish(_ material: SCNMaterial) {
        material.lightingModel = .blinn
        material.specular.contents = Stage.shine
        material.shininess = Stage.shininess
        material.isDoubleSided = true
    }

    private static func part(_ geometry: SCNGeometry, _ color: CGColor, at place: SCNVector3) -> SCNNode {
        let material = SCNMaterial()
        material.diffuse.contents = color
        finish(material)
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = place
        return node
    }

    private func build() {
        // The body first: it stays upright while the head moves.
        let outline = NSBezierPath()
        outline.move(to: Part.torso[0])
        Part.torso.dropFirst().forEach(outline.line(to:))
        outline.close()
        figure.addChildNode(Self.part(
            SCNShape(path: outline, extrusionDepth: Part.torsoDepth), ToyPaint.red, at: SCNVector3(0, 0, 0)
        ))
        for side in Part.sides {
            let arm = Self.part(
                SCNCapsule(capRadius: Part.armRadius, height: Part.armLength), ToyPaint.red,
                at: SCNVector3(Part.armPlace.x * side, Part.armPlace.y, Part.armPlace.z)
            )
            arm.eulerAngles = SCNVector3(0, 0, Part.armLean * side)
            figure.addChildNode(arm)
            figure.addChildNode(Self.part(
                SCNSphere(radius: Part.handRadius), ToyPaint.yellow,
                at: SCNVector3(Part.handPlace.x * side, Part.handPlace.y, Part.handPlace.z)
            ))
        }
        // The neck stays joined to the middle of the shirt's top and the
        // middle of the head's base, however the head moves.
        neck.position = SCNVector3(0, -Part.headAbovePivot, 0)
        neck.addChildNode(Self.part(
            SCNCylinder(radius: Part.neckRadius, height: Part.neckHeight), ToyPaint.yellow,
            at: SCNVector3(0, Part.neckAbovePivot, 0)
        ))
        let head = SCNNode(geometry: headGeometry())
        head.position = SCNVector3(0, Part.headAbovePivot, 0)
        let stud = SCNCylinder(radius: Part.studRadius, height: Part.studHeight)
        stud.radialSegmentCount = Part.roundSegments
        head.addChildNode(Self.part(stud, ToyPaint.yellow, at: SCNVector3(0, Part.studUp, 0)))
        neck.addChildNode(head)
        figure.addChildNode(neck)
    }

    /// The head: a cylinder with rounded edges, turned as on a lathe, with
    /// the picture of the face wrapped round its front.
    private func headGeometry() -> SCNGeometry {
        let mesh = RevolvedSolid.mesh(
            profile: RevolvedSolid.roundedCylinder(
                radius: Float(ToyBuild.headRadius), height: Float(ToyBuild.headHeight), rim: Float(ToyBuild.headRim),
                steps: Part.rimSteps
            ),
            segments: Part.roundSegments
        )
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: mesh.positions.map { SCNVector3($0) }),
                SCNGeometrySource(normals: mesh.normals.map { SCNVector3($0) }),
                // A picture's rows run down from the top; the mesh counts up from the bottom.
                SCNGeometrySource(textureCoordinates: mesh.coordinates.map {
                    CGPoint(x: CGFloat($0.x), y: CGFloat(1 - $0.y))
                }),
            ],
            elements: [SCNGeometryElement(indices: mesh.triangles, primitiveType: .triangles)]
        )
        // The picture covers only the front of the head. Round the rest,
        // its yellow edge is carried on.
        let stretch = 1 / ToyBuild.faceShare
        face.diffuse.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(stretch, 1, 1), (1 - stretch) / 2, 0, 0)
        face.diffuse.wrapS = .clamp
        face.diffuse.wrapT = .clamp
        face.diffuse.contents = ToyPaint.yellow
        Self.finish(face)
        geometry.materials = [face]
        return geometry
    }
}

/// Draws a figure's scene with SceneKit, on the graphics card, and hands
/// back a picture of it the size of the canvas, clear around the figure.
final class SceneKitToyFigureStage: ToyFigureStaging {
    private enum Drawing {
        /// Drawn at twice the size and scaled down, which smooths the edges.
        static let oversampling: CGFloat = 2
        /// SceneKit works in plain light, not screen values, and its
        /// texture hands the picture back the same way.
        static let textureSpace = SRGBColorSpace.make(named: CGColorSpace.linearSRGB)
    }

    private let canvas: CGSize
    private let model: FigureModel
    private let queue: MTLCommandQueue
    private let output: MTLTexture
    private let depth: MTLTexture
    private let renderer: SCNRenderer

    /// Nil when this Mac has no graphics card to draw with.
    init?(device: MTLDevice?, canvas: CGSize, model: FigureModel) {
        func texture(_ format: MTLPixelFormat) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: Int(canvas.width * Drawing.oversampling),
                height: Int(canvas.height * Drawing.oversampling), mipmapped: false
            )
            descriptor.usage = [.shaderRead, .renderTarget]
            return device?.makeTexture(descriptor: descriptor)
        }
        guard let device, let queue = device.makeCommandQueue(),
              let output = texture(.bgra8Unorm_srgb), let depth = texture(.depth32Float)
        else { return nil }
        self.canvas = canvas
        self.model = model
        self.queue = queue
        self.output = output
        self.depth = depth
        renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = model.scene
        renderer.pointOfView = model.eye
    }

    func picture(face image: CGImage, pose: ToyFigurePose) -> CIImage? {
        model.take(pose, face: image)
        // SceneKit applies changes at the end of a run loop turn, and this
        // runs where there is none, so they are pushed through by hand.
        SCNTransaction.flush()

        let bounds = CGRect(x: 0, y: 0, width: output.width, height: output.height)
        return queue.makeCommandBuffer().flatMap { buffer in
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
            let shrink = 1 / Drawing.oversampling
            return CIImage(mtlTexture: output, options: [.colorSpace: Drawing.textureSpace])
                .map { $0.transformed(by: CGAffineTransform(scaleX: shrink, y: -shrink)
                    .concatenating(CGAffineTransform(translationX: 0, y: canvas.height))) }
        }
    }
}
