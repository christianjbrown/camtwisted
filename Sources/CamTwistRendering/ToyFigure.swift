import CamTwistCore
import CoreGraphics
import CoreImage
import Foundation
import Metal

/// How the toy figure is built. Every length is a share of the head's height.
enum ToyBuild {
    static let headRadius: CGFloat = 0.575
    static let headHeight: CGFloat = 1
    /// The rounding of the head's top and bottom edges.
    static let headRim: CGFloat = 0.2
    /// The face is a picture wrapped round the front of the head. It
    /// covers this share of the way round, and so is this wide.
    static let faceShare: CGFloat = 1 / 3
    static let faceWidth = 2 * CGFloat.pi * headRadius * faceShare
}

/// The toy figure's colours.
enum ToyPaint {
    static let yellow = CGColor(srgbRed: 0.97, green: 0.82, blue: 0.09, alpha: 1)
    static let noseShade = CGColor(srgbRed: 0.78, green: 0.62, blue: 0.05, alpha: 1)
    static let red = CGColor(srgbRed: 0.84, green: 0.12, blue: 0.08, alpha: 1)
    static let ink = CGColor(srgbRed: 0.1, green: 0.08, blue: 0.06, alpha: 1)
    static let mouth = CGColor(srgbRed: 0.25, green: 0.04, blue: 0.04, alpha: 1)
    static let tongue = CGColor(srgbRed: 0.9, green: 0.3, blue: 0.3, alpha: 1)
    static let glint = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
}

/// Where the toy figure stands and how its head is turned.
struct ToyFigurePose: Equatable {
    /// The middle of the head, in the picture's points.
    var centre: CGPoint
    /// The head's height in points.
    var headHeight: CGFloat
    /// Radians: to the right of the picture, upwards, and anticlockwise.
    var yaw: CGFloat
    var pitch: CGFloat
    var roll: CGFloat
}

/// Draws the figure as a solid thing, from a picture of its face.
protocol ToyFigureStaging {
    func picture(face: CGImage, pose: ToyFigurePose) -> CIImage?
}

/// A little plastic toy figure: a round yellow head with a stud on top and
/// a red T-shirt. Its eyes, brows, nose and mouth follow the person's, and
/// its head turns, nods and leans with theirs.
struct ToyFigure: CharacterDrawing {
    static let name = "Toy Figure"

    private enum Fit {
        /// The toy's head against the person's face, brow to chin.
        static let headScale: CGFloat = 1.5
        /// How far the head turns and nods when the person's is turned or
        /// nodded as far as can be read, in radians.
        static let widestTurn: CGFloat = 0.9
        static let deepestNod: CGFloat = 0.7
    }

    private let stage: ToyFigureStaging?
    private let painter: ToyFacePainting

    /// - Parameter stage: nil when this Mac has nothing to draw solids with.
    init(stage: ToyFigureStaging?, painter: ToyFacePainting) {
        self.stage = stage
        self.painter = painter
    }

    func picture(of expression: FaceExpression) -> CIImage? {
        painter.face(for: expression).flatMap { stage?.picture(face: $0, pose: Self.pose(for: expression)) }
    }

    static func pose(for expression: FaceExpression) -> ToyFigurePose {
        ToyFigurePose(
            centre: expression.centre,
            headHeight: expression.height * Fit.headScale,
            yaw: expression.turn * Fit.widestTurn,
            pitch: expression.nod * Fit.deepestNod,
            roll: expression.roll
        )
    }
}

/// Paints a figure's face as a flat picture, to be wrapped round its head.
protocol ToyFacePainting {
    /// The face as a picture, or nil when it cannot be drawn.
    func face(for expression: FaceExpression) -> CGImage?
}

