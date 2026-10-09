import Foundation
import simd

/// A virtual camera placement: where it is, where it points, and how wide it sees.
struct CameraPose: Equatable {
    var position: SIMD3<Float>
    var orientation: simd_quatf
    /// Vertical field of view in degrees.
    var fov: Float

    /// Builds a pose at `position` looking at `target`. RealityKit cameras look down their local -Z.
    static func look(from position: SIMD3<Float>,
                     at target: SIMD3<Float>,
                     up: SIMD3<Float> = [0, 1, 0],
                     fov: Float = 62) -> CameraPose {
        let forward = simd_normalize(target - position)
        var upVector = up
        if abs(simd_dot(forward, simd_normalize(up))) > 0.999 {
            upVector = [0, 0, -1]  // looking straight up/down: fall back to "screen-top faces into the café"
        }
        let zAxis = -forward
        let xAxis = simd_normalize(simd_cross(upVector, zAxis))
        let yAxis = simd_cross(zAxis, xAxis)
        let rotation = simd_quatf(simd_float3x3(columns: (xAxis, yAxis, zAxis)))
        return CameraPose(position: position, orientation: simd_normalize(rotation), fov: fov)
    }

    /// Straight-down view (a true 90° overhead shot). `screenUp` is the world direction that appears at the top of the screen.
    static func overhead(above point: SIMD3<Float>, height: Float, screenUp: SIMD3<Float> = [0, 0, -1], fov: Float) -> CameraPose {
        look(from: point + [0, height, 0], at: point, up: screenUp, fov: fov)
    }

    /// The direction the camera is looking.
    var forward: SIMD3<Float> { orientation.act([0, 0, -1]) }
}

/// Global timing curves for camera moves.
enum CameraEasing {
    case linear
    /// Smooth acceleration out of rest and a long, soft settle (smootherstep).
    case cinematic
    /// Faster start, gentle landing — used for short hops between locations.
    case glide

    func apply(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear:
            return t
        case .cinematic:
            return t * t * t * (t * (t * 6 - 15) + 10)
        case .glide:
            // Quick ease-in, then a long Hermite deceleration into the landing.
            return t < 0.4 ? 2.5 * t * t : glideTail(t)
        }
    }

    private func glideTail(_ t: Double) -> Double {
        // Continuous with 2.5t² at t = 0.4 (value 0.4, slope 2.0); cubic ease-out to (1, 1) with zero slope.
        let u = (t - 0.4) / 0.6
        let a = 0.4, b = 2.0 * 0.6  // value and slope (in u units) at u = 0
        // Hermite from (a, b) to (1, 0)
        let h00 = 2 * u * u * u - 3 * u * u + 1
        let h10 = u * u * u - 2 * u * u + u
        let h01 = -2 * u * u * u + 3 * u * u
        return h00 * a + h10 * b + h01 * 1
    }
}

/// A smooth, reversible camera move through a list of key poses.
///
/// Positions, orientations and field of view are interpolated with a non-uniform cubic Hermite
/// (Catmull-Rom style) spline. Knot spacing comes from each segment's travel distance plus its
/// rotation, so a move that mostly rotates in place (rising into the overhead table view) still
/// gets enough time. Sampling at `1 - t` replays the exact same path backwards.
struct CameraPath {
    let keys: [CameraPose]
    let duration: TimeInterval
    let easing: CameraEasing

    /// Normalized knot times, one per key, from 0 to 1.
    let knots: [Float]
    private let positionTangents: [SIMD3<Float>]
    private let rotationKeys: [SIMD4<Float>]
    private let rotationTangents: [SIMD4<Float>]
    private let fovTangents: [Float]

    /// Metres of travel that cost the same time as one radian of rotation.
    static let metresPerRadian: Float = 1.1

