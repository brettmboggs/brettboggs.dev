import Foundation

/// Reads a recipe out of plain lines of text: a scanned card, a pasted email,
/// a page with no structured data. Finds the title, the ingredients, the
/// method, and the serving and timing details, and marks whatever it was
/// unsure about for the review screen.
enum TextRecipeParser {
    struct Line {
        var text: String
        var confidence: Float = 1
    }

    static func parse(text: String, kind: RecipeSource.Kind = .written) -> RecipeDraft {
        let lines = text.components(separatedBy: .newlines).map { Line(text: $0) }
        return parse(lines: lines, kind: kind)
    }

    static func parse(lines rawLines: [Line], kind: RecipeSource.Kind = .scanned) -> RecipeDraft {
        var lines: [Line] = rawLines.compactMap { line in
            let cleaned = fixOCR(line.text).collapsed
            guard !cleaned.isEmpty else { return nil }
            return Line(text: cleaned, confidence: line.confidence)
        }
        // "Ingredients: 2 cups flour" on one line becomes two.
        lines = lines.flatMap(splitInlineMarker)

        var recipe = Recipe()
        recipe.source = RecipeSource(kind: kind)
        var draft = RecipeDraft(recipe: recipe)
        draft.rawText = lines.map(\.text).joined(separator: "\n")
        guard !lines.isEmpty else {
            draft.warnings.append("No text was found.")
            return draft
        }

        // Pull the meta lines (serves, times) out first, wherever they are.
        var servings: Int?
        var yieldText: String?
        var prep: Int?
        var cook: Int?
        var total: Int?
        var ovenLine: String?
        var body: [Line] = []
        for line in lines {
            if let info = servingsInfo(in: line.text), isMetaOnly(line.text) {
                if servings == nil { servings = info.0 }
                if yieldText == nil { yieldText = info.1 }
                continue
            }
            if let times = timesInfo(in: line.text), isMetaOnly(line.text) {
                if let p = times.prep { prep = prep ?? p }
                if let c = times.cook { cook = cook ?? c }
                if let t = times.total { total = total ?? t }
                continue
            }
            if ovenLine == nil, let oven = ovenOnly(in: line.text) {
                ovenLine = oven
                continue
            }
            body.append(line)
        }

        // Section markers.
        let ingredientsIndex = body.firstIndex { marker(for: $0.text) == .ingredients }
        let directionsIndex = body.firstIndex { marker(for: $0.text) == .directions }
        let notesIndex = body.firstIndex { marker(for: $0.text) == .notes }

        var titleRegion: [Line] = []
        var ingredientRegion: [Line] = []
        var stepRegion: [Line] = []
        var notesRegion: [Line] = []

        if ingredientsIndex != nil || directionsIndex != nil {
            let firstMarker = [ingredientsIndex, directionsIndex, notesIndex].compactMap { $0 }.min() ?? 0
            titleRegion = Array(body[..<firstMarker])
            if let i = ingredientsIndex {
                let end = [directionsIndex, notesIndex].compactMap { $0 }.filter { $0 > i }.min() ?? body.count
                ingredientRegion = Array(body[(i + 1)..<end])
            }
            if let d = directionsIndex {
                let end = [notesIndex].compactMap { $0 }.filter { $0 > d }.min() ?? body.count
                stepRegion = Array(body[(d + 1)..<end])
                if ingredientsIndex == nil {
                    // Everything before the method that reads like an ingredient is one.
                    let before = titleRegion
                    titleRegion = []
                    var seenIngredient = false
                    for line in before {
                        if looksLikeIngredient(line.text) { seenIngredient = true; ingredientRegion.append(line) }
                        else if seenIngredient && isHeadingLike(line.text) { ingredientRegion.append(line) }
                        else if !seenIngredient { titleRegion.append(line) }
                        else { ingredientRegion.append(line) }
                    }
                }
            } else if let i = ingredientsIndex {
                // Ingredients marked but no method marker: the method starts at
                // the first line that reads like one.
                let after = Array(body[(i + 1)..<(notesIndex ?? body.count)])
                var split = after.count
                for (offset, line) in after.enumerated() where offset > 0 {
                    if looksLikeStep(line.text) && !looksLikeIngredient(line.text) {
                        split = offset
                        break
                    }
                }
                ingredientRegion = Array(after[..<split])
                stepRegion = Array(after[split...])
            }
            if let n = notesIndex {
                notesRegion = Array(body[(n + 1)...])
            }
        } else {
            // No markers: read the shape of the text.
            var index = 0
            var titleLines: [Line] = []
            // Title and headnote: everything before the first run of ingredients.
            var firstIngredient: Int?
            for (offset, line) in body.enumerated() {
                if looksLikeIngredient(line.text) && !looksLikeStep(line.text) {
                    let nextIsIngredient = offset + 1 < body.count && looksLikeIngredient(body[offset + 1].text)
                    if nextIsIngredient || body.count <= 3 {
                        firstIngredient = offset
                        break
                    }
                }
            }
            if let first = firstIngredient {
                titleLines = Array(body[..<first])
                index = first
                var misses = 0
                while index < body.count {
                    let line = body[index]
                    if looksLikeIngredient(line.text) && !looksLikeStep(line.text) {
                        ingredientRegion.append(line)
                        misses = 0
                    } else if isHeadingLike(line.text) && index + 1 < body.count && looksLikeIngredient(body[index + 1].text) {
                        ingredientRegion.append(line)
                    } else {
                        misses += 1
                        if looksLikeStep(line.text) || misses > 1 { break }
                        ingredientRegion.append(line)
                    }
                    index += 1
                }
                // A line that failed both tests right before the method is
                // more likely the first step than an ingredient.
                if misses > 0, let last = ingredientRegion.last, !looksLikeIngredient(last.text) {
                    ingredientRegion.removeLast()
                    index -= 1
                }
                stepRegion = Array(body[index...])
            } else {
                // Nothing looked like an ingredient: title, then method.
                titleLines = Array(body.prefix(1))
                stepRegion = Array(body.dropFirst())
            }
            titleRegion = titleLines
        }

        // Title and headnote.
        var titleCandidates = titleRegion.filter { !isMetaOnly($0.text) && marker(for: $0.text) == nil }
        if let index = titleCandidates.firstIndex(where: { isTitleLike($0.text) }) {
            draft.recipe.title = tidyTitle(titleCandidates[index].text)
            titleCandidates.remove(at: index)
        } else if let first = titleCandidates.first, first.text.count <= 90 {
            draft.recipe.title = tidyTitle(first.text)
            titleCandidates.removeFirst()
        }
        let headnote = titleCandidates.map(\.text).joined(separator: " ")
        if !headnote.isEmpty {
            if headnote.count <= 400 && !looksLikeIngredient(headnote) {
                draft.recipe.headnote = headnote
            } else {
                // Long preamble that is probably body text that came adrift.
                stepRegion.insert(contentsOf: titleCandidates, at: 0)
            }
        }

        // Ingredients.
        for line in ingredientRegion {
            if marker(for: line.text) != nil { continue }
            if isHeadingLike(line.text) && !looksLikeIngredient(line.text) {
                draft.recipe.ingredients.append(Ingredient.heading(line.text.trimmingCharacters(in: CharacterSet(charactersIn: ":"))))
                continue
            }
            var ingredient = IngredientParser.parse(line.text)
            if ingredient.isHeading {
                draft.recipe.ingredients.append(ingredient)
                continue
            }
            ingredient.text = line.text
            let unsure = line.confidence < 0.55
                || (ingredient.quantity == nil && ingredient.unit == nil && IngredientCatalog.entry(for: ingredient.key) == nil && line.text.split(separator: " ").count > 4)
                || line.text.count > 110
            if unsure { draft.flaggedIngredientIDs.insert(ingredient.id) }
            draft.recipe.ingredients.append(ingredient)
        }

        // Steps.
        let merged = mergeWrappedLines(stepRegion)
        var stepTexts: [(String, Float)] = []
        for (text, confidence) in merged {
            let stripped = stripStepNumber(text)
            if isHeadingLike(stripped) && !looksLikeStep(stripped) {
                stepTexts.append((stripped + ":", confidence))
                continue
            }
            if stripped.count > 420 {
                for piece in splitIntoSteps(stripped) { stepTexts.append((piece, confidence)) }
            } else {
                stepTexts.append((stripped, confidence))
            }
        }
        if stepTexts.count == 1, stepTexts[0].0.count > 220 {
            let only = stepTexts[0]
            stepTexts = splitIntoSteps(only.0).map { ($0, only.1) }
        }
        for (text, confidence) in stepTexts {
            if text.hasSuffix(":") && text.split(separator: " ").count <= 6 {
                draft.recipe.steps.append(Step(text: String(text.dropLast()), isHeading: true))
                continue
            }
            let step = Step(text: text)
            if confidence < 0.55 { draft.flaggedStepIDs.insert(step.id) }
            draft.recipe.steps.append(step)
        }

        if let ovenLine, !draft.recipe.steps.contains(where: { $0.text.lowercased().contains("preheat") }) {
            draft.recipe.steps.insert(Step(text: "Preheat the oven to \(ovenLine)."), at: 0)
        }

        // Notes.
        let notes = mergeWrappedLines(notesRegion).map(\.0).joined(separator: "\n")
        if !notes.isEmpty { draft.recipe.notes = notes }

        draft.recipe.servings = servings
        draft.recipe.yieldText = yieldText
        draft.recipe.prepMinutes = prep
        draft.recipe.cookMinutes = cook
        if let total, total != (prep ?? 0) + (cook ?? 0) {
            if prep == nil && cook == nil {
                draft.recipe.cookMinutes = total
            } else {
                draft.recipe.totalMinutesOverride = total
            }
        }

        if draft.recipe.title.isEmpty { draft.warnings.append("No title was found. Give it one.") }
        if draft.recipe.realIngredients.isEmpty { draft.warnings.append("No ingredients were found.") }
        if draft.recipe.realSteps.isEmpty { draft.warnings.append("No steps were found.") }
        return draft
    }

