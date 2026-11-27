import CamTwistCore
import CoreGraphics
import Foundation

/// A curly handlebar moustache under the nose, leaning and turning with
/// the head.
struct Moustache: Wearable {
    static let name = "Moustache"
    static let colorKey = "Color"
    private static let color = ColorControl(key: colorKey, displayName: "Color", red: 0, green: 0, blue: 0)

    /// The right half, in distances between the eyes, from the middle of the
    /// lip with up as up. The left half mirrors it.
    private enum Shape {
        static let top = CGPoint(x: 0, y: 0.06)
        /// The rounded top of the half, out to where it narrows.
        static let narrow = CGPoint(x: 0.4, y: 0.06)
        static let topBends = (CGPoint(x: 0.12, y: 0.16), CGPoint(x: 0.28, y: 0.16))
        /// The tip, curled up at the end.
        static let tip = CGPoint(x: 0.62, y: 0.12)
        static let tipBends = (CGPoint(x: 0.48, y: 0), CGPoint(x: 0.56, y: 0.02))
        /// Back along the underside to the middle.
        static let under = CGPoint(x: 0.36, y: -0.08)
        static let underBends = (CGPoint(x: 0.6, y: -0.02), CGPoint(x: 0.5, y: -0.1))
        static let bottom = CGPoint(x: 0, y: -0.02)
        static let bottomBends = (CGPoint(x: 0.22, y: -0.06), CGPoint(x: 0.1, y: -0.04))
        static let reach: CGFloat = 0.7
        static let sides: [CGFloat] = [-1, 1]
    }

    let parameters = [color.parameter]
    let reach = Shape.reach

    func anchor(on face: FaceExpression) -> CGPoint { face.upperLip }

    /// One unit is the distance between the eyes.
    func unit(on face: FaceExpression) -> CGFloat { face.eyeSpan }

    func draw(on face: FaceExpression, time: TimeInterval, values: [String: EffectValue], in context: CGContext) {
        let half = CGMutablePath()
        half.move(to: Shape.top)
        half.addCurve(to: Shape.narrow, control1: Shape.topBends.0, control2: Shape.topBends.1)
        half.addCurve(to: Shape.tip, control1: Shape.tipBends.0, control2: Shape.tipBends.1)
        half.addCurve(to: Shape.under, control1: Shape.underBends.0, control2: Shape.underBends.1)
        half.addCurve(to: Shape.bottom, control1: Shape.bottomBends.0, control2: Shape.bottomBends.1)
        half.closeSubpath()
        context.setFillColor(Self.color.value(in: values))
        for side in Shape.sides {
            context.saveGState()
            context.scaleBy(x: side, y: 1)
            context.addPath(half)
            context.fillPath()
            context.restoreGState()
        }
    }
}
