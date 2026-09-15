import Foundation

// MARK: - Ingredient

struct Ingredient: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// The line as written or as last edited. Always kept, so nothing the
    /// parser misunderstood is ever lost.
    var text: String
    var quantity: Double?
    /// The top of a range: "2–3 cloves".
    var quantityMax: Double?
    /// A canonical unit id from `Units`, or nil for a bare count.
    var unit: String?
    var name: String
    /// Everything after the comma: "chopped", "at room temperature".
    var prep: String?
    var isHeading: Bool = false
    var isOptional: Bool = false

    init(id: UUID = UUID(), text: String, quantity: Double? = nil, quantityMax: Double? = nil, unit: String? = nil, name: String, prep: String? = nil, isHeading: Bool = false, isOptional: Bool = false) {
        self.id = id
        self.text = text
        self.quantity = quantity
        self.quantityMax = quantityMax
        self.unit = unit
        self.name = name
        self.prep = prep
        self.isHeading = isHeading
        self.isOptional = isOptional
    }

    static func heading(_ title: String) -> Ingredient {
        Ingredient(text: title, name: title, isHeading: true)
    }

    /// The pantry key this ingredient matches on.
    var key: String { IngredientKey.make(name) }

    enum CodingKeys: String, CodingKey {
        case id, text, quantity, quantityMax, unit, name, prep, isHeading, isOptional
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity)
        quantityMax = try c.decodeIfPresent(Double.self, forKey: .quantityMax)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? text
        prep = try c.decodeIfPresent(String.self, forKey: .prep)
        isHeading = try c.decodeIfPresent(Bool.self, forKey: .isHeading) ?? false
        isOptional = try c.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
    }
}

// MARK: - Step

struct Step: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var isHeading: Bool = false

    init(id: UUID = UUID(), text: String, isHeading: Bool = false) {
        self.id = id
        self.text = text
        self.isHeading = isHeading
    }

    enum CodingKeys: String, CodingKey {
        case id, text, isHeading
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        isHeading = try c.decodeIfPresent(Bool.self, forKey: .isHeading) ?? false
    }
}

// MARK: - Cook log