    // MARK: - Markers

    enum Marker { case ingredients, directions, notes }

    private static let ingredientsMarker = try! NSRegularExpression(pattern: #"^\W*(ingredients?|what you need|what you'll need|you will need|you'll need|shopping list|for the [a-z ]+)\W*$"#, options: [.caseInsensitive])
    private static let directionsMarker = try! NSRegularExpression(pattern: #"^\W*(directions?|instructions?|method|preparation|steps?|how to make it|how to make|procedure|to prepare|to make|assembly|cooking instructions|what to do|to cook|process)\W*$"#, options: [.caseInsensitive])
    private static let notesMarker = try! NSRegularExpression(pattern: #"^\W*(notes?|tips?|cook'?s notes?|chef'?s notes?|recipe notes?|variations?|storage|to store|make ahead|serving suggestions?)\W*$"#, options: [.caseInsensitive])

    static func marker(for text: String) -> Marker? {
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard text.count <= 40 else { return nil }
        if directionsMarker.firstMatch(in: text, range: range) != nil { return .directions }
        if notesMarker.firstMatch(in: text, range: range) != nil { return .notes }
        if ingredientsMarker.firstMatch(in: text, range: range) != nil {
            // "For the sauce" inside an ingredient list is a heading, not the
            // start of the list; only the plain word counts as the marker.
            if text.lowercased().hasPrefix("for the") { return nil }
            return .ingredients
        }
        return nil
    }

    private static func splitInlineMarker(_ line: Line) -> [Line] {
        let text = line.text
        guard let colon = text.firstIndex(of: ":"), text.distance(from: text.startIndex, to: colon) <= 20 else { return [line] }
        let head = String(text[..<colon])
        let tail = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        guard !tail.isEmpty, marker(for: head) != nil else { return [line] }
        return [Line(text: head, confidence: line.confidence), Line(text: tail, confidence: line.confidence)]
    }

    // MARK: - Meta

    private static let servingsRegex = try! NSRegularExpression(pattern: #"\b(serves|servings?|serving size|yields?|makes|portions?|feeds)\b\s*:?\s*(?:about|approximately|approx\.?)?\s*(\d+)(?:\s*(?:-|–|to)\s*(\d+))?\s*([a-zA-Z][a-zA-Z0-9\- ]*)?"#, options: [.caseInsensitive])
    private static let servingsLeadingRegex = try! NSRegularExpression(pattern: #"^\W*(\d+)(?:\s*(?:-|–|to)\s*(\d+))?\s*(servings?|portions?|people|dozen [a-z]+|cookies|muffins|bars|slices|pancakes|rolls|biscuits|cupcakes|pieces|squares|loaves|loaf|cups|quarts|pints)\b\W*$"#, options: [.caseInsensitive])

    /// (count, yield text) from "Serves 4", "Makes 24 cookies", "6 servings".
    static func servingsInfo(in text: String) -> (Int?, String?)? {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        if let match = servingsRegex.firstMatch(in: text, range: range) {
            let word = ns.substring(with: match.range(at: 1)).lowercased()
            let count = Int(ns.substring(with: match.range(at: 2)))
            var tail = match.range(at: 4).location != NSNotFound ? ns.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces) : ""
            tail = tail.trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
            if word.hasPrefix("serv") || word.hasPrefix("feed") || word.hasPrefix("portion") {
                return (count, nil)
            }
            let ignored = ["servings", "serving", "people", "portions"]
            if !tail.isEmpty && !ignored.contains(tail.lowercased()) && tail.split(separator: " ").count <= 4 {
                return (count, "\(count.map { String($0) } ?? "") \(tail)")
            }
            return (count, nil)
        }
        if let match = servingsLeadingRegex.firstMatch(in: text, range: range) {
            let count = Int(ns.substring(with: match.range(at: 1)))
            let unit = ns.substring(with: match.range(at: 3)).lowercased()
            if unit.hasPrefix("serv") || unit.hasPrefix("portion") || unit == "people" { return (count, nil) }
            return (count, "\(count.map { String($0) } ?? "") \(unit)")
        }
        return nil
    }

    private static let timeRegex = try! NSRegularExpression(pattern: #"\b(prep(?:aration)?|cook(?:ing)?|total|bake|baking|ready in|active|hands[- ]on|inactive|chill(?:ing)?|rest(?:ing)?|rise|rising|marinat(?:e|ing)|freez(?:e|ing)|cool(?:ing)?)\s*(?:time)?\s*:?\s*((?:(?:about |approximately |approx\.? )?(?:\d+(?:[.,]\d+)?|\d+ \d/\d|\d/\d|[½¼¾⅓⅔]|an?|one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty|forty|forty[- ]five|fifty|sixty|ninety|half an|half)\s*(?:hours?|hrs?|h\b|minutes?|mins?|m\b)\s*(?:and\s*|,\s*)?)+)"#, options: [.caseInsensitive])

    struct Times {
        var prep: Int?
        var cook: Int?
        var total: Int?
    }

    static func timesInfo(in text: String) -> Times? {
        let ns = text as NSString
        let matches = timeRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }
        var times = Times()
        for match in matches {
            let label = ns.substring(with: match.range(at: 1)).lowercased()
            guard let value = minutes(from: ns.substring(with: match.range(at: 2))) else { continue }
            if label.hasPrefix("prep") || label.hasPrefix("active") || label.hasPrefix("hands") {
                times.prep = (times.prep ?? 0) + value
            } else if label.hasPrefix("cook") || label.hasPrefix("bak") {
                times.cook = (times.cook ?? 0) + value
            } else if label.hasPrefix("total") || label.hasPrefix("ready") {
                times.total = value
            } else {
                // Chill, rest, rise: counted into the cooking side of total.
                times.cook = (times.cook ?? 0) + value
            }
        }
        return (times.prep == nil && times.cook == nil && times.total == nil) ? nil : times
    }

    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40,
        "forty-five": 45, "forty five": 45, "fifty": 50, "sixty": 60, "ninety": 90, "half": 0.5, "half an": 0.5,
    ]

    private static let durationRegex = try! NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?(?:\s+\d/\d)?|\d/\d|[½¼¾⅓⅔]|half an|half|an?|one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty|forty[- ]five|forty|fifty|sixty|ninety)\s*(?:(?:-|–|to)\s*(\d+(?:[.,]\d+)?))?\s*(hours?|hrs?|h\b|minutes?|mins?|m\b|seconds?|secs?)"#, options: [.caseInsensitive])

    /// "1 hour 30 minutes" → 90, "45 mins" → 45, "1½ hours" → 90.
    static func minutes(from text: String) -> Int? {
        let ns = text as NSString
        var total = 0.0
        var found = false
        for match in durationRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let numberText = ns.substring(with: match.range(at: 1)).lowercased()
            let unit = ns.substring(with: match.range(at: 3)).lowercased()
            let value = numberWords[numberText] ?? Fractions.parse(numberText)
            guard let value else { continue }
            found = true
            if unit.hasPrefix("h") { total += value * 60 }
            else if unit.hasPrefix("s") { total += value / 60 }
            else { total += value }
        }
        guard found, total > 0 else { return nil }
        return Int(total.rounded())
    }

    private static let ovenRegex = try! NSRegularExpression(pattern: #"^\W*(?:oven|bake at|oven temp(?:erature)?|temperature)\W*:?\W*(\d{3})\s*(?:°|º|degrees?)?\s*([FC])?\W*$"#, options: [.caseInsensitive])

    /// "Oven: 350°" as a line on its own.
    static func ovenOnly(in text: String) -> String? {
        let ns = text as NSString
        guard let match = ovenRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let degrees = ns.substring(with: match.range(at: 1))
        let scale = match.range(at: 2).location != NSNotFound ? ns.substring(with: match.range(at: 2)).uppercased() : "F"
        return "\(degrees)°\(scale)"
    }

    /// A line that carries only serving or timing information.
    static func isMetaOnly(_ text: String) -> Bool {
        let words = text.split(separator: " ").count
        guard words <= 14 else { return false }
        var stripped = text
        stripped = servingsRegex.stringByReplacingMatches(in: stripped, range: NSRange(location: 0, length: (stripped as NSString).length), withTemplate: " ")
        stripped = servingsLeadingRegex.stringByReplacingMatches(in: stripped, range: NSRange(location: 0, length: (stripped as NSString).length), withTemplate: " ")
        stripped = timeRegex.stringByReplacingMatches(in: stripped, range: NSRange(location: 0, length: (stripped as NSString).length), withTemplate: " ")
        let leftover = stripped.collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " ·|•-–,;:."))
        let leftoverWords = leftover.split(separator: " ").filter { $0.count > 2 }
        return leftoverWords.count <= 2 && !looksLikeStep(text)
    }

