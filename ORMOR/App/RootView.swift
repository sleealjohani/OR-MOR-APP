import SwiftUI

/// The café is the home screen: the 3D scene fills the display and every service lives in it.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @StateObject private var director = CameraDirector()
    @StateObject private var projector = HotspotProjector()
    @StateObject private var store = CafeStore()

    @State private var showLogo = true
    @State private var showSettings = false
    @State private var started = false

    private var reduceMotion: Bool { systemReduceMotion || settings.reduceMotionOverride }
    private var isIdle: Bool { director.phase == .idle }

    var body: some View {
        ZStack {
            CafeSceneView(director: director, projector: projector, quality: settings.graphicsQuality) { spot in
                director.go(to: spot)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)

            if director.spot == .hub && isIdle {
                HotspotLabelsView(projector: projector) { director.go(to: $0) }
                    .transition(.opacity)
                hubHint
            }

            if isIdle { panel }

            if !showLogo && director.phase != .intro { topBar }

            if showLogo {
                LogoIntroView(reduceMotion: reduceMotion) {
                    director.playIntro()
                } onFinished: {
                    withAnimation(.easeOut(duration: 0.3)) { showLogo = false }
                    settings.hasSeenIntro = true
                }
                .transition(.opacity)
            }

            if (director.phase == .intro || showLogo) && settings.hasSeenIntro {
                skipButton
            }

            // Reduced motion: dissolve around the camera cut instead of flying.
            Brand.charcoal
                .ignoresSafeArea()
                .opacity(reduceMotion && director.phase == .moving ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: director.phase)
                .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: director.spot)
        .animation(.easeInOut(duration: 0.3), value: director.phase)
        .environment(\.layoutDirection, settings.language.layoutDirection)
        .environment(\.locale, settings.language.locale)
        .environmentObject(store)
        .statusBarHidden(showLogo || director.phase == .intro)
        .sensoryFeedback(.impact(weight: .light), trigger: director.spot)
        .sheet(isPresented: $showSettings) {
            SettingsView { replayIntro() }
                .environment(\.layoutDirection, settings.language.layoutDirection)
                .presentationDetents([.medium, .large])
        }
        .onAppear(perform: start)
        .onChange(of: reduceMotion, initial: true) { _, value in director.reduceMotion = value }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var panel: some View {
        Group {
            switch director.spot {
            case .table(let n): TableServicePanel(tableNumber: n).id(n)
            case .cashier: CashierPanel()
            case .management: ManagementPanel()
            default: EmptyView()
            }
        }
        .padding(.bottom, 6)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .bottom))))
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                if director.spot != .hub {
                    CircleButton(symbol: "chevron.backward", label: settings.t("رجوع", "Back")) { director.back() }
                        .disabled(!isIdle)
                } else {
                    LogoShape(parts: .crest)
                        .fill(Brand.glowGold)
                        .frame(width: 54, height: 44)
                        .environment(\.layoutDirection, .leftToRight)
                        .shadow(color: .black.opacity(0.35), radius: 6)
                        .accessibilityLabel("OR & MOR")
                }
                Spacer()
                QuickNavMenu(director: director, onSettings: { showSettings = true }, onReplayIntro: replayIntro)
                    .disabled(!isIdle)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            Spacer()
        }
        .transition(.opacity)
    }

    private var hubHint: some View {
        VStack {
            Spacer()
            Label(settings.t("اسحب للنظر حولك · المس طاولة أو الكاشير أو الإدارة",
                             "Drag to look around · tap a table, the cashier or management"),
                  systemImage: "hand.tap")
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.black.opacity(0.35), in: Capsule())
                .padding(.bottom, 28)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var skipButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(settings.t("تخطي", "Skip")) { skipIntro() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.black.opacity(0.35), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Flow

    private func start() {
        guard !started else { return }
        started = true
        director.reduceMotion = reduceMotion
        // Debug / screenshot hook: `-startSpot table-1|cashier|management|hub` skips the intro.
        if let id = UserDefaults.standard.string(forKey: "startSpot") {
            showLogo = false
            director.jumpToHub()
            if let spot = CafeSpot(hotspotName: CafeLayout.hotspotPrefix + id) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { director.go(to: spot) }
            }
            return
        }
        if settings.hasSeenIntro && settings.autoSkipIntro {
            showLogo = false
            director.jumpToHub()
        }
    }

    private func skipIntro() {
        withAnimation(.easeOut(duration: 0.3)) { showLogo = false }
        director.jumpToHub()
    }

    private func replayIntro() {
        showSettings = false
        director.resetToExterior()
        withAnimation(.easeIn(duration: 0.3)) { showLogo = true }
    }
}

/// Floating labels over interactive objects at the hub; also the accessible way to choose a spot.
struct HotspotLabelsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var projector: HotspotProjector
    var onSelect: (CafeSpot) -> Void

    var body: some View {
        ZStack {
            ForEach(Array(projector.points.keys), id: \.self) { spot in
                if let point = projector.points[spot] {
                    Button { onSelect(spot) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: symbol(spot)).font(.caption.weight(.semibold))
                            Text(name(spot)).font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Brand.ink)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Brand.glowGold.opacity(0.8), lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .position(point)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)  // positions are screen-space points
        .ignoresSafeArea()
    }

    private func name(_ spot: CafeSpot) -> String {
        switch spot {
        case .table(let n): return settings.t("طاولة \(n)", "Table \(n)")
        case .cashier: return settings.t("الكاشير", "Cashier")
        case .management: return settings.t("الإدارة", "Management")
        default: return ""
        }
    }

    private func symbol(_ spot: CafeSpot) -> String {
        switch spot {
        case .table: return "square.split.diagonal"
        case .cashier: return "cup.and.saucer.fill"
        case .management: return "person.crop.circle.badge.questionmark"
        default: return "circle"
        }
    }
}

/// Conventional navigation for anyone who prefers it (and for VoiceOver).
struct QuickNavMenu: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var director: CameraDirector
    var onSettings: () -> Void
    var onReplayIntro: () -> Void

    var body: some View {
        Menu {
            Button { director.goHome() } label: { Label(settings.t("المدخل", "Entrance"), systemImage: "door.left.hand.open") }
            Section(settings.t("الطاولات", "Tables")) {
                ForEach(CafeLayout.tables, id: \.number) { t in
                    Button { director.go(to: .table(t.number)) } label: {
                        Label(settings.t("طاولة \(t.number)", "Table \(t.number)"), systemImage: "square.split.diagonal")
                    }
                }
            }
            Button { director.go(to: .cashier) } label: { Label(settings.t("الكاشير والطلبات", "Cashier & orders"), systemImage: "cup.and.saucer") }
            Button { director.go(to: .management) } label: { Label(settings.t("الإدارة", "Management"), systemImage: "person.crop.circle") }
            Divider()
            Button(action: onReplayIntro) { Label(settings.t("إعادة المقدمة", "Replay intro"), systemImage: "play.circle") }
            Button(action: onSettings) { Label(settings.t("الإعدادات", "Settings"), systemImage: "gearshape") }
        } label: {
            CircleButtonLabel(symbol: "line.3.horizontal")
        }
        .accessibilityLabel(settings.t("قائمة التنقل", "Navigation menu"))
    }
}

struct CircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { CircleButtonLabel(symbol: symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}

struct CircleButtonLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Brand.ink)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Brand.glowGold.opacity(0.6), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }
}
