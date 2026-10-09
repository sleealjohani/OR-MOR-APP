import SwiftUI

/// Menu browsing, cart and checkout. Used from a table (dine-in) and from the cashier (delivery / pickup).
struct OrderView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: CafeStore
    let channel: OrderChannel
    var tableNumber: Int?
    var browseOnly = false

    @State private var category: MenuItem.Category = .hot
    @State private var showingCart = false
    @State private var placing = false
    @State private var orderReference: String?

    var body: some View {
        Group {
            if let orderReference {
                ConfirmationCard(
                    title: settings.t("تم استلام طلبك", "Order received"),
                    detail: confirmationDetail,
                    reference: orderReference,
                    doneTitle: settings.t("تم", "Done")
                ) { self.orderReference = nil }
            } else if showingCart {
                cart
            } else {
                menu
            }
        }
        .task { await store.loadMenu() }
    }

    private var confirmationDetail: String {
        switch channel {
        case .dineIn: return settings.t("سيصل طلبك إلى طاولة \(tableNumber ?? 0).", "Your order will be brought to table \(tableNumber ?? 0).")
        case .delivery: return settings.t("سنرسل لك تحديثات حالة التوصيل.", "We'll send you delivery status updates.")
        case .pickup: return settings.t("سنبلغك عندما يصبح جاهزًا للاستلام.", "We'll let you know when it's ready to collect.")
        }
    }

    // MARK: Menu

    private var menu: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChipPicker(options: MenuItem.Category.allCases, selection: $category, label: categoryName)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if store.menu.isEmpty {
                        ProgressView().tint(Brand.gold).padding(.vertical, 30)
                    }
                    ForEach(store.menu.filter { $0.category == category }) { item in
                        row(item)
                    }
                }
            }
            .scrollIndicators(.hidden)
            if !browseOnly && store.cartCount > 0 {
                Button {
                    withAnimation(.snappy) { showingCart = true }
                } label: {
                    HStack {
                        Image(systemName: "bag.fill")
                        Text(settings.t("السلة · \(store.cartCount)", "Cart · \(store.cartCount)"))
                        Spacer()
                        Text(settings.price(store.cartTotal))
                    }
                    .padding(.horizontal, 16)
                }
                .buttonStyle(GoldButtonStyle())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func row(_ item: MenuItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.title3)
                .foregroundStyle(Brand.gold)
                .frame(width: 48, height: 48)
                .background(Brand.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.t(item.nameAR, item.nameEN)).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                Text(settings.t(item.descriptionAR, item.descriptionEN)).font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
                Text(settings.price(item.price)).font(.caption.weight(.semibold)).foregroundStyle(Brand.gold)
            }
            Spacer()
            if !browseOnly { stepper(item) }
        }
        .padding(10)
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stepper(_ item: MenuItem) -> some View {
        let qty = store.quantity(of: item)
        return HStack(spacing: 8) {
            if qty > 0 {
                Button { withAnimation(.snappy) { store.remove(item) } } label: { Image(systemName: "minus") }
                    .accessibilityLabel(settings.t("إزالة", "Remove"))
                Text("\(qty)").font(.subheadline.monospacedDigit()).frame(minWidth: 16)
            }
            Button { withAnimation(.snappy) { store.add(item) } } label: { Image(systemName: "plus") }
                .accessibilityLabel(settings.t("إضافة \(item.nameAR)", "Add \(item.nameEN)"))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Brand.gold)
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .frame(minHeight: 36)
        .background(Brand.paper, in: Capsule())
        .sensoryFeedback(.selection, trigger: qty)
    }

    // MARK: Cart & checkout

    private var cart: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSubheader(title: settings.t("السلة", "Cart")) { withAnimation(.snappy) { showingCart = false } }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.cart) { line in
                        HStack {
                            Text("\(line.quantity)×").monospacedDigit().foregroundStyle(Brand.muted)
                            Text(settings.t(line.item.nameAR, line.item.nameEN)).foregroundStyle(Brand.ink)
                            Spacer()
                            Text(settings.price(line.total)).foregroundStyle(Brand.ink)
                        }
                        .font(.subheadline)
                    }
                    Divider().overlay(Brand.line)
                    HStack {
                        Text(settings.t("الإجمالي", "Total")).font(.headline)
                        Spacer()
                        Text(settings.price(store.cartTotal)).font(.headline).foregroundStyle(Brand.gold)
                    }
                    paymentNote
                }
            }
            Button {
                Task { await place() }
            } label: {
                if placing { ProgressView().tint(.white) } else { Text(checkoutTitle) }
            }
            .buttonStyle(GoldButtonStyle())
            .disabled(placing || store.cart.isEmpty)
        }
    }

    private var checkoutTitle: String {
        switch channel {
        case .dineIn: return settings.t("أرسل الطلب للطاولة", "Send order to table")
        case .delivery: return settings.t("اطلب توصيل", "Order for delivery")
        case .pickup: return settings.t("اطلب للاستلام", "Order for pickup")
        }
    }

    private var paymentNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "creditcard.fill").foregroundStyle(Brand.gold)
            Text(settings.t("الدفع عبر Apple Pay ومدى سيُفعّل مع مزوّد الدفع. في النموذج الأولي: الدفع عند الاستلام.",
                            "Apple Pay and mada will be enabled with the payment provider. Prototype: pay on collection."))
                .font(.caption)
                .foregroundStyle(Brand.muted)
        }
        .padding(10)
        .background(Brand.paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func place() async {
        placing = true
        defer { placing = false }
        if let ref = try? await store.service.placeOrder(store.cart, channel: channel, table: tableNumber) {
            store.cart.removeAll()
            showingCart = false
            withAnimation(.snappy) { orderReference = ref }
        }
    }

    private func categoryName(_ c: MenuItem.Category) -> String {
        switch c {
        case .hot: return settings.t("ساخن", "Hot")
        case .cold: return settings.t("بارد", "Cold")
        case .tea: return settings.t("شاي", "Tea")
        case .dessert: return settings.t("حلى", "Sweets")
        }
    }
}
