import Foundation
import simd

/// Interactive places in the café. The camera always rests at one of these.
enum CafeSpot: Hashable, Identifiable {
    case exterior
    case hub
    case table(Int)
    case cashier
    case management

    var id: String {
        switch self {
        case .exterior: return "exterior"
        case .hub: return "hub"
        case .table(let n): return "table-\(n)"
        case .cashier: return "cashier"
        case .management: return "management"
        }
    }

    /// Parses a hotspot entity name such as "hotspot:table-3".
    init?(hotspotName: String) {
        guard hotspotName.hasPrefix(CafeLayout.hotspotPrefix) else { return nil }
        let id = String(hotspotName.dropFirst(CafeLayout.hotspotPrefix.count))
        switch id {
        case "cashier": self = .cashier
        case "management": self = .management
        default:
            guard id.hasPrefix("table-"), let n = Int(id.dropFirst("table-".count)) else { return nil }
            self = .table(n)
        }
    }
}

/// World layout of the café, in metres.
///
/// Axes: +X to the right when facing the entrance from the street, +Y up, -Z deeper into the café.
/// The glass doors sit at z = 0. Positions are measured by eye from the reference photos in
/// docs/reference-photos and are meant to be tuned (or replaced by a scanned model's anchors).
enum CafeLayout {
    static let hotspotPrefix = "hotspot:"

    // Room shell
    static let roomMinX: Float = -6.2
    static let roomMaxX: Float = 6.2
    static let roomBackZ: Float = -12.0
    static let ceilingHeight: Float = 3.6
    static let doorHalfWidth: Float = 0.9
    static let doorHeight: Float = 2.75

    // Furniture
    static let tableHeight: Float = 0.75
    static let tableSize: Float = 0.72

    struct TableSpec {
        let number: Int
        let position: SIMD3<Float>  // floor point under the table centre
        let chairAngles: [Float]   // radians around the table; 0 = chair on the +Z (entrance) side
    }

    /// Chairs at 0 (front), +90° and -90°: the arrangement in the overhead photo.
    private static let threeChairs: [Float] = [0, .pi / 2, -.pi / 2]
    private static let fourChairs: [Float] = [0, .pi / 2, -.pi / 2, .pi]

    static let tables: [TableSpec] = [
        TableSpec(number: 1, position: [0.75, 0, -5.55], chairAngles: threeChairs),  // against the column
        TableSpec(number: 2, position: [4.4, 0, -6.4], chairAngles: fourChairs),
        TableSpec(number: 3, position: [-3.4, 0, -4.4], chairAngles: fourChairs),
        TableSpec(number: 4, position: [3.7, 0, -2.9], chairAngles: fourChairs),
    ]

    static let column = SIMD3<Float>(0.65, 0, -6.6)
    static let columnRadius: Float = 0.45

    static let counterCenter = SIMD3<Float>(0.9, 0, -10.2)
    static let counterSize = SIMD3<Float>(2.4, 1.08, 0.75)
    static let displayCaseCenter = SIMD3<Float>(-2.3, 0, -10.0)
    static let managementDesk = SIMD3<Float>(4.7, 0, -10.6)

    static func table(_ number: Int) -> TableSpec? { tables.first { $0.number == number } }

    // MARK: - Camera poses

    static let standingEye: Float = 1.62

    /// Resting viewpoint just inside the entrance.
    static let hubPose = CameraPose.look(from: [0.1, 1.7, -0.7], at: [0.55, 1.15, -8.5], fov: 76)

    /// Poses for the opening fly-through: street → doors → inside → hub.
    static let introKeys: [CameraPose] = [
        .look(from: [0.0, 2.3, 15.0], at: [0.0, 4.0, 0.0], fov: 58),
        .look(from: [0.0, 1.9, 7.5], at: [0.0, 2.2, 0.0], fov: 62),
        .look(from: [0.0, 1.7, 2.6], at: [0.0, 1.55, -3.0], fov: 66),
        .look(from: [0.05, 1.68, 0.4], at: [0.4, 1.3, -6.0], fov: 70),
        hubPose,
    ]
    /// Fraction of the intro (in spline distance) at which the doors start to open.
    static let introDoorTrigger: Float = 0.28

