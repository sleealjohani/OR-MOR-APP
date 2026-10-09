import Foundation

struct MenuItem: Identifiable, Hashable {
    enum Category: String, CaseIterable, Identifiable {
        case hot, cold, tea, dessert
        var id: String { rawValue }
    }

    let id: String
    let nameAR: String
    let nameEN: String
    let descriptionAR: String
    let descriptionEN: String
    let price: Double
    let category: Category
    let symbol: String  // SF Symbol until product photography is available
}

struct CartLine: Identifiable, Hashable {
    var item: MenuItem
    var quantity: Int
    var id: String { item.id }
    var total: Double { item.price * Double(quantity) }
}

struct TimeSlot: Identifiable, Hashable {
    let start: Date
    let isAvailable: Bool
    var id: Date { start }
}

enum OrderChannel: String, CaseIterable, Identifiable {
    case dineIn, delivery, pickup
    var id: String { rawValue }
}

enum Occasion: String, CaseIterable, Identifiable {
    case birthday, anniversary, graduation, gathering, other
    var id: String { rawValue }
}

enum SupportTopic: String, CaseIterable, Identifiable {
    case contact, complaint, suggestion, rating, followUp
    var id: String { rawValue }
}

struct Reservation: Identifiable, Hashable {
    let id: String
    let tableNumber: Int
    let start: Date
    let partySize: Int
    let occasion: Occasion?
}

struct SupportTicket: Identifiable, Hashable {
    let id: String
    let topic: SupportTopic
    let message: String
    let rating: Int?
    let createdAt: Date
    var status: String
}
