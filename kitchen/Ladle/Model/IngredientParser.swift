import Foundation

/// Turns "1 1/2 cups all-purpose flour, sifted" into parts a recipe can scale,
/// convert and match against the pantry. The original line is always kept on
/// the ingredient, so a wrong guess here costs nothing but a tidy quantity.
enum IngredientParser {
    static func parse(_ raw: String) -> Ingredient {
        let original = raw.collapsed
        var text = original
        guard !text.isEmpty else { return Ingredient(text: "", name: "") }

        // Bullets and dashes at the start of a line, but never digits.
        while let first = text.first, "-–—•*·▢◻☐□".contains(first) {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespaces)
        }

        // Headings: "For the sauce:" or a short line ending in a colon.
        if text.hasSuffix(":") && text.split(separator: " ").count <= 6 && leadingNumber(in: text) == nil {
            let title = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
            return Ingredient.heading(title)
        }
        let lowerText = text.lowercased()
        if lowerText.hasPrefix("for the ") && text.split(separator: " ").count <= 6 && !lowerText.contains(",") && leadingNumber(in: text) == nil {
            return Ingredient.heading(text)
        }

        var isOptional = false
        if let range = text.range(of: #"\s*[\(\[]?\s*optional\s*[\)\]]?\s*$"#, options: [.regularExpression, .caseInsensitive]) {
            isOptional = true
            text.removeSubrange(range)
            text = text.trimmingCharacters(in: .whitespaces)
            if text.hasSuffix(",") { text.removeLast() }
        } else if text.range(of: #"\boptional\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            isOptional = true
        }

        text = Fractions.expandVulgar(text)

        var quantity: Double?
        var quantityMax: Double?
        var rest = text

        if let found = leadingRange(in: text) {
            quantity = found.0
            quantityMax = found.1
            rest = found.2
        } else if let found = leadingWordNumber(in: text) {
            quantity = found.0
            rest = found.1
        }

        var unit: String?
        var packageNote: String?

        // "(14 oz)" or "14-ounce" before a container word.
        if let size = packageSize(in: rest) {
            packageNote = size.0
            rest = size.1
        }

        if let found = leadingUnit(in: rest) {
            unit = found.0.id
            rest = found.1
            if packageNote == nil, let size = packageSize(in: rest) {
                packageNote = size.0
                rest = size.1
            }
        }

        // "cup of sugar" → "sugar"
        if rest.lowercased().hasPrefix("of ") { rest = String(rest.dropFirst(3)) }

        var name = rest
        var prep: String?
        var trailingNotes: [String] = []