    // MARK: - Shape

    private static let cookingVerbs: Set<String> = [
        "preheat", "mix", "stir", "bake", "add", "combine", "whisk", "pour", "heat", "cook", "simmer",
        "boil", "fold", "beat", "cream", "chop", "serve", "cool", "let", "remove", "drain", "sprinkle",
        "spread", "roll", "cut", "place", "cover", "refrigerate", "chill", "knead", "sauté", "saute",
        "fry", "grill", "roast", "season", "toss", "melt", "bring", "reduce", "transfer", "arrange",
        "brush", "grease", "line", "set", "allow", "return", "continue", "repeat", "top", "garnish",
        "slice", "dice", "mince", "blend", "process", "puree", "purée", "strain", "rinse", "pat",
        "coat", "dredge", "dip", "flip", "turn", "lower", "raise", "increase", "taste", "adjust",
        "divide", "shape", "form", "press", "spoon", "ladle", "scoop", "drizzle", "dust", "sift",
        "soak", "marinate", "rub", "wrap", "seal", "freeze", "thaw", "warm", "reheat", "toast",
        "broil", "steam", "poach", "sear", "brown", "caramelize", "deglaze", "scrape", "stuff", "fill",
        "layer", "assemble", "crumble", "mash", "whip", "scatter", "squeeze", "microwave", "uncover",
        "discard", "reserve", "meanwhile", "using", "working", "once", "when", "while", "gently",
        "carefully", "immediately", "then", "finally", "next", "first", "before", "after", "enjoy",
    ]

