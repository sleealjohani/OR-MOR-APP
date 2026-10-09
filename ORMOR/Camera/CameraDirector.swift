import Foundation
import simd
import SwiftUI

/// Owns the virtual camera: which spot it rests at, the move in progress, and the back stack.
///
/// The RealityKit view calls `advance(by:)` every frame and applies `currentPose` to its camera.
/// SwiftUI reads `spot` / `isMoving` to decide which service panel to show.
@MainActor
final class CameraDirector: ObservableObject {
    enum Phase: Equatable {
        case idle
        case intro
        case moving
    }

    @Published private(set) var spot: CafeSpot = .exterior
    @Published private(set) var phase: Phase = .idle
    /// Bumps whenever the camera settles, so overlays can re-project hotspot labels.
    @Published private(set) var settleCount = 0
    /// Horizontal look-around offset at the hub, in radians.
    @Published private(set) var hubYaw: Float = 0

    private(set) var currentPose: CameraPose = CafeLayout.introKeys[0]
    var viewAspect: Float = 9.0 / 19.5

    /// Set from accessibility settings: replaces flights with a short cut.
    var reduceMotion = false
    /// Called when the intro passes the door trigger.
    var onDoorsShouldOpen: (() -> Void)?
    /// Called when the camera is put back outside (replaying the intro).
    var onDoorsShouldClose: (() -> Void)?

    private struct Move {
        let path: CameraPath
        let destination: CafeSpot
        var elapsed: TimeInterval = 0
        let isIntro: Bool
        var firedDoors = false
    }

    private var move: Move?
    /// Each entry is the path that brought us to the current spot; Back replays it in reverse.
    private var history: [(from: CafeSpot, path: CameraPath)] = []

    static let maxHubYaw: Float = 0.62

    var isMoving: Bool { move != nil }
    var canGoBack: Bool { !history.isEmpty && move == nil }

    // MARK: - Commands

    func playIntro() {
        history.removeAll()
        hubYaw = 0
        let path = CameraPath(keys: CafeLayout.introKeys, duration: reduceMotion ? 1.2 : 7.2, easing: .cinematic)
        start(Move(path: path, destination: .hub, isIntro: true))
    }

    /// Puts the camera back on the street with the doors shut, ready to replay the intro.
    func resetToExterior() {
        move = nil
        history.removeAll()
        hubYaw = 0
        currentPose = CafeLayout.introKeys[0]
        spot = .exterior
        phase = .idle
        onDoorsShouldClose?()
    }

    /// Skips straight to the hub (used when the intro has already been seen).
    func jumpToHub() {
        move = nil
        history.removeAll()
        hubYaw = 0
        currentPose = CafeLayout.hubPose
        spot = .hub
        phase = .idle
        onDoorsShouldOpen?()
        settleCount += 1
    }

    func go(to destination: CafeSpot) {
        guard move == nil, destination != spot, destination != .exterior else { return }
        if destination == .hub { return goHome() }

        var keys = [currentPose]
        let route = CafeLayout.route(to: destination, aspect: viewAspect)
        if spot == .hub {
            // Start from where the user is actually looking, then join the hub route.
            keys += route.dropFirst()
        } else {
            // From another spot: rise back toward the room, then follow the destination route.
            keys += [liftedPose(from: currentPose)] + route.dropFirst()
        }
        let path = CameraPath(keys: keys, duration: duration(for: keys), easing: .glide)
        history.append((from: spot, path: path))
        start(Move(path: path, destination: destination, isIntro: false))
    }

    /// Reverses the last move exactly.
    func back() {
        guard move == nil, let last = history.popLast() else { return }
        start(Move(path: last.path.reversed(), destination: last.from, isIntro: false))
    }

    /// Returns to the hub from anywhere, unwinding in one smooth move.
    func goHome() {
        guard move == nil, spot != .hub else { return }
        if history.count == 1 { return back() }
        let keys = [currentPose, liftedPose(from: currentPose), CafeLayout.hubPose]
        history.removeAll()
        hubYaw = 0
        start(Move(path: CameraPath(keys: keys, duration: duration(for: keys), easing: .glide), destination: .hub, isIntro: false))
    }

    /// Drag-to-look at the hub.
    func lookAround(by deltaYaw: Float) {
        guard spot == .hub, move == nil else { return }
        hubYaw = min(max(hubYaw + deltaYaw, -Self.maxHubYaw), Self.maxHubYaw)
        currentPose = hubPoseWithYaw(hubYaw)
    }

    // MARK: - Frame updates

    func advance(by dt: TimeInterval) {
        guard var m = move else { return }
        m.elapsed += dt
        let progress = min(m.elapsed / m.path.duration, 1)

        if reduceMotion && !m.isIntro {
            // Hold, then cut at the midpoint; the scene view cross-fades around the cut.
            currentPose = progress < 0.5 ? m.path.start : m.path.end
        } else {
            currentPose = m.path.pose(atProgress: progress)
        }

        if m.isIntro, !m.firedDoors, m.path.easing.apply(progress) >= Double(CafeLayout.introDoorTrigger) {
            m.firedDoors = true
            onDoorsShouldOpen?()
        }

        if progress >= 1 {
            currentPose = m.path.end
            move = nil
            spot = m.destination
            phase = .idle
            settleCount += 1
        } else {
            move = m
        }
    }

    // MARK: - Helpers

    private func start(_ m: Move) {
        var m = m
        if reduceMotion && !m.isIntro {
            m = Move(path: CameraPath(keys: [m.path.start, m.path.end], duration: 0.5, easing: .linear),
                     destination: m.destination, isIntro: false)
        }
        move = m
        phase = m.isIntro ? .intro : .moving
    }

    /// Travel time scales with distance and rotation, kept within a snappy-but-cinematic range.
    private func duration(for keys: [CameraPose]) -> TimeInterval {
        var metres: Float = 0
        var radians: Float = 0
        for i in 1..<keys.count {
            metres += simd_distance(keys[i - 1].position, keys[i].position)
            radians += 2 * acos(min(1, abs(simd_dot(keys[i - 1].orientation.vector, keys[i].orientation.vector))))
        }
        let seconds = 0.9 + Double(metres) * 0.16 + Double(radians) * 0.35
        return min(max(seconds, 1.3), 3.0)
    }

    /// A pose a little above and behind `pose`, looking level into the room, used to leave overhead views gracefully.
    private func liftedPose(from pose: CameraPose) -> CameraPose {
        let p = pose.position
        let lifted = SIMD3<Float>(p.x * 0.85, max(p.y, 2.0), p.z + 1.4)
        return .look(from: lifted, at: [p.x * 0.5, 1.2, p.z - 3], fov: 68)
    }

    private func hubPoseWithYaw(_ yaw: Float) -> CameraPose {
        var pose = CafeLayout.hubPose
        pose.orientation = simd_normalize(simd_quatf(angle: yaw, axis: [0, 1, 0]) * pose.orientation)
        return pose
    }
}