        // Parenthetical notes anywhere in the name become prep notes.
        while let open = name.firstIndex(of: "("), let close = name[open...].firstIndex(of: ")") {
            let inner = String(name[name.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            if !inner.isEmpty { trailingNotes.append(inner) }
            name.removeSubrange(open...close)
            name = name.collapsed
        }

        if let comma = name.firstIndex(of: ",") {
            let after = String(name[name.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            name = String(name[..<comma])
            if !after.isEmpty { trailingNotes.insert(after, at: 0) }
        } else if let dash = name.range(of: " - ") ?? name.range(of: " – ") {
            let after = String(name[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
            name = String(name[..<dash.lowerBound])
            if !after.isEmpty { trailingNotes.insert(after, at: 0) }
        }

        // "flour plus more for dusting" → prep gets the tail.
        if let plus = name.range(of: #"\s+(plus|and) (more|extra)\b.*$"#, options: [.regularExpression, .caseInsensitive]) {
            trailingNotes.append(String(name[plus.lowerBound...]).trimmingCharacters(in: .whitespaces))
            name.removeSubrange(plus)
        }

        // Trailing preparation words with no comma: "onion chopped".
        if let range = name.range(of: #"\s+(finely |roughly |coarsely |thinly )?(chopped|minced|diced|sliced|grated|shredded|crushed|melted|softened|beaten|divided|drained|rinsed|peeled|cubed|halved|quartered|julienned|zested|juiced|toasted|crumbled|sifted|packed)\s*$"#, options: [.regularExpression, .caseInsensitive]) {
            trailingNotes.insert(String(name[range]).trimmingCharacters(in: .whitespaces), at: 0)
            name.removeSubrange(range)
        }

        if let packageNote { trailingNotes.insert(packageNote, at: 0) }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " .;:"))
        if name.isEmpty { name = original }
        if !trailingNotes.isEmpty { prep = trailingNotes.joined(separator: ", ") }

        return Ingredient(
            text: original,
            quantity: quantity,
            quantityMax: quantityMax,
            unit: unit,
            name: name,
            prep: prep,
            isOptional: isOptional
        )
    }

    // MARK: Pieces

    private static let numberPattern = #"\d+\s+\d+/\d+|\d+/\d+|\d+(?:[.,]\d+)?"#

    private static let rangeRegex = try! NSRegularExpression(
        pattern: "^(" + numberPattern + #")(?:\s*(?:-|–|—|to|or)\s*("# + numberPattern + #"))?(?=\s|$|[a-zA-Z(])\s*(.*)$"#,
        options: []
    )

    static func leadingNumber(in text: String) -> Double? {
        leadingRange(in: Fractions.expandVulgar(text))?.0
    }

    /// (low, high, remainder) for "2-3 cups sugar".
    static func leadingRange(in text: String) -> (Double, Double?, String)? {
        let ns = text as NSString
        guard let match = rangeRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard let low = Fractions.parse(ns.substring(with: match.range(at: 1))) else { return nil }
        var high: Double?
        if match.range(at: 2).location != NSNotFound {
            high = Fractions.parse(ns.substring(with: match.range(at: 2)))
            if let h = high, h <= low { high = nil }
        }
        let remainder = ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
        return (low, high, remainder)
    }

    private static let wordNumbers: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "half": 0.5, "quarter": 0.25, "dozen": 12,
    ]

    /// "two eggs", "half a cup", "a pinch of salt", "a dozen".
    private static func leadingWordNumber(in text: String) -> (Double, String)? {
        let words = text.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true).map(String.init)
        guard let first = words.first?.lowercased() else { return nil }
        var value: Double?
        var consumed = 1
        if let v = wordNumbers[first] {
            value = v
            if (first == "half" || first == "quarter"), words.count > 1, ["a", "an", "of"].contains(words[1].lowercased()) {
                consumed = 2
                if first == "quarter", words.count > 2, words[2].lowercased() == "of" { consumed = 3 }
            }
        } else if first == "a" || first == "an" {
            guard words.count > 1 else { return nil }
            let next = words[1].lowercased()
            if next == "dozen" {
                return (12, words.dropFirst(2).joined(separator: " "))
            }
            if next == "few" || next == "couple" { return nil }
            guard Units.canonical(words[1]) != nil else { return nil }
            value = 1
        }
        guard let value else { return nil }
        let remainder = words.dropFirst(consumed).joined(separator: " ")
        return (value, remainder)
    }

    private static let sizeRegex = try! NSRegularExpression(
        pattern: #"^\(?\s*(\d+(?:[.,]\d+)?(?:\s*(?:-|–|to)\s*\d+(?:[.,]\d+)?)?)\s*-?\s*(oz|ounce|ounces|ounces?|g|gram|grams|ml|lb|lbs|pound|pounds|inch|inches|in|cm|liter|litre|l|fl oz|fl\. oz|quart|qt|pint|pt)\.?\s*\)?\s+(?=(can|cans|package|packages|pkg|jar|jars|bag|bags|box|boxes|container|containers|bottle|bottles|carton|cartons|tin|tins|packet|packets|block|blocks|log|logs|tube|tubes|piece|pieces|round|loaf|loaves|pie|skillet|pan|dish|tortillas?|fillets?|steaks?|chops?)\b)"#,
        options: [.caseInsensitive]
    )

    /// "(14 oz) can tomatoes" → ("14 oz", "can tomatoes").
    private static func packageSize(in text: String) -> (String, String)? {
        let ns = text as NSString
        guard let match = sizeRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let amount = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
        let unit = ns.substring(with: match.range(at: 2)).lowercased()
        let remainder = ns.substring(from: match.range.location + match.range.length).trimmingCharacters(in: .whitespaces)
        return ("\(amount) \(unit)", remainder)
    }

    /// The unit at the start of the text, if there is one. Tries two words
    /// first, so "fl oz" and "fluid ounces" are found before "fl" fails.
    private static func leadingUnit(in text: String) -> (UnitInfo, String)? {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return nil }
        if words.count >= 2, let two = Units.canonical(words[0] + " " + words[1]) {
            return (two, words.dropFirst(2).joined(separator: " "))
        }
        var candidate = words[0]
        // "cup(s)" and "tablespoon(s)" appear in typed recipes.
        candidate = candidate.replacingOccurrences(of: "(s)", with: "s")
        if let one = Units.canonical(candidate) {
            // "1 clove garlic" is a unit; "1 can opener" is not a thing we
            // will meet. Refuse a bare unit with nothing after it only when
            // it is a container word, which needs a name to make sense.
            let remainder = words.dropFirst().joined(separator: " ")
            if remainder.isEmpty, one.kind == .count, ["can", "jar", "package", "bag", "box", "bottle"].contains(one.id) {
                return nil
            }
            return (one, remainder)
        }
        // Adjective before a count noun: "2 large eggs" has no unit.
        return nil
    }
}
