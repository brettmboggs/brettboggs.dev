import Foundation

/// Reduces an ingredient description to the key it is matched on.
///
/// "2 boneless, skinless chicken thighs, trimmed" and a pantry entry typed as
/// "Chicken thighs" both come out as `chicken thighs`. The same normaliser
/// builds the catalogue's alias table, so the two sides can never drift.
enum IngredientKey {
    static let stopwords: Set<String> = [
        "a", "an", "the", "of", "and", "or", "with", "for", "to", "in", "into", "from", "on", "at",
        "about", "approximately", "some", "any", "your", "favorite", "favourite", "good", "quality",
        "best", "brand", "style", "type", "regular", "real", "pure", "natural", "plain", "homemade",
        "store", "bought", "prepared", "fresh", "freshly", "large", "small", "medium", "extra",
        "big", "little", "tiny", "jumbo", "mini", "baby", "virgin", "cold", "warm", "lukewarm",
        "chopped", "minced", "diced", "sliced", "grated", "shredded", "crushed", "softened",
        "melted", "beaten", "packed", "sifted", "peeled", "seeded", "cored", "pitted", "trimmed",
        "halved", "quartered", "cubed", "cut", "pieces", "piece", "chunks", "chunk", "inch",
        "inches", "thick", "thin", "thinly", "thickly", "finely", "roughly", "coarsely", "lightly",
        "firmly", "divided", "plus", "more", "optional", "taste", "needed", "serving", "garnish",
        "room", "temperature", "ripe", "unsalted", "salted", "lowfat", "nonfat", "reduced", "low",
        "fat", "free", "sodium", "unsweetened", "sweetened", "heaping", "level", "scant", "rounded",
        "generous", "each", "total", "boneless", "skinless", "bone", "skin", "lean", "organic",
        "raw", "leftover", "additional", "if", "desired", "as", "such", "like", "very", "well",
        "washed", "rinsed", "drained", "thawed", "defrosted", "uncooked", "cooled", "chilled",
        "hot", "heated", "toasted", "roasted", "quality", "premium", "fine", "coarse", "half",
        "halves", "whole", "wedges", "wedge", "sticks", "strips", "rings", "florets", "spears",
        "sprigs", "sprig", "leaves", "leaf", "stalks", "stalk", "ribs", "rib", "heads", "head",
        "bunch", "bunches", "cloves", "clove", "cans", "can", "jar", "jars", "package", "packages",
        "pkg", "bag", "bags", "box", "boxes", "bottle", "bottles", "carton", "container", "pinch",
        "dash", "splash", "handful", "cup", "cups", "tablespoon", "tablespoons", "tbsp", "teaspoon",
        "teaspoons", "tsp", "ounce", "ounces", "oz", "pound", "pounds", "lb", "lbs", "gram", "grams",
        "g", "kg", "ml", "liter", "litre", "quart", "pint", "gallon",
    ]

    /// Words that carry meaning even though they look like descriptors.
    /// Removed from the stopword list at build time so a typo above cannot
    /// swallow them.
    private static let keep: Set<String> = [
        "green", "red", "white", "black", "yellow", "sweet", "sour", "dried", "frozen", "canned",
        "ground", "cooked", "instant", "light", "dark", "brown", "heavy", "double", "single",
        "cream", "sea", "kosher", "wheat", "whole",
    ]

    static let effectiveStopwords: Set<String> = stopwords.subtracting(keep)

