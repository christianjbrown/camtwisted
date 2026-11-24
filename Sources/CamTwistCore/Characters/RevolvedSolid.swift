import Foundation

/// The surface of a solid as corners and the triangles between them.
public struct SolidMesh: Equatable, Sendable {
    public var positions: [SIMD3<Float>]
    /// Which way the surface faces at each corner, one unit long.
    public var normals: [SIMD3<Float>]
    /// Where each corner falls on a picture wrapped round the solid: the
    /// first number runs once round it, with a half at the front, and the
    /// second from the bottom, 0, to the top, 1.
    public var coordinates: [SIMD2<Float>]
    /// Corner numbers, three to a triangle.
    public var triangles: [UInt32]
}

/// A solid made by sweeping an outline round an upright axis, the way a
/// lathe turns one: a head, a bottle, a chess piece.
public enum RevolvedSolid {
    private static let fullTurn = 2 * Float.pi
    private static let front: Float = 0.5

    /// - Parameters:
    ///   - profile: the outline from bottom to top, each point a distance
    ///     out from the axis and a height. No two neighbours are the same point.
    ///   - segments: how many flat strips make up one turn.
    public static func mesh(profile: [SIMD2<Float>], segments: Int) -> SolidMesh {
        let heights = profile.map(\.y)
        let bottom = heights.reduce(heights[0], min)
        let tall = heights.reduce(heights[0], max) - bottom
        var mesh = SolidMesh(positions: [], normals: [], coordinates: [], triangles: [])
        for (index, point) in profile.enumerated() {
            // The surface faces square to the outline's own direction.
            let along = profile[min(index + 1, profile.count - 1)] - profile[max(index - 1, 0)]
            let length = (along.x * along.x + along.y * along.y).squareRoot()
            let outward = SIMD2<Float>(along.y / length, -along.x / length)
            // The seam's corners are made twice, so the picture can meet itself there.
            for step in 0...segments {
                let round = Float(step) / Float(segments)
                let angle = (round - front) * fullTurn
                mesh.positions.append(SIMD3(point.x * sin(angle), point.y, point.x * cos(angle)))
                mesh.normals.append(SIMD3(outward.x * sin(angle), outward.y, outward.x * cos(angle)))
                mesh.coordinates.append(SIMD2(round, (point.y - bottom) / tall))
            }
        }
        let ring = segments + 1
        for index in 0..<(profile.count - 1) {
            for step in 0..<segments {
                let lower = UInt32(index * ring + step), upper = lower + UInt32(ring)
                mesh.triangles += [lower, lower + 1, upper + 1, lower, upper + 1, upper]
            }
        }
        return mesh
    }

    /// The outline of an upright cylinder whose top and bottom edges are rounded off.
    ///
    /// - Parameters:
    ///   - rim: the radius of the rounding.
    ///   - steps: how many pieces each rounded edge is made of.
    public static func roundedCylinder(radius: Float, height: Float, rim: Float, steps: Int) -> [SIMD2<Float>] {
        let quarterTurn = Float.pi / 2
        func edge(centredAt centre: SIMD2<Float>, from start: Float) -> [SIMD2<Float>] {
            (0...steps).map { step in
                let angle = start + quarterTurn * Float(step) / Float(steps)
                return SIMD2(centre.x + rim * cos(angle), centre.y + rim * sin(angle))
            }
        }
        let half = height / 2
        return [SIMD2(0, -half)]
            + edge(centredAt: SIMD2(radius - rim, rim - half), from: -quarterTurn)
            + edge(centredAt: SIMD2(radius - rim, half - rim), from: 0)
            + [SIMD2(0, half)]
    }
}
