import SwiftUI

/// Service surface shown over the overhead view of a table.
struct TableServicePanel: View {
    @EnvironmentObject private var settings: AppSettings
    let tableNumber: Int

    enum Tab: String, CaseIterable { case reserve, order, celebrate }
    @State private var tab: Tab = .reserve

    var body: some View {
        ServicePanel(title: settings.t("طاولة \(tableNumber)", "Table \(tableNumber)"),
                     subtitle: subtitle,
                     maxHeightFraction: 0.6) {
            ChipPicker(options: Tab.allCases, selection: $tab, label: tabName, icon: tabIcon)
            switch tab {
            case .reserve: ReservationView(tableNumber: tableNumber, occasion: nil)
            case .order: OrderView(channel: .dineIn, tableNumber: tableNumber)
            case .celebrate: CelebrationView(tableNumber: tableNumber)
            }
        }
    }

    private var subtitle: String {
        let seats = CafeLayout.table(tableNumber)?.chairAngles.count ?? 4
        return settings.t("حتى \(seats) أشخاص · امسح رمز QR على الطاولة للطلب منها مباشرة",
                          "Up to \(seats) guests · scan the table's QR code to order from your seat")
    }

    private func tabName(_ t: Tab) -> String {
        switch t {
        case .reserve: return settings.t("احجز", "Reserve")
        case .order: return settings.t("اطلب", "Order")
        case .celebrate: return settings.t("مناسبة", "Celebrate")
        }
    }

    private func tabIcon(_ t: Tab) -> String {
        switch t {
        case .reserve: return "calendar"
        case .order: return "cup.and.saucer"
        case .celebrate: return "gift"
        }
    }
}

/// Date, party size and live time-slot availability for one table.
struct ReservationView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: CafeStore
    let tableNumber: Int
    let occasion: Occasion?

    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var partySize = 2
    @State private var slots: [TimeSlot] = []
    @State private var selected: TimeSlot?
    @State private var loading = false
    @State private var phone = ""
    @State private var confirmed: Reservation?

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: Date())) }
    }

    var body: some View {
        if let confirmed {
            ConfirmationCard(
                title: settings.t("تم تأكيد الحجز", "Reservation confirmed"),
                detail: settings.t("طاولة \(confirmed.tableNumber) · \(confirmed.partySize) أشخاص · \(timeText(confirmed.start))",
                                   "Table \(confirmed.tableNumber) · \(confirmed.partySize) guests · \(timeText(confirmed.start))"),
                reference: confirmed.id,
                doneTitle: settings.t("تم", "Done")
            ) { self.confirmed = nil; selected = nil }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ChipPicker(options: days, selection: $day, label: dayText)
                    Stepper(value: $partySize, in: 1...(CafeLayout.table(tableNumber)?.chairAngles.count ?? 4)) {
                        Label(settings.t("عدد الأشخاص: \(partySize)", "Guests: \(partySize)"), systemImage: "person.2.fill")
                            .font(.subheadline)
                            .foregroundStyle(Brand.ink)
                    }
                    .tint(Brand.gold)

                    if loading {
                        ProgressView().tint(Brand.gold).frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(slots) { slot in slotButton(slot) }
                        }
                    }
                    if selected != nil { PhoneField(phone: $phone) }
                    Button(settings.t("تأكيد الحجز", "Confirm reservation")) { Task { await reserve() } }
                        .buttonStyle(GoldButtonStyle())
                        .disabled(selected == nil || !PhoneField.isValid(phone))
                }
            }
            .scrollIndicators(.hidden)
            .task(id: "\(day.timeIntervalSince1970)-\(partySize)") { await loadSlots() }
        }
    }

    private func slotButton(_ slot: TimeSlot) -> some View {
        let isSelected = selected == slot
        return Button { selected = slot } label: {
            Text(timeText(slot.start))
                .font(.footnote.monospacedDigit().weight(isSelected ? .bold : .regular))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(isSelected ? .white : (slot.isAvailable ? Brand.ink : Brand.muted.opacity(0.5)))
                .background(isSelected ? Brand.gold : .white.opacity(slot.isAvailable ? 0.6 : 0.2),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .strikethrough(!slot.isAvailable)
        }
        .buttonStyle(.plain)
        .disabled(!slot.isAvailable)
        .accessibilityLabel(timeText(slot.start) + (slot.isAvailable ? "" : settings.t("، محجوز", ", unavailable")))
    }

    private func loadSlots() async {
        loading = true
        selected = nil
        slots = (try? await store.service.availability(table: tableNumber, on: day, partySize: partySize)) ?? []
        loading = false
    }

    private func reserve() async {
        guard let selected else { return }
        store.verifiedPhone = phone
        if let r = try? await store.service.reserve(table: tableNumber, at: selected.start, partySize: partySize, occasion: occasion) {
            withAnimation(.snappy) { confirmed = r }
        }
    }

    private func dayText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return settings.t("اليوم", "Today") }
        if Calendar.current.isDateInTomorrow(date) { return settings.t("غدًا", "Tomorrow") }
        return date.formatted(.dateTime.weekday(.abbreviated).day().locale(settings.language.locale))
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(settings.language.locale))
    }
}

/// Request an in-café celebration at this table.
struct CelebrationView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: CafeStore
    let tableNumber: Int

    @State private var occasion: Occasion = .birthday
    @State private var date = Date().addingTimeInterval(86_400 * 3)
    @State private var guests = 6
    @State private var notes = ""
    @State private var phone = ""
    @State private var sending = false
    @State private var ticket: SupportTicket?

    var body: some View {
        if let ticket {
            ConfirmationCard(title: settings.t("وصلنا طلبك", "Request received"),
                             detail: settings.t("سيتواصل معك فريق المناسبات لتأكيد التفاصيل.", "Our events team will contact you to confirm details."),
                             reference: ticket.id, doneTitle: settings.t("تم", "Done")) { self.ticket = nil }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ChipPicker(options: Occasion.allCases, selection: $occasion, label: occasionName)
                    DatePicker(settings.t("الموعد", "Date & time"), selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .tint(Brand.gold)
                        .environment(\.locale, settings.language.locale)
                    Stepper(settings.t("الضيوف: \(guests)", "Guests: \(guests)"), value: $guests, in: 2...40)
                    TextField(settings.t("ملاحظات (كيك، زينة، ...)", "Notes (cake, decoration, ...)"), text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    PhoneField(phone: $phone)
                    Button { Task { await send() } } label: {
                        if sending { ProgressView().tint(.white) } else { Text(settings.t("أرسل الطلب", "Send request")) }
                    }
                    .buttonStyle(GoldButtonStyle())
                    .disabled(sending || !PhoneField.isValid(phone))
                }
                .font(.subheadline)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        let message = "celebration=\(occasion.rawValue) table=\(tableNumber) guests=\(guests) at=\(date.ISO8601Format()) phone=\(phone) notes=\(notes)"
        if let t = try? await store.service.submitSupport(topic: .contact, message: message, rating: nil) {
            withAnimation(.snappy) { ticket = t }
        }
    }

    private func occasionName(_ o: Occasion) -> String {
        switch o {
        case .birthday: return settings.t("عيد ميلاد", "Birthday")
        case .anniversary: return settings.t("ذكرى", "Anniversary")
        case .graduation: return settings.t("تخرج", "Graduation")
        case .gathering: return settings.t("لقاء", "Gathering")
        case .other: return settings.t("أخرى", "Other")
        }
    }
}