/// Paints the toy figure's face, flat, to be wrapped round its head.
struct ToyFacePainter: ToyFacePainting {
    private enum Face {
        static let eyeAcross: CGFloat = 0.2
        static let eyeUp: CGFloat = 0.1
        static let eyeRadius: CGFloat = 0.065
        /// A shut eye is still a line.
        static let eyeShut: CGFloat = 0.15
        /// The glint shows once an eye is at least this far open.
        static let glintFrom: CGFloat = 0.5
        static let glintOffset = CGPoint(x: 0.02, y: 0.025)
        static let glintRadius: CGFloat = 0.022

        static let browUp: CGFloat = 0.24
        static let browHalfWidth: CGFloat = 0.09
        static let browLift: CGFloat = 0.05
        static let lineWidth: CGFloat = 0.03

        static let noseUp: CGFloat = -0.04
        static let noseHalfWidth: CGFloat = 0.04
        static let noseDip: CGFloat = 0.05

        static let mouthUp: CGFloat = -0.2
        static let mouthHalfWidth: CGFloat = 0.2
        /// How much wider a broad smile is, and how far its corners lift.
        static let smileWidening: CGFloat = 0.25
        static let cornerLift: CGFloat = 0.06
        /// The middle of the top lip against its corners: a little below
        /// them at rest, and further the more the corners lift.
        static let restingDip: CGFloat = 0.02
        static let dipForLift: CGFloat = 1.5
        /// How far a wide open mouth drops, and how open it has to be
        /// before it is drawn as more than a line.
        static let drop: CGFloat = 0.2
        static let openFrom: CGFloat = 0.02
        /// The bottom lip's curve is pulled this many times its drop.
        static let curvePull: CGFloat = 2
        static let tongueHalfWidth: CGFloat = 0.11
        static let tongueHeight: CGFloat = 0.12
    }

    /// The usual height of the picture in points. It is drawn with more
    /// detail than that, as all canvas drawing is.
    static let usualHeight: CGFloat = 400

    private let size: CGSize

    /// - Parameter height: how tall the picture is, in points.
    init(height: CGFloat) {
        size = CGSize(width: (height * ToyBuild.faceWidth).rounded(), height: height)
    }

    /// The face as a picture, or nil when it has no size to be drawn at.
    func face(for expression: FaceExpression) -> CGImage? {
        CanvasDrawing.bitmap(size: size) { context in
            context.setFillColor(ToyPaint.yellow)
            context.fill(CGRect(origin: .zero, size: size))
            // From here on one unit is the height of the head, from its middle.
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: size.height, y: size.height)
            drawEyes(expression, in: context)
            drawNose(in: context)
            drawMouth(expression, in: context)
        }
    }

    private func drawEyes(_ expression: FaceExpression, in context: CGContext) {
        context.setLineWidth(Face.lineWidth)
        context.setLineCap(.round)
        context.setStrokeColor(ToyPaint.ink)
        let eyes: [(side: CGFloat, open: CGFloat, brow: CGFloat)] = [
            (-1, expression.leftEyeOpen, expression.leftBrow), (1, expression.rightEyeOpen, expression.rightBrow),
        ]
        for eye in eyes {
            let centre = CGPoint(x: eye.side * Face.eyeAcross, y: Face.eyeUp)
            let tall = Face.eyeRadius * max(eye.open, Face.eyeShut)
            context.setFillColor(ToyPaint.ink)
            context.fillEllipse(in: CGRect(
                x: centre.x - Face.eyeRadius, y: centre.y - tall, width: Face.eyeRadius * 2, height: tall * 2
            ))
            if eye.open >= Face.glintFrom {
                context.setFillColor(ToyPaint.glint)
                context.fillEllipse(in: CGRect(
                    x: centre.x + Face.glintOffset.x - Face.glintRadius,
                    y: centre.y + Face.glintOffset.y - Face.glintRadius,
                    width: Face.glintRadius * 2, height: Face.glintRadius * 2
                ))
            }
            let brow = Face.browUp + eye.brow * Face.browLift
            context.move(to: CGPoint(x: centre.x - Face.browHalfWidth, y: brow))
            context.addLine(to: CGPoint(x: centre.x + Face.browHalfWidth, y: brow))
            context.strokePath()
        }
    }

    private func drawNose(in context: CGContext) {
        context.setStrokeColor(ToyPaint.noseShade)
        context.move(to: CGPoint(x: -Face.noseHalfWidth, y: Face.noseUp))
        context.addQuadCurve(
            to: CGPoint(x: Face.noseHalfWidth, y: Face.noseUp), control: CGPoint(x: 0, y: Face.noseUp - Face.noseDip)
        )
        context.strokePath()
    }

    private func drawMouth(_ expression: FaceExpression, in context: CGContext) {
        let halfWidth = Face.mouthHalfWidth * (1 + Face.smileWidening * expression.smile)
        let lift = Face.cornerLift * expression.smile
        let left = CGPoint(x: -halfWidth, y: Face.mouthUp + lift)
        let right = CGPoint(x: halfWidth, y: Face.mouthUp + lift)
        let top = CGPoint(x: 0, y: Face.mouthUp - lift * Face.dipForLift - Face.restingDip)
        let drop = Face.drop * expression.mouthOpen

        context.setStrokeColor(ToyPaint.ink)
        guard drop > Face.openFrom else {
            // Closed: a single line, curved by the smile.
            context.move(to: left)
            context.addQuadCurve(to: right, control: top)
            context.strokePath()
            return
        }
        let lips = CGMutablePath()
        lips.move(to: left)
        lips.addQuadCurve(to: right, control: top)
        lips.addQuadCurve(to: left, control: CGPoint(x: top.x, y: top.y - drop * Face.curvePull))
        lips.closeSubpath()

        context.saveGState()
        context.addPath(lips)
        context.clip()
        context.setFillColor(ToyPaint.mouth)
        context.fill(lips.boundingBoxOfPath)
        context.setFillColor(ToyPaint.tongue)
        let floor = top.y - drop
        context.fillEllipse(in: CGRect(
            x: -Face.tongueHalfWidth, y: floor - Face.tongueHeight, width: Face.tongueHalfWidth * 2, height: Face.tongueHeight
        ))
        context.restoreGState()
        context.addPath(lips)
        context.strokePath()
    }
}

