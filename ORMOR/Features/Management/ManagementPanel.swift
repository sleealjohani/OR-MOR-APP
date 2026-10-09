import SwiftUI

/// Service surface at the management desk: contact, complaints, suggestions, ratings, follow-up.
struct ManagementPanel: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var topic: SupportTopic?

    var body: some View {
        ServicePanel(title: settings.t("الإدارة وتجربة العملاء", "Management & guest care"),
                     subtitle: settings.t("نسمعك ونتابع طلبك حتى إغلاقه", "We listen, and follow your request through"),
                     maxHeightFraction: 0.55) {
            if let topic {
                PanelSubheader(title: name(topic)) { withAnimation(.snappy) { self.topic = nil } }
                if topic == .followUp {
                    TicketListView()
                } else {
                    SupportFormView(topic: topic)
                }
            } else {
                ScrollView {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(SupportTopic.allCases) { t in
                            ServiceTile(title: name(t), symbol: symbol(t)) { withAnimation(.snappy) { topic = t } }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func name(_ t: SupportTopic) -> String {
        switch t {
        case .contact: return settings.t("تواصل مع الإدارة", "Contact management")
        case .complaint: return settings.t("شكوى", "Complaint")
        case .suggestion: return settings.t("اقتراح", "Suggestion")
        case .rating: return settings.t("قيّم تجربتك", "Rate your visit")
        case .followUp: return settings.t("متابعة طلباتي", "Track my requests")
        }
    }

    private func symbol(_ t: SupportTopic) -> String {
        switch t {
        case .contact: return "envelope"
        case .complaint: return "exclamationmark.bubble"
        case .suggestion: return "lightbulb"
        case .rating: return "star"
        case .followUp: return "clock.arrow.circlepath"
        }
    }
}

struct SupportFormView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: CafeStore
    let topic: SupportTopic

    @State private var message = ""
    @State private var rating = 0
    @State private var phone = ""
    @State private var sending = false
    @State private var ticket: SupportTicket?

    var body: some View {
        if let ticket {
            ConfirmationCard(title: settings.t("شكرًا لك", "Thank you"),
                             detail: settings.t("وصلت رسالتك إلى الإدارة. يمكنك متابعتها من «متابعة طلباتي».",
                                                "Your message reached management. Track it under “Track my requests”."),
                             reference: ticket.id, doneTitle: settings.t("تم", "Done")) { self.ticket = nil; message = ""; rating = 0 }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if topic == .rating {
                        HStack(spacing: 10) {
                            ForEach(1...5, id: \.self) { i in
                                Button { rating = i } label: {
                                    Image(systemName: i <= rating ? "star.fill" : "star")
                                        .font(.title2)
                                        .foregroundStyle(Brand.glowGold)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(settings.t("\(i) نجوم", "\(i) stars"))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .sensoryFeedback(.selection, trigger: rating)
                    }
                    TextField(placeholder, text: $message, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    PhoneField(phone: $phone)
                    Button { Task { await send() } } label: {
                        if sending { ProgressView().tint(.white) } else { Text(settings.t("إرسال", "Send")) }
                    }
                    .buttonStyle(GoldButtonStyle())
                    .disabled(sending || !canSend)
                }
                .font(.subheadline)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var canSend: Bool {
        PhoneField.isValid(phone) && (topic == .rating ? rating > 0 : !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var placeholder: String {
        switch topic {
        case .complaint: return settings.t("ما الذي حدث؟ سنعالجه بجدية.", "What happened? We'll take it seriously.")
        case .suggestion: return settings.t("فكرتك لتحسين أور أند مور", "Your idea to improve OR & MOR")
        case .rating: return settings.t("أخبرنا المزيد (اختياري)", "Tell us more (optional)")
        default: return settings.t("رسالتك للإدارة", "Your message to management")
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        if let t = try? await store.service.submitSupport(topic: topic, message: message, rating: topic == .rating ? rating : nil) {
            withAnimation(.snappy) { ticket = t }
        }
    }
}

struct TicketListView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: CafeStore
    @State private var tickets: [SupportTicket] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if tickets.isEmpty {
                    Text(settings.t("لا توجد طلبات بعد.", "No requests yet."))
                        .font(.subheadline).foregroundStyle(Brand.muted).padding(.vertical, 24)
                }
                ForEach(tickets) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.id).font(.subheadline.monospaced().weight(.semibold))
                            Text(t.createdAt.formatted(.dateTime.day().month().hour().minute().locale(settings.language.locale)))
                                .font(.caption).foregroundStyle(Brand.muted)
                        }
                        Spacer()
                        Text(settings.t("تم الاستلام", "Received"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Brand.success.opacity(0.12), in: Capsule())
                            .foregroundStyle(Brand.success)
                    }
                    .padding(12)
                    .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .task { tickets = (try? await store.service.tickets()) ?? [] }
    }
}
