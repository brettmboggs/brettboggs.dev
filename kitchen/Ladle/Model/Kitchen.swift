import Foundation

/// A place that gets cooked in: home, mom's, the lakehouse, the office.
///
/// Each kitchen keeps its own pantry, shopping list and plan. The cookbook,
/// the staples list and every setting belong to the person and go everywhere.
struct Kitchen: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String = Kitchen.symbols[0]
    /// Whether this kitchen counts the staples as on hand. A lakehouse might
    /// not have flour; home always does.
    var assumeStaples: Bool = true
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String, symbol: String = Kitchen.symbols[0], assumeStaples: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.assumeStaples = assumeStaples
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, assumeStaples, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Kitchen"
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? Kitchen.symbols[0]
        assumeStaples = try c.decodeIfPresent(Bool.self, forKey: .assumeStaples) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    /// Icons to pick from, first is the default.
    static let symbols = [
        "house", "house.lodge", "building.2", "building", "heart", "person.2",
        "figure.2.and.child.holdinghands", "sailboat", "beach.umbrella", "mountain.2",
        "tent", "tree", "graduationcap", "briefcase", "fork.knife", "cup.and.saucer",
    ]

    /// Where this kitchen's files live, under the app's folder.
    var folder: String { "Kitchens/\(id.uuidString)" }
}

/// Every kitchen, and which one the app is showing.
struct KitchenBook: Codable, Hashable {
    var kitchens: [Kitchen]
    var currentID: UUID

    enum CodingKeys: String, CodingKey {
        case kitchens, currentID
    }

    init(kitchens: [Kitchen], currentID: UUID) {
        self.kitchens = kitchens
        self.currentID = currentID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kitchens = try c.decodeIfPresent([Kitchen].self, forKey: .kitchens) ?? []
        currentID = try c.decodeIfPresent(UUID.self, forKey: .currentID) ?? kitchens.first?.id ?? UUID()
    }
}
