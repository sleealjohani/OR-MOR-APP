import RealityKit
import UIKit
import simd

/// The live scene graph plus the handles the app animates.
@MainActor
struct CafeScene {
    let root: AnchorEntity
    let camera: PerspectiveCamera
    let leftDoor: Entity
    let rightDoor: Entity
    let hotspotRings: [CafeSpot: ModelEntity]
}

/// Builds a lightweight, photo-textured stand-in of OR & MOR from primitives.
///
/// This is the prototype environment. A scanned model (USDZ) can replace it later as long as it
/// keeps entities named `hotspot:table-N`, `hotspot:cashier`, `hotspot:management` and the two
/// door pivots; see docs/3D-PIPELINE.md.
@MainActor
enum CafeSceneBuilder {
    typealias M = CafeMaterials

    static func build() -> CafeScene {
        let root = AnchorEntity(world: .zero)

        buildShell(into: root)
        buildExterior(into: root)
        let (left, right) = buildDoors(into: root)
        buildCeilingLights(into: root)
        buildColumn(into: root)
        buildStair(into: root)
        buildDecor(into: root)

        var rings: [CafeSpot: ModelEntity] = [:]
        for table in CafeLayout.tables {
            let hotspot = makeTable(table)
            root.addChild(hotspot)
            rings[.table(table.number)] = addRing(to: hotspot, at: [0, 0, 0], size: 1.9)
        }
        let cashier = makeCashier()
        root.addChild(cashier)
        rings[.cashier] = addRing(to: cashier, at: [0, 0, 1.15], size: 2.2)
        let management = makeManagement()
        root.addChild(management)
        rings[.management] = addRing(to: management, at: [0, 0, 0.95], size: 1.8)

        addLights(into: root)

        let camera = PerspectiveCamera()
        camera.camera.near = 0.05
        camera.camera.far = 80
        root.addChild(camera)

        return CafeScene(root: root, camera: camera, leftDoor: left, rightDoor: right, hotspotRings: rings)
    }

    // MARK: - Helpers

    @discardableResult
    private static func box(_ size: SIMD3<Float>, at position: SIMD3<Float>, _ material: Material,
                            corner: Float = 0, in parent: Entity) -> ModelEntity {
        let e = ModelEntity(mesh: .generateBox(width: size.x, height: size.y, depth: size.z, cornerRadius: corner),
                            materials: [material])
        e.position = position
        parent.addChild(e)
        return e
    }

