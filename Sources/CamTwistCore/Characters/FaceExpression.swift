import CoreGraphics
import Foundation

/// Where the parts of one face are in a picture, in the picture's own
/// points with the origin at the bottom left.
public struct FaceLandmarks: Equatable, Sendable {
    /// The face as a whole, from brow to chin.
    public var box: CGRect
    /// The outlines of the two eyes and the two brows. Either way round:
    /// the reader sorts each pair by where it sits in the picture.
    public var eyes: [[CGPoint]]
    public var brows: [[CGPoint]]
    public var nose: [CGPoint]
    /// The outside and the inside edge of the lips.
    public var outerLips: [CGPoint]
    public var innerLips: [CGPoint]

    public init(
        box: CGRect, eyes: [[CGPoint]], brows: [[CGPoint]], nose: [CGPoint], outerLips: [CGPoint], innerLips: [CGPoint]
    ) {
        self.box = box
        self.eyes = eyes
        self.brows = brows
        self.nose = nose
        self.outerLips = outerLips
        self.innerLips = innerLips
    }
}

/// What a face is doing, in terms any character can act out. "Left" is the
/// left of the picture, whichever side of the person that is.
public struct FaceExpression: Equatable, Sendable {
    private enum Resting {
        /// Where a face nobody has seen yet is taken to be: the middle,
        /// a little above half way up, about a third of the picture tall.
        static let centre = CGPoint(x: 0.5, y: 0.6)
        static let height: CGFloat = 0.3
        static let smile: CGFloat = 0.5
        /// The top of a head is about this many face heights above the
        /// middle of its face.
        static let crownAbove: CGFloat = 0.7
        /// The eyes are about this many face heights above the middle of
        /// the face, and this many apart.
        static let eyesAbove: CGFloat = 0.15
        static let eyesApart: CGFloat = 0.45
    }

    /// The middle of the face, in the picture's points.
    public var centre: CGPoint
    /// How tall the face is, brow to chin, in points.
    public var height: CGFloat
    /// The top of the head, in the picture's points.
    public var crown: CGPoint
    /// The point half way between the eyes, and how far apart they are.
    public var eyeLine: CGPoint
    public var eyeSpan: CGFloat
    /// The head's lean, in radians anticlockwise.
    public var roll: CGFloat
    /// Which way the head faces: -1 to the left of the picture, 1 to the right.
    public var turn: CGFloat
    /// -1 looking down, 1 looking up.
    public var nod: CGFloat
    /// 0 shut, 1 wide open.
    public var leftEyeOpen: CGFloat
    public var rightEyeOpen: CGFloat
    /// -1 lowered, 1 raised.
    public var leftBrow: CGFloat
    public var rightBrow: CGFloat
    /// 0 closed, 1 wide open.
    public var mouthOpen: CGFloat
    /// -1 pursed, 1 a broad smile.
    public var smile: CGFloat

    public init(
        centre: CGPoint, height: CGFloat, crown: CGPoint? = nil, eyeLine: CGPoint? = nil, eyeSpan: CGFloat? = nil,
        roll: CGFloat = 0, turn: CGFloat = 0, nod: CGFloat = 0,
        leftEyeOpen: CGFloat = 1, rightEyeOpen: CGFloat = 1, leftBrow: CGFloat = 0, rightBrow: CGFloat = 0,
        mouthOpen: CGFloat = 0, smile: CGFloat = 0
    ) {
        self.centre = centre
        self.height = height
        // Where it has not been measured, the top of the head is taken
        // to be straight above the face.
        self.crown = crown ?? CGPoint(x: centre.x, y: centre.y + height * Resting.crownAbove)
        // The same goes for the eyes: where a face's usually are.
        self.eyeLine = eyeLine ?? CGPoint(x: centre.x, y: centre.y + height * Resting.eyesAbove)
        self.eyeSpan = eyeSpan ?? height * Resting.eyesApart
        self.roll = roll
        self.turn = turn
        self.nod = nod
        self.leftEyeOpen = leftEyeOpen
        self.rightEyeOpen = rightEyeOpen
        self.leftBrow = leftBrow
        self.rightBrow = rightBrow
        self.mouthOpen = mouthOpen
        self.smile = smile
    }