struct CookEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    /// 0 means unrated.
    var rating: Int
    var note: String

    init(id: UUID = UUID(), date: Date = Date(), rating: Int = 0, note: String = "") {
        self.id = id
        self.date = date
        self.rating = rating
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, date, rating, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

// MARK: - Source

struct RecipeSource: Codable, Hashable {
    enum Kind: String, Codable {
        case written
        case scanned
        case web
        case file
    }

    var kind: Kind = .written
    var name: String?
    var url: URL?
    var author: String?

    init(kind: Kind = .written, name: String? = nil, url: URL? = nil, author: String? = nil) {
        self.kind = kind
        self.name = name
        self.url = url
        self.author = author
    }

    enum CodingKeys: String, CodingKey {
        case kind, name, url, author
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .written
        name = try c.decodeIfPresent(String.self, forKey: .name)
        url = try? c.decodeIfPresent(URL.self, forKey: .url)
        author = try c.decodeIfPresent(String.self, forKey: .author)
    }

    /// "From Grandma's card", "smittenkitchen.com", "Bon Appétit".
    var label: String? {
        if let name = name?.nilIfBlank { return name }
        if let author = author?.nilIfBlank { return author }
        if let host = url?.host() {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        switch kind {
        case .scanned: return "Scanned"
        case .file: return "Shared"
        case .web, .written: return nil
        }
    }
}

// MARK: - Nutrition

struct Nutrition: Codable, Hashable {
    var calories: String?
    var fat: String?
    var carbohydrates: String?
    var protein: String?
    var fiber: String?
    var sugar: String?
    var sodium: String?

    var isEmpty: Bool {
        [calories, fat, carbohydrates, protein, fiber, sugar, sodium].allSatisfy { $0?.nilIfBlank == nil }
    }

    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    var rows: [Row] {
        let pairs: [(String, String?)] = [
            ("Calories", calories), ("Fat", fat), ("Carbs", carbohydrates), ("Protein", protein),
            ("Fiber", fiber), ("Sugar", sugar), ("Sodium", sodium),
        ]
        return pairs.compactMap { pair in
            guard let value = pair.1?.nilIfBlank else { return nil }
            return Row(label: pair.0, value: value)
        }
    }
}

// MARK: - Recipe

struct Recipe: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    /// A short line under the title. The story, if there is one.
    var headnote: String = ""
    var ingredients: [Ingredient] = []
    var steps: [Step] = []
    var servings: Int?
    /// "12 cookies", "one 9-inch pie". Shown instead of a bare number.
    var yieldText: String?
    var prepMinutes: Int?
    var cookMinutes: Int?
    /// Set when a source states a total that is not prep + cook.
    var totalMinutesOverride: Int?
    var tags: [String] = []
    var source: RecipeSource = RecipeSource()
    var photoID: String?
    /// The scanned card or page this came from, kept as the heirloom.
    var scanIDs: [String] = []
    var notes: String = ""
    var isFavorite: Bool = false
    /// Imported without anyone looking at it yet.
    var needsReview: Bool = false
    var cookLog: [CookEntry] = []
    var nutrition: Nutrition?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    init(title: String, ingredients: [Ingredient] = [], steps: [Step] = [], source: RecipeSource = RecipeSource()) {
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id, title, headnote, ingredients, steps, servings, yieldText, prepMinutes, cookMinutes,
             totalMinutesOverride, tags, source, photoID, scanIDs, notes, isFavorite, needsReview,
             cookLog, nutrition, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        headnote = try c.decodeIfPresent(String.self, forKey: .headnote) ?? ""
        ingredients = try c.decodeIfPresent([Ingredient].self, forKey: .ingredients) ?? []
        steps = try c.decodeIfPresent([Step].self, forKey: .steps) ?? []
        servings = try c.decodeIfPresent(Int.self, forKey: .servings)
        yieldText = try c.decodeIfPresent(String.self, forKey: .yieldText)
        prepMinutes = try c.decodeIfPresent(Int.self, forKey: .prepMinutes)
        cookMinutes = try c.decodeIfPresent(Int.self, forKey: .cookMinutes)
        totalMinutesOverride = try c.decodeIfPresent(Int.self, forKey: .totalMinutesOverride)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        source = try c.decodeIfPresent(RecipeSource.self, forKey: .source) ?? RecipeSource()
        photoID = try c.decodeIfPresent(String.self, forKey: .photoID)
        scanIDs = try c.decodeIfPresent([String].self, forKey: .scanIDs) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        needsReview = try c.decodeIfPresent(Bool.self, forKey: .needsReview) ?? false
        cookLog = try c.decodeIfPresent([CookEntry].self, forKey: .cookLog) ?? []
        nutrition = try c.decodeIfPresent(Nutrition.self, forKey: .nutrition)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    // MARK: Derived

    var totalMinutes: Int? {
        if let totalMinutesOverride, totalMinutesOverride > 0 { return totalMinutesOverride }
        let sum = (prepMinutes ?? 0) + (cookMinutes ?? 0)
        return sum > 0 ? sum : nil
    }

    /// Ingredients that are things, not headings.
    var realIngredients: [Ingredient] {
        ingredients.filter { !$0.isHeading }
    }

    var realSteps: [Step] {
        steps.filter { !$0.isHeading && !$0.text.isBlank }
    }

    var timesCooked: Int { cookLog.count }

    var lastCooked: Date? { cookLog.map(\.date).max() }

    var averageRating: Double? {
        let rated = cookLog.map(\.rating).filter { $0 > 0 }
        guard !rated.isEmpty else { return nil }
        return Double(rated.reduce(0, +)) / Double(rated.count)
    }

    /// Everything search should find.
    var searchText: String {
        ([title, headnote, notes] + tags + realIngredients.map(\.name) + [source.label ?? ""])
            .joined(separator: " ")
            .lowercased()
    }

    /// "45 min · Serves 4".
    var metaLine: String {
        var parts: [String] = []
        if let total = totalMinutes { parts.append(Format.minutes(total)) }
        if let yield = Format.yield(servings: servings, text: yieldText) { parts.append(yield) }
        return parts.joined(separator: " · ")
    }

    var isQuick: Bool {
        guard let total = totalMinutes else { return false }
        return total <= 30
    }

    /// Ingredients mentioned in a step's text, for the cook screen.
    func ingredientsMentioned(in step: Step) -> [Ingredient] {
        let lower = step.text.lowercased()
        return realIngredients.filter { ingredient in
            let words = IngredientKey.significantWords(ingredient.name)
            guard let head = words.last else { return false }
            return lower.containsWord(head) || (words.count > 1 && lower.containsWord(words.joined(separator: " ")))
        }
    }
}

extension String {
    /// Whole-word containment, so "egg" is not found inside "eggplant".
    func containsWord(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let pattern = "(?<![a-z])" + NSRegularExpression.escapedPattern(for: word) + "(?:s|es)?(?![a-z])"
        return range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
