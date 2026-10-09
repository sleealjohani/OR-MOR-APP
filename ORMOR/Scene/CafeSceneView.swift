import Combine
import RealityKit
import SwiftUI
import UIKit
import simd

/// Screen positions of hotspot labels, refreshed while the camera rests at the hub.
@MainActor
final class HotspotProjector: ObservableObject {
    @Published var points: [CafeSpot: CGPoint] = [:]
}

enum GraphicsQuality: String, CaseIterable, Identifiable {
    case high, balanced
    var id: String { rawValue }
}

/// Hosts the RealityKit café and wires it to the camera director.
struct CafeSceneView: UIViewRepresentable {
    @ObservedObject var director: CameraDirector
    let projector: HotspotProjector
    var quality: GraphicsQuality
    var onSelect: (CafeSpot) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(director: director, projector: projector, onSelect: onSelect)
    }

    func makeUIView(context: Context) -> CafeARView {
        let view = CafeARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 0.05, green: 0.055, blue: 0.07, alpha: 1))
        let cameraDirector = director
        view.onLayout = { [weak cameraDirector] size in
            guard size.height > 0 else { return }
            cameraDirector?.viewAspect = Float(size.width / size.height)
        }
        context.coordinator.attach(to: view)
        apply(quality, to: view)
        return view
    }

    func updateUIView(_ view: CafeARView, context: Context) {
        context.coordinator.onSelect = onSelect
        apply(quality, to: view)
    }

    private func apply(_ quality: GraphicsQuality, to view: ARView) {
        switch quality {
        case .high:
            view.renderOptions = [.disableMotionBlur, .disableCameraGrain]
        case .balanced:
            view.renderOptions = [.disableMotionBlur, .disableCameraGrain, .disableDepthOfField, .disableHDR, .disableGroundingShadows]
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let director: CameraDirector
        let projector: HotspotProjector
        var onSelect: (CafeSpot) -> Void
        private weak var view: ARView?
        private var scene: CafeScene?
        private var updateSubscription: Cancellable?
        private var clock: TimeInterval = 0

        init(director: CameraDirector, projector: HotspotProjector, onSelect: @escaping (CafeSpot) -> Void) {
            self.director = director
            self.projector = projector
            self.onSelect = onSelect
        }

        func attach(to view: ARView) {
            self.view = view
            let scene = CafeSceneBuilder.build()
            view.scene.addAnchor(scene.root)
            self.scene = scene
            apply(director.currentPose)

            director.onDoorsShouldOpen = { [weak self] in
                guard let scene = self?.scene else { return }
                CafeSceneBuilder.setDoors(scene, open: true, animated: !(self?.director.reduceMotion ?? false))
            }

            director.onDoorsShouldClose = { [weak self] in
                guard let scene = self?.scene else { return }
                CafeSceneBuilder.setDoors(scene, open: false, animated: false)
            }

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            view.addGestureRecognizer(tap)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            view.addGestureRecognizer(pan)

            updateSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.tick(event.deltaTime)
                }
            }
        }

        private func tick(_ dt: TimeInterval) {
            guard let scene else { return }
            clock += dt
            director.advance(by: min(dt, 1.0 / 20))  // clamp hitches so the camera never skips ahead
            apply(director.currentPose)

            // Breathing glow rings, only while the user can choose a spot.
            let showRings = director.spot == .hub && !director.isMoving
            let pulse = 1 + 0.06 * Float(sin(clock * 2.4))
            for ring in scene.hotspotRings.values {
                ring.isEnabled = showRings
                ring.scale = [pulse, 1, pulse]
            }
            updateLabels(visible: showRings)
        }

        private func apply(_ pose: CameraPose) {
            guard let camera = scene?.camera else { return }
            camera.transform = Transform(scale: .one, rotation: pose.orientation, translation: pose.position)
            camera.camera.fieldOfViewInDegrees = pose.fov
        }

        private func updateLabels(visible: Bool) {
            guard let view else { return }
            guard visible else {
                if !projector.points.isEmpty { projector.points = [:] }
                return
            }
            let pose = director.currentPose
            var points: [CafeSpot: CGPoint] = [:]
            for spot in CafeLayout.interactiveSpots {
                guard let anchor = CafeLayout.labelAnchor(for: spot),
                      simd_dot(anchor - pose.position, pose.forward) > 0.3,
                      let p = view.project(anchor),
                      view.bounds.insetBy(dx: -40, dy: -40).contains(p) else { continue }
                points[spot] = p
            }
            let changed = points.count != projector.points.count || points.contains { key, p in
                guard let old = projector.points[key] else { return true }
                return abs(old.x - p.x) > 0.5 || abs(old.y - p.y) > 0.5
            }
            if changed { projector.points = points }
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view, director.spot == .hub, !director.isMoving else { return }
            let location = gesture.location(in: view)
            var entity = view.entity(at: location)
            while let e = entity {
                if let spot = CafeSpot(hotspotName: e.name) {
                    onSelect(spot)
                    return
                }
                entity = e.parent
            }
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view else { return }
            let dx = gesture.translation(in: view).x
            gesture.setTranslation(.zero, in: view)
            director.lookAround(by: Float(dx) * 0.0035)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

/// ARView that reports its size so overhead framing can adapt to the screen shape.
final class CafeARView: ARView {
    var onLayout: ((CGSize) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds.size)
    }
}