    /// A calm face in the middle of a picture, for when nobody is in it.
    public static func resting(in canvas: CGSize) -> FaceExpression {
        FaceExpression(
            centre: CGPoint(x: canvas.width * Resting.centre.x, y: canvas.height * Resting.centre.y),
            height: canvas.height * Resting.height,
            smile: Resting.smile
        )
    }

    /// This expression moved part of the way towards another: none of the
    /// way at a share of 0, all of it at 1.
    public func blended(towards other: FaceExpression, by share: CGFloat) -> FaceExpression {
        func mix(_ path: KeyPath<FaceExpression, CGFloat>) -> CGFloat {
            self[keyPath: path] + (other[keyPath: path] - self[keyPath: path]) * share
        }
        return FaceExpression(
            centre: CGPoint(x: mix(\.centre.x), y: mix(\.centre.y)),
            height: mix(\.height),
            crown: CGPoint(x: mix(\.crown.x), y: mix(\.crown.y)),
            eyeLine: CGPoint(x: mix(\.eyeLine.x), y: mix(\.eyeLine.y)),
            eyeSpan: mix(\.eyeSpan),
            roll: mix(\.roll), turn: mix(\.turn), nod: mix(\.nod),
            leftEyeOpen: mix(\.leftEyeOpen), rightEyeOpen: mix(\.rightEyeOpen),
            leftBrow: mix(\.leftBrow), rightBrow: mix(\.rightBrow),
            mouthOpen: mix(\.mouthOpen), smile: mix(\.smile)
        )
    }
}

/// Works out what a face is doing from where its parts are.
public protocol FaceReading {
    /// Nil when the face cannot be read.
    func expression(of face: FaceLandmarks) -> FaceExpression?
}

/// Reads a face by measuring it, as `FaceExpressionReader` does.
public struct MeasuringFaceReader: FaceReading {
    public init() {}

    public func expression(of face: FaceLandmarks) -> FaceExpression? {
        FaceExpressionReader.expression(of: face)
    }
}

/// Works out what a face is doing from where its parts are.
///
/// Everything is measured along the line between the eyes and in units of
/// the distance between them, so the answer is the same however large the
/// face is in the picture and however far the head leans.
public enum FaceExpressionReader {
    /// What each measure reads on an ordinary face, in eye distances.
    private enum Measure {
        /// An eye's height over its width, shut and open.
        static let eyeShut: CGFloat = 0.14
        static let eyeOpen: CGFloat = 0.28
        /// How far a brow sits above the eye line, at rest, and how much
        /// further it goes when raised as far as it will.
        static let browAtRest: CGFloat = 0.35
        static let browReach: CGFloat = 0.12
        /// How far the nose is from the middle of the eye line when the
        /// head is turned right round to one side.
        static let noseReach: CGFloat = 0.3
        /// How far below the eye line the nose is when the head is level,
        /// and how much that changes looking right up or right down.
        static let noseAtRest: CGFloat = -0.5
        static let nodReach: CGFloat = 0.2
        /// The gap between the lips, closed and wide open.
        static let lipsClosed: CGFloat = 0.06
        static let lipsOpen: CGFloat = 0.5
        /// The mouth's width at rest, and how much it widens in a broad smile.
        static let mouthAtRest: CGFloat = 0.8
        static let smileReach: CGFloat = 0.2
        /// The top of the head is this many times as far above the eyes
        /// as the mouth is below them.
        static let crownOverMouth: CGFloat = 1.7
    }

