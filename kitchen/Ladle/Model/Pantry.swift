import Foundation

struct PantryItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var key: String
    var aisle: Aisle
    var note: String = ""
    /// Flagged to be cooked with soon. Recipes that use it float up.
    var useSoon: Bool = false
    var addedAt: Date = Date()

    init(id: UUID = UUID(), name: String, aisle: Aisle? = nil, note: String = "", useSoon: Bool = false, addedAt: Date = Date()) {
        let cleaned = name.collapsed
        self.id = id
        self.key = IngredientKey.make(cleaned)
        self.name = IngredientCatalog.entry(for: key)?.name ?? cleaned.lowercased()
        self.aisle = aisle ?? IngredientKey.aisle(for: key)
        self.note = note
        self.useSoon = useSoon
        self.addedAt = addedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, key, aisle, note, useSoon, addedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? IngredientKey.make(name)
        aisle = try c.decodeIfPresent(Aisle.self, forKey: .aisle) ?? IngredientKey.aisle(for: key)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        useSoon = try c.decodeIfPresent(Bool.self, forKey: .useSoon) ?? false
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }

    var displayName: String { name.capitalizedFirst() }
}
