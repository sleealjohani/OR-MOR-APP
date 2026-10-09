import SwiftUI

/// Opening title: the crest draws itself in light, fills with gold, the Arabic and Latin names
/// are revealed in their reading directions, a highlight passes over, then everything lifts away.
struct LogoIntroView: View {
    var reduceMotion: Bool
    /// Called when the logo starts lifting away; the 3D fly-through should begin here.
    var onReveal: () -> Void
    /// Called when the overlay has fully faded.
    var onFinished: () -> Void

    @State private var backdrop = 0.0
    @State private var stroke: CGFloat = 0
    @State private var fill = 0.0
    @State private var arabicReveal: CGFloat = 0
    @State private var latinReveal: CGFloat = 0
    @State private var shimmer: CGFloat = -0.4
    @State private var lift = 0.0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width * 0.78, 360)
            ZStack {
                RadialGradient(colors: [Color(hex: 0x2E2A24), Color(hex: 0x0D0D0E)],
                               center: .center, startRadius: 10, endRadius: geo.size.height * 0.7)
                    .ignoresSafeArea()
                    .opacity(backdrop * (1 - lift))

                logo
                    .frame(width: side, height: side * LogoShape.viewBox.height / LogoShape.viewBox.width)
                    .scaleEffect(1 + 0.1 * lift)
                    .opacity(1 - lift)
                    .blur(radius: 6 * lift)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.46)
            }
        }
        .environment(\.layoutDirection, .leftToRight)  // the artwork is not mirrored
        .allowsHitTesting(false)
        .accessibilityLabel("OR & MOR — أور أند مور")
        .task { await play() }
    }

    private var logo: some View {
        let gold = LinearGradient(colors: [Color(hex: 0xF3D58A), Brand.glowGold, Color(hex: 0xA67C2E)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        return ZStack {
            // Crest: traced in light, then filled
            LogoShape(parts: .crest)
                .trim(from: 0, to: stroke)
                .stroke(Brand.glowGold, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                .shadow(color: Brand.glowGold.opacity(0.8), radius: 6)
                .opacity(1 - fill * 0.85)
            LogoShape(parts: .crest).fill(gold).opacity(fill)

            // Arabic name revealed right-to-left, Latin left-to-right
            LogoShape(parts: .arabic).fill(gold)
                .mask(alignment: .trailing) { revealMask(arabicReveal, alignment: .trailing) }
            LogoShape(parts: .latin).fill(gold)
                .mask(alignment: .leading) { revealMask(latinReveal, alignment: .leading) }

            // A single soft highlight sweeping across the finished mark
            LogoShape(parts: .all)
                .fill(LinearGradient(stops: [.init(color: .clear, location: 0),
                                             .init(color: .white.opacity(0.75), location: 0.5),
                                             .init(color: .clear, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
                .mask {
                    GeometryReader { g in
                        Rectangle()
                            .frame(width: g.size.width * 0.35)
                            .rotationEffect(.degrees(18))
                            .offset(x: g.size.width * shimmer)
                    }
                }
                .blendMode(.plusLighter)
        }
    }

    private func revealMask(_ amount: CGFloat, alignment: Alignment) -> some View {
        GeometryReader { g in
            LinearGradient(colors: [.black, .black, .clear],
                           startPoint: alignment == .leading ? .leading : .trailing,
                           endPoint: alignment == .leading ? .trailing : .leading)
                .frame(width: g.size.width * amount * 1.3)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private func play() async {
        if reduceMotion {
            fill = 1; stroke = 1; arabicReveal = 1; latinReveal = 1
            withAnimation(.easeOut(duration: 0.3)) { backdrop = 1 }
            guard await pause(0.9) else { return }
            onReveal()
            withAnimation(.easeInOut(duration: 0.5)) { lift = 1 }
            guard await pause(0.5) else { return }
            onFinished()
            return
        }
        withAnimation(.easeOut(duration: 0.4)) { backdrop = 1 }
        guard await pause(0.25) else { return }
        withAnimation(.easeInOut(duration: 1.8)) { stroke = 1 }
        guard await pause(1.45) else { return }
        withAnimation(.easeInOut(duration: 0.8)) { fill = 1 }
        guard await pause(0.35) else { return }
        withAnimation(.easeOut(duration: 0.9)) { arabicReveal = 1 }
        guard await pause(0.3) else { return }
        withAnimation(.easeOut(duration: 0.9)) { latinReveal = 1 }
        guard await pause(0.75) else { return }
        withAnimation(.easeInOut(duration: 1.0)) { shimmer = 1.2 }
        guard await pause(1.05) else { return }
        onReveal()
        withAnimation(.easeIn(duration: 1.1)) { lift = 1 }
        guard await pause(1.1) else { return }
        onFinished()
    }

    /// Returns false if the intro was dismissed (the view disappeared), so no later step fires.
    private func pause(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }
}
