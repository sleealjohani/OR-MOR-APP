import Foundation

/// Backend boundary. The prototype uses `MockCafeService`; a Supabase implementation will
/// conform to the same protocol (tables, availability, reservations, menu, orders, support).
protocol CafeService {
    func menu() async throws -> [MenuItem]
    func availability(table: Int, on day: Date, partySize: Int) async throws -> [TimeSlot]
    func reserve(table: Int, at start: Date, partySize: Int, occasion: Occasion?) async throws -> Reservation
    func placeOrder(_ lines: [CartLine], channel: OrderChannel, table: Int?) async throws -> String
    func submitSupport(topic: SupportTopic, message: String, rating: Int?) async throws -> SupportTicket
    func tickets() async throws -> [SupportTicket]
}

/// In-memory stand-in with realistic latency.
actor MockCafeService: CafeService {
    private var reservations: [Reservation] = []
    private var supportTickets: [SupportTicket] = []

    /// Sample items from the brand kit plus a few café staples (prices are placeholders).
    static let sampleMenu: [MenuItem] = [
        MenuItem(id: "latte", nameAR: "لاتيه", nameEN: "Latte", descriptionAR: "قهوة وحليب، بطعم متوازن.", descriptionEN: "Espresso and steamed milk, balanced.", price: 18, category: .hot, symbol: "cup.and.saucer.fill"),
        MenuItem(id: "spanish", nameAR: "سبانش لاتيه", nameEN: "Spanish latte", descriptionAR: "حليب مكثف محلى وإسبريسو.", descriptionEN: "Sweetened condensed milk and espresso.", price: 21, category: .hot, symbol: "cup.and.saucer.fill"),
        MenuItem(id: "v60", nameAR: "قهوة مقطرة V60", nameEN: "V60 pour-over", descriptionAR: "محصول مختار، تحضير يدوي.", descriptionEN: "Single origin, brewed by hand.", price: 24, category: .hot, symbol: "drop.fill"),
        MenuItem(id: "iced", nameAR: "قهوة باردة", nameEN: "Iced coffee", descriptionAR: "اختيار بارد للحظة هادئة.", descriptionEN: "A cold choice for a quiet moment.", price: 20, category: .cold, symbol: "takeoutbag.and.cup.and.straw.fill"),
        MenuItem(id: "coldbrew", nameAR: "كولد برو", nameEN: "Cold brew", descriptionAR: "منقوع ١٨ ساعة.", descriptionEN: "Steeped for 18 hours.", price: 22, category: .cold, symbol: "takeoutbag.and.cup.and.straw.fill"),
        MenuItem(id: "tea", nameAR: "شاي", nameEN: "Tea", descriptionAR: "شاي أسود أو أخضر.", descriptionEN: "Black or green tea.", price: 12, category: .tea, symbol: "mug.fill"),
        MenuItem(id: "karak", nameAR: "كرك", nameEN: "Karak", descriptionAR: "شاي بالحليب والهيل.", descriptionEN: "Milk tea with cardamom.", price: 10, category: .tea, symbol: "mug.fill"),
        MenuItem(id: "cake", nameAR: "كيكة اليوم", nameEN: "Cake of the day", descriptionAR: "من واجهة الحلويات.", descriptionEN: "From the pastry display.", price: 26, category: .dessert, symbol: "birthday.cake.fill"),
        MenuItem(id: "croissant", nameAR: "كرواسون", nameEN: "Croissant", descriptionAR: "زبدة، مخبوز اليوم.", descriptionEN: "All-butter, baked today.", price: 14, category: .dessert, symbol: "fork.knife"),
    ]

    func menu() async throws -> [MenuItem] {
        try await Task.sleep(nanoseconds: 250_000_000)
        return Self.sampleMenu
    }

    func availability(table: Int, on day: Date, partySize: Int) async throws -> [TimeSlot] {
        try await Task.sleep(nanoseconds: 300_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let open = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: day) ?? day
        let booked = Set(reservations.filter { $0.tableNumber == table && calendar.isDate($0.start, inSameDayAs: day) }.map(\.start))
        let seats = CafeLayout.table(table)?.chairAngles.count ?? 4
        return (0..<14).compactMap { i in
            guard let start = calendar.date(byAdding: .minute, value: 30 * i, to: open) else { return nil }
            // Deterministic pseudo-availability so the prototype feels real but repeatable.
            let busy = (i * 7 + table * 3 + calendar.component(.day, from: day)) % 5 == 0
            let available = !busy && !booked.contains(start) && partySize <= seats && start > Date()
            return TimeSlot(start: start, isAvailable: available)
        }
    }

    func reserve(table: Int, at start: Date, partySize: Int, occasion: Occasion?) async throws -> Reservation {
        try await Task.sleep(nanoseconds: 600_000_000)
        let r = Reservation(id: "R-" + String(Int.random(in: 10_000...99_999)), tableNumber: table, start: start, partySize: partySize, occasion: occasion)
        reservations.append(r)
        return r
    }

    func placeOrder(_ lines: [CartLine], channel: OrderChannel, table: Int?) async throws -> String {
        try await Task.sleep(nanoseconds: 700_000_000)
        return "O-" + String(Int.random(in: 1_000...9_999))
    }

    func submitSupport(topic: SupportTopic, message: String, rating: Int?) async throws -> SupportTicket {
        try await Task.sleep(nanoseconds: 500_000_000)
        let ticket = SupportTicket(id: "S-" + String(Int.random(in: 1_000...9_999)), topic: topic, message: message,
                                   rating: rating, createdAt: Date(), status: "received")
        supportTickets.insert(ticket, at: 0)
        return ticket
    }

    func tickets() async throws -> [SupportTicket] { supportTickets }
}