    private static let dropPhrases: [NSRegularExpression] = [
        #"\bto taste\b"#, #"\bfor (?:serving|garnish|the pan|greasing|frying|dusting|brushing|drizzling|topping|sprinkling|rolling)\b"#,
        #"\bas needed\b"#, #"\bif (?:needed|desired)\b"#, #"\bor (?:more|less)(?: to taste)?\b"#,
        #"\bat room temperature\b"#, #"\bplus (?:more|extra).*$"#, #"\band (?:more|extra).*$"#,
        #"\bsuch as .*$"#, #"\bpreferably .*$"#, #"\bdivided\b"#, #"\boptional\b"#, #"\babout\b"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// Lowercase words, hyphens split, punctuation and numbers gone, stopwords
    /// removed, each word singular.
    static func normalizedPhrase(_ text: String) -> String {
        significantWords(text).joined(separator: " ")
    }

    static func significantWords(_ text: String) -> [String] {
        var lower = text.lowercased()
        lower = lower.replacingOccurrences(of: "'", with: "")
        lower = lower.replacingOccurrences(of: "’", with: "")
        lower = lower.replacingOccurrences(of: "&", with: " and ")
        var words: [String] = []
        var current = ""
        for ch in lower {
            if ch.isLetter {
                current.append(ch)
            } else {
                if !current.isEmpty { words.append(current) }
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
            .filter { !effectiveStopwords.contains($0) }
            .map(singular)
    }

    /// The canonical key for a recipe ingredient or a pantry entry.
    static func make(_ name: String) -> String {
        var text = name.lowercased()
        // Parentheticals and everything after the first comma are notes.
        while let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") {
            text.removeSubrange(open...close)
        }
        if let comma = text.firstIndex(of: ",") {
            text = String(text[..<comma])
        }
        for regex in dropPhrases {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: " ")
        }
        let phrase = normalizedPhrase(text)
        guard !phrase.isEmpty else {
            let fallback = normalizedPhrase(name)
            return fallback.isEmpty ? name.lowercased().collapsed : fallback
        }
        if let exact = IngredientCatalog.byAlias[phrase] { return exact }

        let words = phrase.split(separator: " ").map(String.init)
        let padded = " " + phrase + " "
        for (aliasKey, canonical) in IngredientCatalog.aliasesByLength {
            let aliasWords = aliasKey.split(separator: " ")
            if aliasWords.count >= 2 {
                if padded.contains(" " + aliasKey + " ") { return canonical }
            } else if let last = words.last, last == aliasKey {
                // A single known word only counts as the head noun:
                // "garlic bread" is bread, not garlic.
                return canonical
            }
        }
        if words.count > 3 {
            return words.suffix(3).joined(separator: " ")
        }
        return phrase
    }

    private static let irregular: [String: String] = [
        "leaves": "leaf", "halves": "half", "loaves": "loaf", "knives": "knife", "tomatoes": "tomato",
        "potatoes": "potato", "mangoes": "mango", "cookies": "cookie", "brownies": "brownie",
        "anchovies": "anchovy", "berries": "berry", "cherries": "cherry", "strawberries": "strawberry",
        "blueberries": "blueberry", "raspberries": "raspberry", "blackberries": "blackberry",
        "cranberries": "cranberry", "pastries": "pastry", "jalapeños": "jalapeño", "jalapenos": "jalapeno",
        "avocados": "avocado", "pistachios": "pistachio", "radishes": "radish", "peaches": "peach",
        "sandwiches": "sandwich", "hummus": "hummus", "couscous": "couscous", "molasses": "molasses",
        "asparagus": "asparagus", "swiss": "swiss", "grits": "grits", "oats": "oats", "chips": "chips",
        "sprinkles": "sprinkles", "greens": "greens",
    ]

    static func singular(_ word: String) -> String {
        if let known = irregular[word] { return known }
        guard word.count > 3 else { return word }
        if word.hasSuffix("ss") || word.hasSuffix("us") || word.hasSuffix("is") { return word }
        if word.hasSuffix("ies") && word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") { return String(word.dropLast(2)) }
        if word.hasSuffix("ches") || word.hasSuffix("shes") || word.hasSuffix("xes") || word.hasSuffix("zes") || word.hasSuffix("sses") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s") { return String(word.dropLast()) }
        return word
    }

    /// A readable name for a key: the catalogue spelling when there is one.
    static func displayName(for key: String) -> String {
        if let entry = IngredientCatalog.entry(for: key) { return entry.name }
        return key
    }

    static func aisle(for key: String) -> Aisle {
        IngredientCatalog.entry(for: key)?.aisle ?? .other
    }
}

// MARK: - Pantry index

/// The pantry as something to ask questions of, built once per query.
struct PantryIndex {
    let pantryKeys: Set<String>
    let stapleKeys: Set<String>
    /// Catalogue parents of what is on hand: cheddar in the pantry means
    /// "cheese" is covered.
    private let coveredParents: Set<String>
    /// Last words of pantry entries the catalogue does not know, so a typed
    /// "farro" still meets a recipe's "pearl farro".
    private let looseTails: Set<String>

