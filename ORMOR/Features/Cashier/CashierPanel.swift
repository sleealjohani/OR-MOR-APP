import SwiftUI

/// Service surface at the cashier counter.
struct CashierPanel: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: CafeStore
    @Environment(\.openURL) private var openURL

    enum Section: Hashable { case delivery, pickup, catering, menu }
    @State private var section: Section?

    var body: some View {
        ServicePanel(title: settings.t("الكاشير", "Cashier"),
                     subtitle: settings.t("اطلب للتوصيل أو الاستلام، أو جهّز مناسبتك", "Order for delivery or pickup, or plan your event"),
                     maxHeightFraction: 0.55) {
            switch section {
            case nil:
                ScrollView {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ServiceTile(title: settings.t("توصيل", "Delivery"), symbol: "scooter",
                                    caption: settings.t("إلى باب منزلك", "To your door")) { open(.delivery) }
                        ServiceTile(title: settings.t("استلام مسبق", "Pickup & advance"), symbol: "bag",
                                    caption: settings.t("اطلب الآن واستلم لاحقًا", "Order now, collect later")) { open(.pickup) }
                        ServiceTile(title: settings.t("مناسبات وضيافة", "Catering & events"), symbol: "sparkles",
                                    caption: settings.t("تجهيز خارجي", "Off-site preparation")) { open(.catering) }
                        ServiceTile(title: settings.t("القائمة", "Menu"), symbol: "menucard",
                                    caption: settings.t("المنتجات والأسعار", "Products and prices")) { open(.menu) }
                    }
                }
                .scrollIndicators(.hidden)
                Button {
                    if let url = URL(string: "tel:\(CafeInfo.phone)") { openURL(url) }
                } label: {
                    Label(settings.t("اتصل بالمقهى", "Call the café"), systemImage: "phone.fill")
                }
                .buttonStyle(OutlineButtonStyle())
            case .delivery:
                PanelSubheader(title: settings.t("توصيل", "Delivery")) { open(nil) }
                OrderView(channel: .delivery)
            case .pickup:
                PanelSubheader(title: settings.t("استلام مسبق", "Pickup & advance")) { open(nil) }
                OrderView(channel: .pickup)
            case .catering:
                PanelSubheader(title: settings.t("مناسبات وضيافة", "Catering & events")) { open(nil) }
                CateringRequestView()
            case .menu:
                PanelSubheader(title: settings.t("القائمة", "Menu")) { open(nil) }
                OrderView(channel: .pickup, browseOnly: true)
            }
        }
    }

    private func open(_ s: Section?) {
        withAnimation(.snappy(duration: 0.3)) { section = s }
    }
}

struct CateringRequestView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: CafeStore
    @State private var date = Date().addingTimeInterval(86_400 * 7)
    @State private var guests = 30
    @State private var location = ""
    @State private var notes = ""
    @State private var phone = ""
    @State private var ticket: SupportTicket?

    var body: some View {
        if let ticket {
            ConfirmationCard(title: settings.t("وصلنا طلبك", "Request received"),
                             detail: settings.t("سنرسل لك عرض سعر خلال يوم عمل.", "We'll send you a quote within one business day."),
                             reference: ticket.id, doneTitle: settings.t("تم", "Done")) { self.ticket = nil }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DatePicker(settings.t("موعد المناسبة", "Event date"), selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .tint(Brand.gold)
                        .environment(\.locale, settings.language.locale)
                    Stepper(settings.t("عدد الضيوف: \(guests)", "Guests: \(guests)"), value: $guests, in: 10...500, step: 10)
                    TextField(settings.t("الموقع / الحي", "Location / district"), text: $location)
                        .padding(12)
                        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    TextField(settings.t("تفاصيل الضيافة المطلوبة", "What would you like us to prepare?"), text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    PhoneField(phone: $phone)
                    Button(settings.t("اطلب عرض سعر", "Request a quote")) {
                        Task {
                            let message = "catering guests=\(guests) at=\(date.ISO8601Format()) location=\(location) phone=\(phone) notes=\(notes)"
                            if let t = try? await store.service.submitSupport(topic: .contact, message: message, rating: nil) {
                                withAnimation(.snappy) { ticket = t }
                            }
                        }
                    }
                    .buttonStyle(GoldButtonStyle())
                    .disabled(!PhoneField.isValid(phone) || location.isEmpty)
                }
                .font(.subheadline)
            }
            .scrollIndicators(.hidden)
        }
    }
}