extension NativeEffect {
    /// The effects that follow a face: characters that stand in for the
    /// person, and things the person wears.
    static func characters(tuning: EffectTuning, tracker: @escaping () -> FaceTracking) -> [NativeEffect] {
        func follower(in canvas: CGSize, share: Double) -> FaceFollower {
            FaceFollower(
                tracker: tracker(),
                smoother: ExpressionSmoother(start: .resting(in: canvas), share: CGFloat(share)),
                reader: MeasuringFaceReader(),
                patience: tuning.faceFramesHeld
            )
        }
        /// Something worn follows the head quickly, so it does not trail behind it.
        func worn(_ name: String, _ item: Wearable) -> NativeEffect {
            NativeEffect(name: name, kind: .filter, parameters: WornEffect.parameters(for: item)) { canvas in
                WornEffect(
                    canvas: canvas, follower: follower(in: canvas, share: tuning.wornSmoothing), item: item
                )
            }
        }
        return [
            NativeEffect(name: ToyFigure.name, kind: .filter, parameters: CharacterEffect.parameters) { canvas in
                CharacterEffect(
                    canvas: canvas,
                    follower: follower(in: canvas, share: tuning.characterSmoothing),
                    character: ToyFigure(
                        stage: SceneKitToyFigureStage(
                            device: MTLCreateSystemDefaultDevice(), canvas: canvas, model: ToyFigureModel(canvas: canvas)
                        ),
                        painter: ToyFacePainter(height: ToyFacePainter.usualHeight)
                    )
                )
            },
            worn(Antennae.name, Antennae()),
            worn(PixelSunglasses.name, PixelSunglasses()),
            NativeEffect(name: BigEyesEffect.name, kind: .filter, parameters: BigEyesEffect.parameters) { canvas in
                BigEyesEffect(canvas: canvas, follower: follower(in: canvas, share: tuning.wornSmoothing))
            },
        ]
    }
}