    init(keys: [CameraPose], duration: TimeInterval, easing: CameraEasing = .cinematic) {
        precondition(!keys.isEmpty, "CameraPath needs at least one key")
        self.keys = keys
        self.duration = max(duration, 0.001)
        self.easing = easing

        // Quaternions q and -q are the same rotation; keep neighbours in the same hemisphere.
        var quats: [SIMD4<Float>] = []
        for key in keys {
            var q = key.orientation.vector
            if let previous = quats.last, simd_dot(previous, q) < 0 { q = -q }
            quats.append(q)
        }
        rotationKeys = quats

        var costs: [Float] = []
        for i in 1..<max(keys.count, 1) {
            let distance = simd_distance(keys[i - 1].position, keys[i].position)
            let angle = 2 * acos(min(1, abs(simd_dot(quats[i - 1], quats[i]))))
            costs.append(max(distance + angle * Self.metresPerRadian, 0.0001))
        }
        let total = costs.reduce(0, +)
        var knots: [Float] = [0]
        for c in costs { knots.append(knots.last! + (total > 0 ? c / total : 0)) }
        if keys.count > 1 { knots[knots.count - 1] = 1 }
        self.knots = knots

        positionTangents = Self.tangents(keys.map(\.position), knots: knots)
        rotationTangents = Self.tangents(quats, knots: knots)
        fovTangents = Self.tangents(keys.map { SIMD2<Float>($0.fov, 0) }, knots: knots).map(\.x)
    }

    var start: CameraPose { keys[0] }
    var end: CameraPose { keys[keys.count - 1] }

    /// The same path traversed backwards.
    func reversed(duration: TimeInterval? = nil) -> CameraPath {
        CameraPath(keys: keys.reversed(), duration: duration ?? self.duration, easing: easing)
    }

    /// Pose at normalized time `progress` (0...1) after easing.
    func pose(atProgress progress: Double) -> CameraPose {
        pose(atSpline: Float(easing.apply(progress)))
    }

    /// Pose at a raw spline parameter `s` (0...1), no easing.
    func pose(atSpline s: Float) -> CameraPose {
        guard keys.count > 1 else { return keys[0] }
        let s = min(max(s, 0), 1)
        var i = 0
        while i < knots.count - 2 && s > knots[i + 1] { i += 1 }
        let t0 = knots[i], t1 = knots[i + 1]
        let h = max(t1 - t0, 1e-6)
        let u = (s - t0) / h

        let position = Self.hermite(keys[i].position, positionTangents[i], keys[i + 1].position, positionTangents[i + 1], u: u, h: h)
        let q = Self.hermite(rotationKeys[i], rotationTangents[i], rotationKeys[i + 1], rotationTangents[i + 1], u: u, h: h)
        let fov = Self.hermite(SIMD2(keys[i].fov, 0), SIMD2(fovTangents[i], 0), SIMD2(keys[i + 1].fov, 0), SIMD2(fovTangents[i + 1], 0), u: u, h: h).x
        let orientation = simd_length(q) > 1e-6 ? simd_quatf(vector: simd_normalize(q)) : keys[i].orientation
        return CameraPose(position: position, orientation: orientation, fov: fov)
    }

    // MARK: - Spline helpers

    /// Finite-difference tangents for non-uniform knots (zero-acceleration style ends).
    private static func tangents<V: SIMD>(_ values: [V], knots: [Float]) -> [V] where V.Scalar == Float {
        let n = values.count
        guard n > 1 else { return Array(repeating: V(), count: n) }
        var result: [V] = []
        for i in 0..<n {
            let a = max(i - 1, 0), b = min(i + 1, n - 1)
            let dt = knots[b] - knots[a]
            result.append(dt > 1e-6 ? (values[b] - values[a]) / dt : V())
        }
        return result
    }

    private static func hermite<V: SIMD>(_ p0: V, _ m0: V, _ p1: V, _ m1: V, u: Float, h: Float) -> V where V.Scalar == Float {
        let u2 = u * u, u3 = u2 * u
        let h00 = 2 * u3 - 3 * u2 + 1
        let h10 = u3 - 2 * u2 + u
        let h01 = -2 * u3 + 3 * u2
        let h11 = u3 - u2
        return h00 * p0 + (h10 * h) * m0 + h01 * p1 + (h11 * h) * m1
    }
}
