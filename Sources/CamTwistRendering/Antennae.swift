import CamTwistCore
import CoreGraphics
import Foundation

/// A pair of cartoon alien antennae. They grow from the top of the head,
/// lean, turn and nod with it, and bob a little by themselves.
struct Antennae: Wearable {
    static let name = "Alien Antennae"
    static let colorKey = "Color"
    /// An alien green.
    private static let color = ColorControl(key: colorKey, displayName: "Color", red: 0.45, green: 0.85, blue: 0.3)

    /// Every length is a share of the face's height, brow to chin, measured
    /// from the top of the head with the head upright.
    private enum Shape {
        /// Where a stalk leaves the head, on the right: just inside the
        /// top of it, so it never floats free. The other mirrors it.
        static let root = CGPoint(x: 0.22, y: -0.08)
        /// Where it ends, and the point its curve is pulled towards.
        static let tip = CGPoint(x: 0.42, y: 0.5)
        static let bend = CGPoint(x: 0.2, y: 0.35)
        static let stalkWidth: CGFloat = 0.04
        static let ballRadius: CGFloat = 0.085
        /// The shine on each ball: where it sits and how big it is.
        static let shineOffset = CGPoint(x: -0.025, y: 0.03)
        static let shineRadius: CGFloat = 0.028
        /// How far the tips lean over as the head turns and lift as it nods.
        static let turnLean: CGFloat = 0.15
        static let nodLift: CGFloat = 0.08
        /// The bob: how far the tips sway, how many times a second, and
        /// how far out of step the two are, in turns.
        static let sway: CGFloat = 0.025
        static let swaysPerSecond = 0.7
        static let outOfStep = 0.25
        static let reach: CGFloat = 0.8
        static let sides: [CGFloat] = [-1, 1]
    }

    private enum Paint {
        /// The stalks are the colour of the balls, darkened by this much black laid over them.
        static let stalkShade = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3)
        static let shine = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.8)
    }

    private static let fullTurn = 2 * Double.pi

    let parameters = [color.parameter]
    let reach = Shape.reach

    func anchor(on face: FaceExpression) -> CGPoint { face.crown }

    func unit(on face: FaceExpression) -> CGFloat { face.height }

    func draw(on face: FaceExpression, time: TimeInterval, values: [String: EffectValue], in context: CGContext) {
        let color = Self.color.value(in: values)
        context.setLineWidth(Shape.stalkWidth)
        context.setLineCap(.round)
        for (index, side) in Shape.sides.enumerated() {
            let phase = (time * Shape.swaysPerSecond + Double(index) * Shape.outOfStep) * Self.fullTurn
            let tip = CGPoint(
                x: side * Shape.tip.x + face.turn * Shape.turnLean + CGFloat(sin(phase)) * Shape.sway,
                y: Shape.tip.y + face.nod * Shape.nodLift
            )
            let root = CGPoint(x: side * Shape.root.x, y: Shape.root.y)
            let bend = CGPoint(x: side * Shape.bend.x, y: Shape.bend.y)
            for paint in [color, Paint.stalkShade] {
                context.setStrokeColor(paint)
                context.move(to: root)
                context.addQuadCurve(to: tip, control: bend)
                context.strokePath()
            }

            context.setFillColor(color)
            context.fillEllipse(in: CGRect(
                x: tip.x - Shape.ballRadius, y: tip.y - Shape.ballRadius,
                width: Shape.ballRadius * 2, height: Shape.ballRadius * 2
            ))
            context.setFillColor(Paint.shine)
            context.fillEllipse(in: CGRect(
                x: tip.x + Shape.shineOffset.x - Shape.shineRadius, y: tip.y + Shape.shineOffset.y - Shape.shineRadius,
                width: Shape.shineRadius * 2, height: Shape.shineRadius * 2
            ))
        }
    }
}
