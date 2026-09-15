import Foundation

struct ShoppingItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var key: String
    var quantity: Double?
    var unit: String?
    var note: String = ""
    var aisle: Aisle
    var isChecked: Bool = false
    /// The recipes that asked for it, so the list can say why.
    var recipeIDs: [UUID] = []
    var addedAt: Date = Date()

    init(id: UUID = UUID(), name: String, quantity: Double? = nil, unit: String? = nil, note: String = "", aisle: Aisle? = nil, recipeIDs: [UUID] = []) {
        let cleaned = name.collapsed
        self.id = id
        self.key = IngredientKey.make(cleaned)
        self.name = IngredientCatalog.entry(for: key)?.name ?? cleaned.lowercased()
        self.quantity = quantity
        self.unit = unit
        self.note = note
        self.aisle = aisle ?? IngredientKey.aisle(for: key)
        self.recipeIDs = recipeIDs
    }

    enum CodingKeys: String, CodingKey {
        case id, name, key, quantity, unit, note, aisle, isChecked, recipeIDs, addedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? IngredientKey.make(name)
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        aisle = try c.decodeIfPresent(Aisle.self, forKey: .aisle) ?? IngredientKey.aisle(for: key)
        isChecked = try c.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false
        recipeIDs = try c.decodeIfPresent([UUID].self, forKey: .recipeIDs) ?? []
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }

    var displayName: String { name.capitalizedFirst() }

    func quantityText(system: UnitSystem) -> String {
        QuantityText.string(quantity: quantity, quantityMax: nil, unit: unit, scale: 1, system: system, abbreviated: true)
    }

    /// "2 cups · for Lasagna".
    var detail: String {
        note
    }
}

enum ShoppingMerge {
    /// Adds an ingredient to the list, folding it into an unchecked line for
    /// the same thing when the units allow it.
    static func add(_ ingredient: Ingredient, scale: Double, recipeID: UUID?, into items: inout [ShoppingItem]) {
        let key = ingredient.key
        let quantity = ingredient.quantity.map { $0 * scale }
        if let index = items.firstIndex(where: { $0.key == key && !$0.isChecked }) {
            var existing = items[index]
            if let recipeID, !existing.recipeIDs.contains(recipeID) {
                existing.recipeIDs.append(recipeID)
            }
            if let quantity {
                if let total = existing.quantity, let summed = Units.sum(total, existing.unit, plus: quantity, ingredient.unit) {
                    existing.quantity = summed.0
                    existing.unit = summed.1
                } else if existing.quantity == nil && existing.note.isEmpty {
                    existing.quantity = quantity
                    existing.unit = ingredient.unit
                } else {
                    let extra = QuantityText.string(quantity: quantity, quantityMax: nil, unit: ingredient.unit, scale: 1, system: .us, abbreviated: true)
                    if !extra.isEmpty {
                        existing.note = existing.note.isEmpty ? "+ \(extra)" : existing.note + ", + \(extra)"
                    }
                }
            }
            items[index] = existing
        } else {
            var item = ShoppingItem(
                name: ingredient.name,
                quantity: quantity,
                unit: ingredient.unit,
                recipeIDs: recipeID.map { [$0] } ?? []
            )
            if let prep = ingredient.prep, prep.count < 30, ingredient.quantity == nil {
                item.note = prep
            }
            items.append(item)
        }
    }
}