    @discardableResult
    private static func cylinder(height: Float, radius: Float, at position: SIMD3<Float>, _ material: Material, in parent: Entity) -> ModelEntity {
        let e = ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [material])
        e.position = position
        parent.addChild(e)
        return e
    }

    /// Vertical plane facing +Z (rotate to face elsewhere).
    @discardableResult
    private static func panel(width: Float, height: Float, at position: SIMD3<Float>, facingYaw: Float = 0,
                              _ material: Material, in parent: Entity) -> ModelEntity {
        let e = ModelEntity(mesh: .generatePlane(width: width, height: height), materials: [material])
        e.position = position
        e.orientation = simd_quatf(angle: facingYaw, axis: [0, 1, 0])
        parent.addChild(e)
        return e
    }

    private static func addRing(to hotspot: Entity, at offset: SIMD3<Float>, size: Float) -> ModelEntity {
        let ring = ModelEntity(mesh: .generatePlane(width: size, depth: size), materials: [M.glowTexture("tex_hotspot_ring", transparent: true)])
        ring.position = offset + [0, 0.006, 0]
        ring.name = "ring"
        hotspot.addChild(ring)
        return ring
    }

    private static func hotspot(_ spot: CafeSpot, at position: SIMD3<Float>, hitBox: SIMD3<Float>, hitOffset: SIMD3<Float> = .zero) -> Entity {
        let e = Entity()
        e.name = CafeLayout.hotspotPrefix + spot.id
        e.position = position
        e.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: hitBox).offsetBy(translation: hitOffset)]))
        return e
    }

    // MARK: - Room

    private static func buildShell(into root: Entity) {
        let width = CafeLayout.roomMaxX - CafeLayout.roomMinX
        let depth = -CafeLayout.roomBackZ
        let h = CafeLayout.ceilingHeight
        let midZ = CafeLayout.roomBackZ / 2

        // Large-format porcelain floor: the texture spans 2.4 m x 1.2 m.
        let floor = ModelEntity(mesh: .generatePlane(width: width, depth: depth),
                                materials: [M.textured("tex_floor", fallback: 0xECE4D6, roughness: 0.22, repeat: [width / 2.4, depth / 1.2], clearcoat: 0.6)])
        floor.position = [0, 0, midZ]
        root.addChild(floor)

        let ceiling = ModelEntity(mesh: .generatePlane(width: width, depth: depth), materials: [M.pbr(M.ceiling, roughness: 0.9)])
        ceiling.position = [0, h, midZ]
        ceiling.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        root.addChild(ceiling)

        let wall = M.pbr(M.ivoryWall, roughness: 0.85)
        let t: Float = 0.2
        box([t, h, depth], at: [CafeLayout.roomMinX - t / 2, h / 2, midZ], wall, in: root)
        box([t, h, depth], at: [CafeLayout.roomMaxX + t / 2, h / 2, midZ], wall, in: root)

        // Back wall with a kitchen opening behind the display case.
        let backZ = CafeLayout.roomBackZ - t / 2
        box([4.0, h, t], at: [-4.2, h / 2, backZ], wall, in: root)
        box([6.6, h, t], at: [2.9, h / 2, backZ], wall, in: root)
        box([2.0, h - 2.4, t], at: [-1.2, 2.4 + (h - 2.4) / 2, backZ], wall, in: root)
        box([2.0, 2.4, 0.05], at: [-1.2, 1.2, backZ - 1.2], M.pbr(0x9A8F80, roughness: 0.8), in: root)  // kitchen beyond

        // Inside face of the front wall, around the doorway.
        let side = (width - 2 * CafeLayout.doorHalfWidth) / 2
        box([side, h, t], at: [CafeLayout.roomMinX + side / 2, h / 2, -t / 2], wall, in: root)
        box([side, h, t], at: [CafeLayout.roomMaxX - side / 2, h / 2, -t / 2], wall, in: root)
        let lintel = h - CafeLayout.doorHeight
        box([2 * CafeLayout.doorHalfWidth, lintel, t], at: [0, CafeLayout.doorHeight + lintel / 2, -t / 2], wall, in: root)

        // Warm LED cove along the base of the walls.
        let cove = M.glow(M.warmLED)
        box([0.03, 0.03, depth], at: [CafeLayout.roomMinX + 0.02, 0.04, midZ], cove, in: root)
        box([0.03, 0.03, depth], at: [CafeLayout.roomMaxX - 0.02, 0.04, midZ], cove, in: root)
        box([6.6, 0.03, 0.03], at: [2.9, 0.04, CafeLayout.roomBackZ + 0.02], cove, in: root)
    }

    private static func buildCeilingLights(into root: Entity) {
        let h = CafeLayout.ceilingHeight - 0.01
        let strip = M.glow(M.coolLED)
        let vent = M.pbr(0x161616, roughness: 0.6)
        // Long angled linear lights and black slot diffusers, as in the interior photos.
        let lines: [(SIMD3<Float>, Float, Float)] = [
            ([1.5, h, -3.0], 5.5, 0.35), ([-1.0, h, -7.5], 6.0, 0.35), ([3.6, h, -8.6], 4.5, 0.35),
            ([-3.8, h, -2.6], 3.5, 0.35),
        ]
        for (p, length, yaw) in lines {
            let e = box([length, 0.02, 0.035], at: p, strip, in: root)
            e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        }
        let vents: [(SIMD3<Float>, Float, Float)] = [
            ([-1.8, h, -4.3], 3.2, 0.12), ([2.6, h, -5.6], 3.4, 0.12), ([0.2, h, -9.6], 3.0, 0.12), ([4.0, h, -1.8], 2.4, 0.12),
        ]
        for (p, length, yaw) in vents {
            let e = box([length, 0.015, 0.12], at: p, vent, in: root)
            e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        }
        // Small square downlights
        for p: SIMD3<Float> in [[-2.5, h, -9], [1.8, h, -2.2], [3.3, h, -7.4], [-1.6, h, -1.4], [-4.4, h, -6.3]] {
            box([0.12, 0.012, 0.12], at: p, M.glow(0xFFFFFF), in: root)
        }
    }

    private static func buildColumn(into root: Entity) {
        let h = CafeLayout.ceilingHeight
        cylinder(height: h, radius: CafeLayout.columnRadius, at: CafeLayout.column + [0, h / 2, 0], M.pbr(0xEDE7DC, roughness: 0.6), in: root)
    }

    private static func buildStair(into root: Entity) {
        let stone = M.pbr(0xE6DFD2, roughness: 0.4)
        let led = M.glow(M.warmLED)
        for i in 0..<9 {
            let y = Float(i) * 0.18
            let z = -6.4 - Float(i) * 0.3
            box([1.1, 0.18, 0.3], at: [-5.6, y + 0.09, z], stone, in: root)
            box([1.1, 0.012, 0.012], at: [-5.6, y + 0.185, z + 0.15], led, in: root)
        }
        box([0.02, 2.4, 0.02], at: [-5.02, 1.2, -6.2], led, in: root)
        box([0.02, 2.4, 0.02], at: [-5.02, 1.2, -5.6], led, in: root)
    }

    private static func buildDecor(into root: Entity) {
        let backZ = CafeLayout.roomBackZ + 0.012
        // Coffee artwork on the back wall
        panel(width: 0.34, height: 0.78, at: [2.5, 2.05, backZ], M.glowTexture("tex_wall_art_1"), in: root)
        panel(width: 0.36, height: 0.95, at: [2.95, 1.55, backZ], M.glowTexture("tex_wall_art_2"), in: root)
        panel(width: 0.5, height: 0.7, at: [-5.4, 2.0, -9.0], facingYaw: .pi / 2, M.glowTexture("tex_wall_art_1"), in: root)

        // Leaning mirror
        let mirror = box([0.75, 1.95, 0.04], at: [3.85, 0.98, backZ + 0.25], M.pbr(0xDCDCDC, roughness: 0.03, metallic: 1), in: root)
        mirror.orientation = simd_quatf(angle: -0.12, axis: [1, 0, 0])
        box([0.8, 2.0, 0.03], at: [3.85, 0.98, backZ + 0.23], M.pbr(0x2A2A2A, roughness: 0.4), in: root).orientation = mirror.orientation

        // Potted ficus
        let plantBase: SIMD3<Float> = [4.9, 0, backZ + 0.55]
        cylinder(height: 0.34, radius: 0.2, at: plantBase + [0, 0.17, 0], M.pbr(0xF4F2EE, roughness: 0.3), in: root)
        cylinder(height: 1.0, radius: 0.025, at: plantBase + [0, 0.8, 0], M.pbr(0x5B4632, roughness: 0.8), in: root)
        let leaf = M.pbr(0x4E7A2C, roughness: 0.7)
        let blobs: [(SIMD3<Float>, Float)] = [([0, 1.45, 0], 0.32), ([0.2, 1.2, 0.05], 0.24), ([-0.18, 1.25, -0.04], 0.25), ([0.05, 1.75, 0], 0.22), ([-0.1, 1.0, 0.1], 0.18)]
        for (offset, r) in blobs {
            let e = ModelEntity(mesh: .generateSphere(radius: r), materials: [leaf])
            e.position = plantBase + offset
            root.addChild(e)
        }

        // Wall-mounted tablet (right wall)
        box([0.03, 0.2, 0.28], at: [CafeLayout.roomMaxX - 0.02, 1.5, -9.3], M.pbr(0x111111, roughness: 0.2), in: root)
    }

    // MARK: - Exterior

    private static func buildExterior(into root: Entity) {
        let stone = M.pbr(M.stoneFacade, roughness: 0.55)
        let lightStone = M.pbr(0xDAD7D1, roughness: 0.35)
        let warm = M.glow(M.warmLED)

        // Street and pavement (the café floor is at y = 0; the street sits two steps lower).
        let street = ModelEntity(mesh: .generatePlane(width: 40, depth: 30), materials: [M.pbr(M.street, roughness: 0.9)])
        street.position = [0, -0.34, 16.5]
        root.addChild(street)

        // Two steps with gold LED nosing
        box([5.2, 0.17, 0.8], at: [0, -0.255, 1.4], lightStone, in: root)
        box([5.2, 0.17, 1.0], at: [0, -0.085, 0.6], lightStone, in: root)
        box([5.2, 0.015, 0.02], at: [0, -0.175, 1.81], warm, in: root)
        box([5.2, 0.015, 0.02], at: [0, -0.005, 1.11], warm, in: root)
        box([1.4, 0.01, 0.5], at: [0.5, 0.005, 0.5], M.pbr(0x161616, roughness: 0.9), in: root)  // door mat

        // Facade: outer skin in front of the inside wall, leaving the doorway open.
        let facadeZ: Float = 0.2
        let fw: Float = 14, fh: Float = 7.5
        let side = (fw - 2 * CafeLayout.doorHalfWidth) / 2
        box([side, fh, 0.2], at: [-(CafeLayout.doorHalfWidth + side / 2), fh / 2, facadeZ], stone, in: root)
        box([side, fh, 0.2], at: [CafeLayout.doorHalfWidth + side / 2, fh / 2, facadeZ], stone, in: root)
        box([2 * CafeLayout.doorHalfWidth, fh - CafeLayout.doorHeight, 0.2],
            at: [0, CafeLayout.doorHeight + (fh - CafeLayout.doorHeight) / 2, facadeZ], stone, in: root)
        // Doorway reveal so the opening reads as deep
        box([0.12, CafeLayout.doorHeight, 0.42], at: [-CafeLayout.doorHalfWidth - 0.06, CafeLayout.doorHeight / 2, 0.0], lightStone, in: root)
        box([0.12, CafeLayout.doorHeight, 0.42], at: [CafeLayout.doorHalfWidth + 0.06, CafeLayout.doorHeight / 2, 0.0], lightStone, in: root)

        // Portal pillars and canopy framing the entrance
        for x: Float in [-1.55, 1.55] {
            box([0.55, 3.5, 0.6], at: [x, 1.75, 0.55], lightStone, in: root)
        }
        box([3.7, 0.55, 0.9], at: [0, 3.78, 0.65], lightStone, in: root)
        box([0.14, 0.14, 0.02], at: [0, 3.48, 1.05], M.glow(0xFFFFFF), in: root)

        // Black frame around the glass doors
        let frame = M.pbr(0x101010, roughness: 0.35, metallic: 0.6)
        box([2 * CafeLayout.doorHalfWidth + 0.12, 0.12, 0.12], at: [0, CafeLayout.doorHeight - 0.06, 0.06], frame, in: root)
        box([2 * CafeLayout.doorHalfWidth, 0.42, 0.04], at: [0, CafeLayout.doorHeight - 0.33, 0.06], M.glass(tint: 0x0C0C0C, opacity: 0.85), in: root)

        // Illuminated signage: Arabic over Latin, in glowing gold above the canopy.
        let signWidth: Float = 3.6
        let sign = panel(width: signWidth, height: signWidth * 0.497, at: [0, 5.0, 1.12],
                         M.glowTexture("sign_logotype", transparent: true), in: root)
        sign.name = "sign"
        box([4.4, 1.9, 0.2], at: [0, 5.0, 1.0], M.pbr(0xBFBBB4, roughness: 0.5), in: root)

        // Lit windows either side, hinting at the warm interior.
        for x: Float in [-4.6, 4.6] {
            panel(width: 2.6, height: 2.6, at: [x, 1.6, facadeZ + 0.105], M.glow(0xE8C890, alpha: 0.92), in: root)
            box([2.7, 0.06, 0.06], at: [x, 0.28, facadeZ + 0.13], frame, in: root)
            box([2.7, 0.06, 0.06], at: [x, 2.92, facadeZ + 0.13], frame, in: root)
        }
    }

    /// Two black-framed glass leaves hinged at the outer edges, opening inward.
    private static func buildDoors(into root: Entity) -> (Entity, Entity) {
        let frame = M.pbr(0x0E0E0E, roughness: 0.3, metallic: 0.7)
        let glass = M.glass(tint: 0x20262B, opacity: 0.18)
        let leafWidth = CafeLayout.doorHalfWidth
        let leafHeight = CafeLayout.doorHeight - 0.5

        func leaf(hingeX: Float, direction: Float) -> Entity {
            let pivot = Entity()
            pivot.position = [hingeX, 0, 0.06]
            let c: Float = direction * leafWidth / 2  // centre of the leaf relative to the hinge
            let w = leafWidth
            box([w - 0.1, leafHeight - 0.1, 0.012], at: [c, leafHeight / 2, 0], glass, in: pivot)
            box([w, 0.06, 0.05], at: [c, 0.03, 0], frame, in: pivot)
            box([w, 0.06, 0.05], at: [c, leafHeight - 0.03, 0], frame, in: pivot)
            box([0.06, leafHeight, 0.05], at: [c - w / 2 + 0.03, leafHeight / 2, 0], frame, in: pivot)
            box([0.06, leafHeight, 0.05], at: [c + w / 2 - 0.03, leafHeight / 2, 0], frame, in: pivot)
            // Long bar handle near the meeting edge, both faces
            let handleX = c + direction * (w / 2 - 0.12)
            box([0.025, 1.0, 0.025], at: [handleX, 1.05, 0.06], frame, in: pivot)
            box([0.025, 1.0, 0.025], at: [handleX, 1.05, -0.06], frame, in: pivot)
            root.addChild(pivot)
            return pivot
        }
        let left = leaf(hingeX: -leafWidth, direction: 1)
        let right = leaf(hingeX: leafWidth, direction: -1)
        return (left, right)
    }

    /// Swings the doors open (inward) or closed.
    static func setDoors(_ scene: CafeScene, open: Bool, animated: Bool) {
        let angle: Float = open ? 1.75 : 0
        let targets: [(Entity, Float)] = [(scene.leftDoor, angle), (scene.rightDoor, -angle)]
        for (door, a) in targets {
            var t = door.transform
            t.rotation = simd_quatf(angle: a, axis: [0, 1, 0])
            if animated {
                door.move(to: t, relativeTo: door.parent, duration: 1.9, timingFunction: .easeInOut)
            } else {
                door.transform = t
            }
        }
    }

    // MARK: - Furniture

    private static func makeTable(_ spec: CafeLayout.TableSpec) -> Entity {
        let s = CafeLayout.tableSize
        let h = CafeLayout.tableHeight
        let e = hotspot(.table(spec.number), at: spec.position, hitBox: [1.7, 1.0, 1.7], hitOffset: [0, 0.5, 0])

        // Sintered-stone top with the real veining from the overhead photo
        box([s, 0.028, s], at: [0, h - 0.014, 0],
            M.textured("tex_tabletop", fallback: 0x262626, roughness: 0.38, clearcoat: 0.4), corner: 0.012, in: e)
        let black = M.pbr(0x141414, roughness: 0.45, metallic: 0.3)
        cylinder(height: h - 0.03, radius: 0.045, at: [0, (h - 0.03) / 2, 0], black, in: e)
        cylinder(height: 0.025, radius: 0.27, at: [0, 0.0125, 0], black, in: e)

        for angle in spec.chairAngles {
            let chair = makeChair()
            chair.position = [sin(angle) * 0.6, 0, cos(angle) * 0.6]
            chair.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
            e.addChild(chair)
        }
        return e
    }

    /// Cognac leather tub chair with dark tapered legs. Front faces local -Z.
    private static func makeChair() -> Entity {
        let chair = Entity()
        let leather = M.pbr(M.leather, roughness: 0.42, clearcoat: 0.35)
        let leg = M.pbr(0x2B2420, roughness: 0.5)
        let seatY: Float = 0.47
        box([0.5, 0.08, 0.46], at: [0, seatY, 0.02], leather, corner: 0.035, in: chair)
        // Wrap-around back and arms
        box([0.52, 0.27, 0.06], at: [0, seatY + 0.2, 0.24], leather, corner: 0.03, in: chair)
        box([0.06, 0.2, 0.4], at: [-0.26, seatY + 0.17, 0.06], leather, corner: 0.03, in: chair)
        box([0.06, 0.2, 0.4], at: [0.26, seatY + 0.17, 0.06], leather, corner: 0.03, in: chair)
        for (x, z) in [(-0.21, -0.17), (0.21, -0.17), (-0.21, 0.21), (0.21, 0.21)] as [(Float, Float)] {
            let l = box([0.028, seatY, 0.028], at: [x * 1.06, seatY / 2, z * 1.06], leg, in: chair)
            l.orientation = simd_quatf(angle: x > 0 ? -0.05 : 0.05, axis: [0, 0, 1])
        }
        return chair
    }

    private static func makeCashier() -> Entity {
        let size = CafeLayout.counterSize
        let e = hotspot(.cashier, at: CafeLayout.counterCenter, hitBox: [size.x + 3.6, 2.4, 2.0], hitOffset: [-1.4, 1.2, 0])

        box(size, at: [0, size.y / 2, 0], M.textured("tex_wood", fallback: 0xC9A276, roughness: 0.55, repeat: [2, 1]), in: e)
        box([size.x + 0.04, 0.04, size.z + 0.06], at: [0, size.y + 0.02, 0], M.pbr(0xF2EFEA, roughness: 0.25), in: e)
        // Gold crest on the counter front
        panel(width: 0.42, height: 0.42 * 0.453, at: [0, size.y * 0.62, size.z / 2 + 0.006],
              M.glowTexture("logo_crest_gold", transparent: true, tint: UIColor(white: 0.85, alpha: 1)), in: e)
        // LED kick under the counter
        box([size.x, 0.02, 0.02], at: [0, 0.03, size.z / 2 + 0.02], M.glow(M.warmLED), in: e)

        // Espresso bar behind the counter, from the interior photo
        panel(width: 1.9, height: 1.25, at: [0.1, 1.55, -0.62], M.glowTexture("tex_coffee_bar"), in: e)
        box([2.4, 0.9, 0.5], at: [0, 0.45, -0.75], M.pbr(0xD9D2C6, roughness: 0.4), in: e)

        // Pastry display case to the left, photographed front panel
        let caseOffset = CafeLayout.displayCaseCenter - CafeLayout.counterCenter
        box([1.5, 0.75, 0.75], at: caseOffset + [0, 0.375, 0], M.pbr(0xB9BBBD, roughness: 0.2, metallic: 0.8), in: e)
        box([1.5, 1.28, 0.7], at: caseOffset + [0, 1.39, -0.02], M.pbr(0x2A2520, roughness: 0.6), in: e)
        panel(width: 1.5, height: 1.26, at: caseOffset + [0, 1.38, 0.34], M.glowTexture("tex_display_case"), in: e)
        return e
    }

    private static func makeManagement() -> Entity {
        let e = hotspot(.management, at: CafeLayout.managementDesk, hitBox: [1.8, 2.4, 1.6], hitOffset: [0, 1.2, 0.2])
        let wood = M.textured("tex_wood", fallback: 0xC9A276, roughness: 0.5, repeat: [1, 1])
        // Reception podium
        box([1.15, 1.05, 0.5], at: [0, 0.525, 0.25], wood, corner: 0.02, in: e)
        box([1.2, 0.035, 0.56], at: [0, 1.07, 0.25], M.pbr(0x1C1C1C, roughness: 0.3), in: e)
        panel(width: 0.34, height: 0.34 * 0.453, at: [0, 0.72, 0.505],
              M.glowTexture("logo_crest_gold", transparent: true, tint: UIColor(white: 0.85, alpha: 1)), in: e)
        // Office door behind it
        let doorZ = CafeLayout.roomBackZ - CafeLayout.managementDesk.z + 0.03
        box([1.0, 2.25, 0.05], at: [0, 1.125, doorZ], wood, in: e)
        box([0.03, 0.22, 0.03], at: [0.38, 1.05, doorZ + 0.04], M.pbr(0xB8913F, roughness: 0.3, metallic: 1), in: e)
        // Brass plaque
        box([0.36, 0.1, 0.01], at: [0, 1.75, doorZ + 0.03], M.pbr(0xB8913F, roughness: 0.25, metallic: 1), in: e)
        return e
    }

    // MARK: - Lighting

    private static func addLights(into root: Entity) {
        let warm = UIColor(red: 1.0, green: 0.86, blue: 0.68, alpha: 1)
        let interior: [SIMD3<Float>] = [[-3, 3.2, -2.5], [2.5, 3.2, -2.5], [-3, 3.2, -7], [2.5, 3.2, -6.5], [-1, 3.2, -10.3], [3.8, 3.2, -10]]
        for p in interior {
            let light = PointLight()
            light.light.color = warm
            light.light.intensity = 11000
            light.light.attenuationRadius = 9
            light.position = p
            root.addChild(light)
        }

        // Exterior: sign wash and the portal downlight
        let signWash = PointLight()
        signWash.light.color = UIColor(red: 1, green: 0.8, blue: 0.45, alpha: 1)
        signWash.light.intensity = 9000
        signWash.light.attenuationRadius = 6
        signWash.position = [0, 4.6, 2.2]
        root.addChild(signWash)

        let portal = SpotLight()
        portal.light.color = warm
        portal.light.intensity = 14000
        portal.light.innerAngleInDegrees = 30
        portal.light.outerAngleInDegrees = 60
        portal.light.attenuationRadius = 6
        portal.position = [0, 3.4, 1.0]
        portal.look(at: [0, 0, 1.4], from: portal.position, relativeTo: nil)
        root.addChild(portal)

        let fill = DirectionalLight()
        fill.light.color = UIColor(red: 0.9, green: 0.88, blue: 0.85, alpha: 1)
        fill.light.intensity = 600
        fill.look(at: [0, 0, -6], from: [3, 8, 6], relativeTo: nil)
        root.addChild(fill)
    }
}
