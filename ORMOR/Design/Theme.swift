import SwiftUI

/// Brand palette. `gold` is measured from the printed cup (brand kit); `glowGold` matches the lit signage.
enum Brand {
    static let gold = Color(hex: 0x836117)
    static let glowGold = Color(hex: 0xD6A84B)
    static let ink = Color(hex: 0x22231E)
    static let charcoal = Color(hex: 0x242424)
    static let paper = Color(hex: 0xF5F0E3)
    static let ivory = Color(hex: 0xF5F0E6)
    static let cognac = Color(hex: 0xA76D43)
    static let muted = Color(hex: 0x5C5D55)
    static let line = Color(hex: 0xD4CCBC)
    static let success = Color(hex: 0x315C42)
    static let error = Color(hex: 0x963C36)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Interim OFL fonts from the brand kit: Reem Kufi for headings, Noto Sans Arabic for Arabic body text,
/// Noto Serif for English body text.
enum BrandFont {
    static func heading(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Reem Kufi", size: size, relativeTo: style)
    }

    static func body(_ size: CGFloat = 16, language: AppLanguage, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        switch language {
        case .ar: return .custom("Noto Sans Arabic", size: size, relativeTo: style).weight(weight)
        case .en: return .custom("Noto Serif", size: size, relativeTo: style).weight(weight)
        }
    }
}

/// Translucent panel used for every service surface, so panels feel layered over the scene.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 26

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(Brand.paper.opacity(0.55), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Brand.glowGold.opacity(0.7), Brand.glowGold.opacity(0.1)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 26) -> some View { modifier(GlassPanel(cornerRadius: cornerRadius)) }
}

/// Primary action button in measured brand gold.
struct GoldButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Brand.gold.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Secondary outlined button.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Brand.gold)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Brand.paper.opacity(configuration.isPressed ? 0.9 : 0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.gold.opacity(0.6), lineWidth: 1))
    }
}
