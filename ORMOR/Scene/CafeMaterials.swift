import RealityKit
import UIKit

/// Shared materials for the café, tuned to the reference photos.
@MainActor
enum CafeMaterials {
    private static var textureCache: [String: TextureResource] = [:]

    static func texture(_ name: String) -> TextureResource? {
        if let cached = textureCache[name] { return cached }
        guard let texture = try? TextureResource.load(named: name) else { return nil }
        textureCache[name] = texture
        return texture
    }

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    static func pbr(_ hex: UInt32, roughness: Float, metallic: Float = 0, clearcoat: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color(hex))
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: metallic)
        if clearcoat > 0 { m.clearcoat = .init(floatLiteral: clearcoat) }
        return m
    }

    static func textured(_ name: String, fallback hex: UInt32, roughness: Float, repeat scale: SIMD2<Float> = [1, 1], clearcoat: Float = 0) -> PhysicallyBasedMaterial {
        var m = pbr(hex, roughness: roughness, clearcoat: clearcoat)
        if let tex = texture(name) {
            m.baseColor = .init(tint: .white, texture: .init(tex))
            m.textureCoordinateTransform = .init(offset: .zero, scale: scale, rotation: 0)
        }
        return m
    }

    /// Self-lit surface (LED strips, signage, photo panels that already contain their lighting).
    static func glow(_ hex: UInt32, alpha: Float = 1) -> UnlitMaterial {
        var m = UnlitMaterial(color: color(hex))
        if alpha < 1 { m.blending = .transparent(opacity: .init(floatLiteral: alpha)) }
        return m
    }

    static func glowTexture(_ name: String, transparent: Bool = false, tint: UIColor = .white) -> UnlitMaterial {
        var m = UnlitMaterial(color: tint)
        if let tex = texture(name) {
            m.color = .init(tint: tint, texture: .init(tex))
        }
        if transparent { m.blending = .transparent(opacity: .init(floatLiteral: 1)) }
        return m
    }

    static func glass(tint hex: UInt32 = 0x1C2024, opacity: Float = 0.22) -> PhysicallyBasedMaterial {
        var m = pbr(hex, roughness: 0.04, metallic: 0.2)
        m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return m
    }

    // Palette from the photos and the brand kit
    static let ivoryWall: UInt32 = 0xE9E1D2
    static let ceiling: UInt32 = 0xF1ECE2
    static let stoneFacade: UInt32 = 0xC9C6C0
    static let charcoal: UInt32 = 0x1E1E1F
    static let leather: UInt32 = 0xA76D43
    static let warmLED: UInt32 = 0xFFD27A
    static let coolLED: UInt32 = 0xFFF6E8
    static let street: UInt32 = 0x3A3A3C
}