    init(pantry: [PantryItem], staples: Set<String>) {
        let keys = Set(pantry.map(\.key))
        pantryKeys = keys
        stapleKeys = staples
        var parents = Set<String>()
        var tails = Set<String>()
        for key in keys.union(staples) {
            if let entry = IngredientCatalog.entry(for: key) {
                if let parent = entry.parent { parents.insert(parent) }
            } else if let tail = key.split(separator: " ").last {
                tails.insert(String(tail))
            }
        }
        coveredParents = parents
        looseTails = tails
    }

    static let empty = PantryIndex(pantry: [], staples: [])

    var isEmpty: Bool { pantryKeys.isEmpty }

    /// Whether the kitchen can supply `key`, counting staples.
    func has(_ key: String) -> Bool {
        if pantryKeys.contains(key) || stapleKeys.contains(key) { return true }
        if coveredParents.contains(key) { return true }
        if let entry = IngredientCatalog.entry(for: key) {
            if let parent = entry.parent, pantryKeys.contains(parent) || stapleKeys.contains(parent) { return true }
            return false
        }
        // Unknown to the catalogue: match on the head word either way.
        if let tail = key.split(separator: " ").last {
            let t = String(tail)
            if looseTails.contains(t) || pantryKeys.contains(t) { return true }
        }
        return false
    }

    /// Whether the match came from the pantry proper or an assumed staple.
    func isStapleOnly(_ key: String) -> Bool {
        guard !pantryKeys.contains(key) else { return false }
        if stapleKeys.contains(key) { return true }
        if let parent = IngredientCatalog.entry(for: key)?.parent, stapleKeys.contains(parent), !pantryKeys.contains(parent) {
            return true
        }
        return false
    }
}

// MARK: - Availability

struct IngredientMatch: Identifiable {
    enum Status {
        case have
        case staple
        case substitute(Substitution)
        case missing
    }

    let ingredient: Ingredient
    let status: Status

    var id: UUID { ingredient.id }

    var isCovered: Bool {
        switch status {
        case .have, .staple, .substitute: return true
        case .missing: return false
        }
    }

    var substitution: Substitution? {
        if case .substitute(let s) = status { return s }
        return nil
    }
}

/// How close a recipe is to cookable with what is in the kitchen.
struct Availability: Identifiable {
    let recipe: Recipe
    let matches: [IngredientMatch]

    var id: UUID { recipe.id }

    /// Missing ingredients that are not optional.
    var missing: [Ingredient] {
        matches.filter { !$0.isCovered && !$0.ingredient.isOptional }.map(\.ingredient)
    }

    var missingOptional: [Ingredient] {
        matches.filter { !$0.isCovered && $0.ingredient.isOptional }.map(\.ingredient)
    }

    var substitutions: [IngredientMatch] {
        matches.filter { $0.substitution != nil }
    }

    var haveCount: Int { matches.filter(\.isCovered).count }
    var total: Int { matches.count }

    var canMake: Bool { total > 0 && missing.isEmpty }
    var isClose: Bool { !canMake && total > 0 && missing.count <= 2 }

    /// 0 to 1, substitutions counting a little less than the real thing.
    var score: Double {
        guard total > 0 else { return 0 }
        var points = 0.0
        for match in matches {
            switch match.status {
            case .have, .staple: points += 1
            case .substitute: points += 0.85
            case .missing: points += match.ingredient.isOptional ? 1 : 0
            }
        }
        return points / Double(total)
    }

    /// "Missing garlic and lemon", "1 swap", "Ready".
    var summary: String {
        if canMake {
            let swaps = substitutions.count
            if swaps == 0 { return "Ready to cook" }
            return swaps == 1 ? "Ready, with 1 swap" : "Ready, with \(swaps) swaps"
        }
        let names = missing.prefix(3).map { IngredientKey.displayName(for: $0.key) }
        var text = "Missing " + names.joined(separator: ", ")
        if missing.count > 3 { text += " +\(missing.count - 3)" }
        return text
    }

    static func compute(_ recipe: Recipe, index: PantryIndex) -> Availability {
        let matches = recipe.realIngredients.map { ingredient -> IngredientMatch in
            let key = ingredient.key
            if index.has(key) {
                return IngredientMatch(ingredient: ingredient, status: index.isStapleOnly(key) ? .staple : .have)
            }
            if let sub = Substitutions.available(for: key, in: index) {
                return IngredientMatch(ingredient: ingredient, status: .substitute(sub))
            }
            return IngredientMatch(ingredient: ingredient, status: .missing)
        }
        return Availability(recipe: recipe, matches: matches)
    }
}