    /// Nil when a part of the face is missing or its eyes cannot be told apart.
    public static func expression(of face: FaceLandmarks) -> FaceExpression? {
        let parts = face.eyes + face.brows + [face.nose, face.outerLips, face.innerLips]
        guard face.eyes.count == Pair.count, face.brows.count == Pair.count, !parts.contains(where: \.isEmpty) else {
            return nil
        }
        let eyes = face.eyes.sorted { middle(of: $0).x < middle(of: $1).x }
        let brows = face.brows.sorted { middle(of: $0).x < middle(of: $1).x }
        let left = middle(of: eyes[Pair.left]), right = middle(of: eyes[Pair.right])
        let span = hypot(right.x - left.x, right.y - left.y)
        guard span > 0 else { return nil }

        let roll = atan2(right.y - left.y, right.x - left.x)
        let origin = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        // Into the face's own frame: along the eye line, up from it, in eye distances.
        let level = CGAffineTransform(translationX: -origin.x, y: -origin.y)
            .concatenating(CGAffineTransform(rotationAngle: -roll))
            .concatenating(CGAffineTransform(scaleX: 1 / span, y: 1 / span))
        func levelled(_ points: [CGPoint]) -> [CGPoint] { points.map { $0.applying(level) } }

        let nose = middle(of: levelled(face.nose))
        let lips = levelled(face.outerLips)
        // Up the face's own upright from the eyes, however the head leans.
        let rise = -middle(of: lips).y * Measure.crownOverMouth * span
        return FaceExpression(
            centre: CGPoint(x: face.box.midX, y: face.box.midY),
            height: face.box.height,
            crown: CGPoint(x: origin.x - sin(roll) * rise, y: origin.y + cos(roll) * rise),
            eyeLine: origin,
            eyeSpan: span,
            roll: roll,
            turn: signed(nose.x / Measure.noseReach),
            nod: signed((nose.y - Measure.noseAtRest) / Measure.nodReach),
            leftEyeOpen: openness(ofEye: levelled(eyes[Pair.left])),
            rightEyeOpen: openness(ofEye: levelled(eyes[Pair.right])),
            leftBrow: signed((middle(of: levelled(brows[Pair.left])).y - Measure.browAtRest) / Measure.browReach),
            rightBrow: signed((middle(of: levelled(brows[Pair.right])).y - Measure.browAtRest) / Measure.browReach),
            mouthOpen: share(of: size(of: levelled(face.innerLips)).height, from: Measure.lipsClosed, to: Measure.lipsOpen),
            smile: signed((size(of: lips).width - Measure.mouthAtRest) / Measure.smileReach)
        )
    }

    private enum Pair {
        static let count = 2
        static let left = 0
        static let right = 1
    }

    private static func openness(ofEye points: [CGPoint]) -> CGFloat {
        let size = size(of: points)
        // An eye with no width at all tells nothing: it is taken as shut.
        guard size.width > 0 else { return 0 }
        return share(of: size.height / size.width, from: Measure.eyeShut, to: Measure.eyeOpen)
    }

    private static func middle(of points: [CGPoint]) -> CGPoint {
        let count = CGFloat(points.count)
        return CGPoint(x: points.map(\.x).reduce(0, +) / count, y: points.map(\.y).reduce(0, +) / count)
    }

    /// How wide and how tall a set of points is. The points are never empty.
    private static func size(of points: [CGPoint]) -> CGSize {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGSize(width: xs.reduce(xs[0], max) - xs.reduce(xs[0], min), height: ys.reduce(ys[0], max) - ys.reduce(ys[0], min))
    }

    /// Where a value falls between two ends, held to 0...1.
    private static func share(of value: CGFloat, from low: CGFloat, to high: CGFloat) -> CGFloat {
        min(max((value - low) / (high - low), 0), 1)
    }

    /// A value held to -1...1.
    private static func signed(_ value: CGFloat) -> CGFloat {
        min(max(value, -1), 1)
    }
}

/// Steadies an expression from one frame to the next.
public protocol ExpressionSmoothing: AnyObject {
    /// The expression to show this frame, given what was just seen, if anything.
    func settle(on seen: FaceExpression?) -> FaceExpression
    /// Puts the expression somewhere by hand.
    func rest(at expression: FaceExpression)
}

/// Steadies an expression from one frame to the next, so a character does
/// not twitch with every small wobble in where a face was found.
public final class ExpressionSmoother: ExpressionSmoothing {
    private let share: CGFloat
    private var current: FaceExpression
    private var hasSeenAFace = false

    /// - Parameters:
    ///   - start: what to show until a face is first seen.
    ///   - share: how far each frame moves towards what was just seen, 0 to 1.
    public init(start: FaceExpression, share: CGFloat) {
        current = start
        self.share = share
    }

    /// The expression to show this frame. With no face in sight the last
    /// one is held, so the character stays put rather than vanishing.
    public func settle(on seen: FaceExpression?) -> FaceExpression {
        guard let seen else { return current }
        // The first sighting is taken whole: gliding in from the middle
        // of the picture would look like a mistake.
        current = hasSeenAFace ? current.blended(towards: seen, by: share) : seen
        hasSeenAFace = true
        return current
    }

    /// Puts the expression somewhere by hand, as a preview does to stand a
    /// character where its sample figure is.
    public func rest(at expression: FaceExpression) {
        current = expression
    }
}
