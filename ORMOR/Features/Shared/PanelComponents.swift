import SwiftUI

/// Shared state for services and the cart.
@MainActor
final class CafeStore: ObservableObject {
    let service: CafeService
    @Published var menu: [MenuItem] = []
    @Published var cart: [CartLine] = []
    @Published var verifiedPhone: String?

    init(service: CafeService = MockCafeService()) {
        self.service = service
    }

    var cartCount: Int { cart.reduce(0) { $0 + $1.quantity } }
    var cartTotal: Double { cart.reduce(0) { $0 + $1.total } }

    func loadMenu() async {
        guard menu.isEmpty else { return }
        menu = (try? await service.menu()) ?? []
    }

    func add(_ item: MenuItem) {
        if let i = cart.firstIndex(where: { $0.item.id == item.id }) {
            cart[i].quantity += 1
        } else {
            cart.append(CartLine(item: item, quantity: 1))
        }
    }

    func remove(_ item: MenuItem) {
        guard let i = cart.firstIndex(where: { $0.item.id == item.id }) else { return }
        cart[i].quantity -= 1
        if cart[i].quantity <= 0 { cart.remove(at: i) }
    }

    func quantity(of item: MenuItem) -> Int { cart.first { $0.item.id == item.id }?.quantity ?? 0 }
}

/// Café contact details. TODO: replace with the real number before release.
enum CafeInfo {
    static let phone = "+966500000000"
}

/// A floating service surface over the 3D scene.
struct ServicePanel<Content: View>: View {
    @EnvironmentObject private var settings: AppSettings
    let title: String
    var subtitle: String?
    var maxHeightFraction: CGFloat = 0.56
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 14) {
                    Capsule().fill(Brand.gold.opacity(0.35)).frame(width: 38, height: 4)
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(BrandFont.heading(26))
                            .foregroundStyle(Brand.ink)
                        if let subtitle {
                            Text(subtitle)
                                .font(BrandFont.body(13, language: settings.language))
                                .foregroundStyle(Brand.muted)
                        }
                    }
                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: geo.size.height * maxHeightFraction, alignment: .top)
                .glassPanel()
                .padding(.horizontal, 10)
            }
        }
    }
}

/// Horizontal chip picker used for tabs and filters.
struct ChipPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var icon: ((Value) -> String)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let selected = option == selection
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { selection = option }
                    } label: {
                        HStack(spacing: 6) {
                            if let icon { Image(systemName: icon(option)).font(.caption) }
                            Text(label(option))
                        }
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .foregroundStyle(selected ? .white : Brand.ink)
                        .background(selected ? Brand.gold : Brand.paper.opacity(0.7), in: Capsule())
                        .overlay(Capsule().strokeBorder(Brand.gold.opacity(selected ? 0 : 0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// Square tile for a service entry point (cashier and management).
struct ServiceTile: View {
    let title: String
    let symbol: String
    var caption: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Brand.gold)
                    .frame(width: 40, height: 40)
                    .background(Brand.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(Brand.muted).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(12)
            .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Small header row with a back control for nested panel content.
struct PanelSubheader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(Brand.paper, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Brand.gold)
            Text(title).font(.headline).foregroundStyle(Brand.ink)
            Spacer()
        }
    }
}

/// Success state shown after a request is accepted.
struct ConfirmationCard: View {
    let title: String
    let detail: String
    let reference: String
    let doneTitle: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Brand.gold)
                .symbolEffect(.bounce, value: reference)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Brand.ink)
            Text(detail).font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
            Text(reference)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .environment(\.layoutDirection, .leftToRight)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Brand.paper, in: Capsule())
            Button(doneTitle, action: onDone).buttonStyle(OutlineButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// Lightweight identification by mobile number (OTP verification arrives with the backend).
struct PhoneField: View {
    @EnvironmentObject private var settings: AppSettings
    @Binding var phone: String

    static func isValid(_ phone: String) -> Bool {
        let digits = phone.filter(\.isNumber)
        return (digits.hasPrefix("05") && digits.count == 10) || (digits.hasPrefix("9665") && digits.count == 12)
    }

    var body: some View {
        HStack {
            Image(systemName: "phone.fill").foregroundStyle(Brand.gold)
            TextField(settings.t("رقم الجوال 05xxxxxxxx", "Mobile number 05xxxxxxxx"), text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .environment(\.layoutDirection, .leftToRight)
                .multilineTextAlignment(settings.language == .ar ? .trailing : .leading)
            if Self.isValid(phone) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.success)
            }
        }
        .padding(12)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.line, lineWidth: 1))
    }
}