    /// Full camera route from the hub to a spot (first key is the hub).
    static func route(to spot: CafeSpot, aspect: Float) -> [CameraPose] {
        switch spot {
        case .exterior:
            return Array(introKeys.reversed())
        case .hub:
            return [hubPose]
        case .table(let n):
            guard let spec = table(n) else { return [hubPose] }
            return [hubPose] + tableApproach(spec, aspect: aspect)
        case .cashier:
            // Pass left of the column, then face the counter as a customer would.
            return [
                hubPose,
                .look(from: [-1.2, 1.66, -5.2], at: [0.2, 1.3, -10.4], fov: 68),
                framed(target: counterCenter + [0, 0.95, counterSize.z / 2], from: [counterCenter.x - 1.4, 1.95, counterCenter.z + 3.7], fov: 66),
            ]
        case .management:
            return [
                hubPose,
                .look(from: [2.3, 1.68, -4.6], at: [4.6, 1.3, -10.4], fov: 68),
                framed(target: managementDesk + [0, 1.0, 0.5], from: [managementDesk.x - 0.45, 1.95, managementDesk.z + 3.3], fov: 66),
            ]
        }
    }

    /// Fraction of the screen height (from the bottom) where a framed object should sit,
    /// above the service panel that covers the lower half.
    static let panelFramingHeight: Float = 0.76

    /// Looks from `position` so that `target` appears horizontally centred at `screenHeight`
    /// (0 = bottom edge, 1 = top edge) of a camera with vertical field of view `fov`.
    static func framed(target: SIMD3<Float>, from position: SIMD3<Float>, fov: Float, screenHeight: Float = panelFramingHeight) -> CameraPose {
        let flat = SIMD3<Float>(target.x - position.x, 0, target.z - position.z)
        let distance = max(simd_length(flat), 0.01)
        let direction = flat / distance
        let elevation = atan2(target.y - position.y, distance)
        let offset = atan((2 * screenHeight - 1) * tan(fov * .pi / 360))
        let pitch = elevation - offset
        let lookPoint = position + direction * cos(pitch) + SIMD3<Float>(0, sin(pitch), 0)
        return .look(from: position, at: lookPoint, fov: fov)
    }

    /// Approach from the hub side, then rise and rotate into a true 90° overhead view of the tabletop.
    static func tableApproach(_ table: TableSpec, aspect: Float) -> [CameraPose] {
        let top = table.position + [0, tableHeight, 0]
        let toTable = simd_normalize(SIMD3<Float>(top.x - hubPose.position.x, 0, top.z - hubPose.position.z))
        let approach = top - toTable * 1.55 + [0, 0.75, 0]
        let overheadFOV: Float = 70
        let pose = overheadPose(for: top, aspect: aspect, fov: overheadFOV)
        return [
            .look(from: approach, at: top + [0, 0.05, 0], fov: 66),
            pose,
        ]
    }

    /// Overhead framing: the tabletop and the chairs around it fit across the screen width,
    /// with the table placed in the upper part of the screen so the service panel can sit below it.
    static func overheadPose(for tableTop: SIMD3<Float>, aspect: Float, fov: Float) -> CameraPose {
        let halfWidthToShow: Float = 0.82  // tabletop (0.36) + chair depth, with a little breathing room
        let tanHalfV = tan(fov * .pi / 360)
        let tanHalfH = tanHalfV * max(aspect, 0.3)
        let height = min(halfWidthToShow / tanHalfH, ceilingHeight - tableHeight - 0.15)
        // Screen-up is -Z, so moving the camera toward +Z pushes the table up the screen.
        let lift = height * tanHalfV * 0.42
        return .overhead(above: tableTop + [0, 0, lift], height: height, screenUp: [0, 0, -1], fov: fov)
    }

    /// World point a hotspot label floats over.
    static func labelAnchor(for spot: CafeSpot) -> SIMD3<Float>? {
        switch spot {
        case .table(let n): return table(n).map { $0.position + [0, tableHeight + 0.35, 0] }
        case .cashier: return counterCenter + [-1.75, counterSize.y + 0.7, 0.3]  // between display case and column, where it's visible
        case .management: return managementDesk + [0, 1.75, 0]
        default: return nil
        }
    }

    static var interactiveSpots: [CafeSpot] {
        tables.map { .table($0.number) } + [.cashier, .management]
    }
}