    static func looksLikeStep(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
        guard words.count >= 4 else { return false }
        if text.range(of: #"^\d+[.)]\s+[A-Za-z]"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"^step\s*\d+"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        let verbHits = words.prefix(6).filter { cookingVerbs.contains($0) }.count
        if verbHits > 0 && words.count >= 5 { return true }
        if words.count >= 12 && (text.contains(". ") || text.hasSuffix(".")) { return true }
        return false
    }

    private static let ingredientStarts = try! NSRegularExpression(pattern: #"^(a pinch|pinch|a dash|dash|a handful|handful|a splash|splash|juice of|zest of|salt|pepper|salt and pepper|freshly ground|a few|a couple|some|several|one|two|three|four|five|six|half|quarter|a can|a jar|a package|a stick|a clove|a cup|a tablespoon|a teaspoon|\d)"#, options: [.caseInsensitive])

    static func looksLikeIngredient(_ text: String) -> Bool {
        let expanded = Fractions.expandVulgar(text)
        let words = expanded.split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 20 else { return false }
        // "1. Preheat the oven" is a numbered step, not an ingredient.
        if expanded.range(of: #"^\d+[.)]\s+[A-Za-z]"#, options: .regularExpression) != nil {
            let rest = expanded.replacingOccurrences(of: #"^\d+[.)]\s+"#, with: "", options: .regularExpression)
            return looksLikeIngredient(rest) && !looksLikeStep(rest)
        }
        if IngredientParser.leadingRange(in: expanded) != nil {
            // A number at the start, and not a long sentence.
            if words.count > 14 && looksLikeStep(text) { return false }
            return true
        }
        let ns = expanded as NSString
        if ingredientStarts.firstMatch(in: expanded, range: NSRange(location: 0, length: ns.length)) != nil {
            return !looksLikeStep(text) || words.count <= 8
        }
        if words.count <= 9 && words.contains(where: { Units.canonical($0) != nil }) && !looksLikeStep(text) {
            return true
        }
        if words.count <= 5 {
            let key = IngredientKey.make(text)
            if IngredientCatalog.entry(for: key) != nil { return true }
        }
        return false
    }

    /// "For the topping", "Sauce", "Crust:".
    static func isHeadingLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        let words = trimmed.split(separator: " ")
        guard words.count >= 1, words.count <= 5, trimmed.count <= 40 else { return false }
        if text.hasSuffix(":") { return true }
        if IngredientParser.leadingNumber(in: trimmed) != nil { return false }
        if trimmed.lowercased().hasPrefix("for the ") { return true }
        let allCaps = trimmed == trimmed.uppercased() && trimmed.rangeOfCharacter(from: .letters) != nil
        let titleCase = words.allSatisfy { $0.first?.isUppercase == true || $0.count <= 3 }
        if (allCaps || titleCase) && !looksLikeIngredient(trimmed) && !trimmed.hasSuffix(".") {
            return words.count <= 4
        }
        return false
    }

    static func isTitleLike(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard words.count <= 12, text.count <= 80 else { return false }
        if looksLikeIngredient(text) || looksLikeStep(text) { return false }
        if text.hasSuffix(".") && words.count > 6 { return false }
        let letters = text.filter(\.isLetter)
        guard letters.count >= 3 else { return false }
        let allCaps = text == text.uppercased()
        let capitalisedWords = words.filter { $0.first?.isUppercase == true }.count
        return allCaps || capitalisedWords >= max(1, words.count / 2)
    }

    static func tidyTitle(_ text: String) -> String {
        var title = text.trimmingCharacters(in: CharacterSet(charactersIn: " :.-–—*"))
        title = title.replacingOccurrences(of: #"^recipe (for|of)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(of: #"\s+recipe$"#, with: "", options: [.regularExpression, .caseInsensitive])
        if title == title.uppercased() && title.count > 3 {
            title = title.capitalized
            for small in [" And ", " Of ", " The ", " With ", " In ", " For ", " A ", " On ", " To "] {
                title = title.replacingOccurrences(of: small, with: small.lowercased())
            }
        }
        return title
    }

    static func stripStepNumber(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: #"^\s*(?:step\s*)?\d{1,2}\s*[.):\-–]\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"^\s*step\s*\d{1,2}\s*:?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"^\s*[•\-–*▢]\s+"#, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Lines that are one sentence broken across a card get put back together.
    private static func mergeWrappedLines(_ lines: [Line]) -> [(String, Float)] {
        var out: [(String, Float)] = []
        for line in lines {
            let text = line.text
            if let last = out.last, shouldJoin(last.0, next: text) {
                out[out.count - 1] = (last.0 + " " + text, min(last.1, line.confidence))
            } else {
                out.append((text, line.confidence))
            }
        }
        return out
    }

    private static func shouldJoin(_ previous: String, next: String) -> Bool {
        guard let lastChar = previous.last, let firstChar = next.first else { return false }
        if next.range(of: #"^(?:step\s*)?\d{1,2}[.):]\s"#, options: [.regularExpression, .caseInsensitive]) != nil { return false }
        if isHeadingLike(next) || marker(for: next) != nil { return false }
        if ".!?:".contains(lastChar) { return false }
        if firstChar.isLowercase { return true }
        if ",;".contains(lastChar) { return true }
        let tail = previous.split(separator: " ").last.map(String.init)?.lowercased() ?? ""
        if ["and", "or", "the", "a", "an", "to", "of", "in", "with", "until", "for", "into", "on", "at", "then", "over"].contains(tail) { return true }
        return false
    }

    /// One long paragraph into steps, one or two sentences each.
    static func splitIntoSteps(_ paragraph: String) -> [String] {
        let sentences = self.sentences(in: paragraph)
        guard sentences.count > 1 else { return [paragraph] }
        var steps: [String] = []
        for sentence in sentences {
            if let last = steps.last, last.count < 45 || sentence.count < 30 {
                steps[steps.count - 1] = last + " " + sentence
            } else {
                steps.append(sentence)
            }
        }
        return steps
    }

    private static let sentenceEnd = try! NSRegularExpression(pattern: #"(?<=[.!?])["”’)]?\s+(?=[A-Z0-9"“(])"#)

    static func sentences(in text: String) -> [String] {
        let ns = text as NSString
        var pieces: [String] = []
        var start = 0
        for match in sentenceEnd.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let end = match.range.location
            let piece = ns.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespaces)
            if !piece.isEmpty { pieces.append(piece) }
            start = match.range.location + match.range.length
        }
        let tail = ns.substring(from: start).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { pieces.append(tail) }
        return pieces
    }

    // MARK: - OCR repairs

    /// The handful of misreads that show up on every scanned card.
    static func fixOCR(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "’", with: "'")
        s = s.replacingOccurrences(of: "‘", with: "'")
        s = s.replacingOccurrences(of: "º", with: "°")
        s = s.replacingOccurrences(of: "˚", with: "°")
        s = s.replacingOccurrences(of: "\u{00AD}", with: "")
        // "l/2", "I/2", "1 /2" → "1/2"
        s = s.replacingOccurrences(of: #"\b[lI]/(\d)"#, with: "1/$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d)\s+/\s*(\d)"#, with: "$1/$2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d)/\s+(\d)"#, with: "$1/$2", options: .regularExpression)
        // "35O°" → "350°", "1O minutes" → "10 minutes"
        s = s.replacingOccurrences(of: #"(?<=\d)[Oo](?=\d|\s*°|\s*degrees|\s*min|\s*sec)"#, with: "0", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<=\d)[Oo](?=\d)"#, with: "0", options: .regularExpression)
        // A lone "l" or "I" before a unit is a 1.
        s = s.replacingOccurrences(of: #"^[lI](?=\s+(?:cup|c\.|tsp|tbsp|t\.|T\.|teaspoon|tablespoon|lb|oz|egg|can|clove|stick|pound|ounce|pkg|package|quart|pint|small|large|medium|whole))"#, with: "1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^[lI](?=\s*[/.]\d)"#, with: "1", options: .regularExpression)
        // "1/2c" → "1/2 c", "2T" stays for the unit parser.
        s = s.replacingOccurrences(of: #"(\d)(cups?|tsp|tbsp|teaspoons?|tablespoons?|oz|lbs?)\b"#, with: "$1 $2", options: [.regularExpression, .caseInsensitive])
        return s
    }
}
