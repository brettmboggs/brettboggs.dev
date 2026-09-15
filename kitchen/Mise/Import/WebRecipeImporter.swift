import Foundation
import UIKit

enum WebImportError: LocalizedError {
    case badURL
    case network(String)
    case blocked(Int)
    case notHTML
    case noRecipe

    var errorDescription: String? {
        switch self {
        case .badURL: return "That does not look like a web address."
        case .network(let detail): return "Could not reach the page. \(detail)"
        case .blocked(let code): return "That site would not let the page be read (\(code)). Copy the recipe text from Safari and paste it instead."
        case .notHTML: return "That link is not a web page."
        case .noRecipe: return "No recipe was found on that page. Copy the text and paste it instead."
        }
    }
}

/// Pulls a recipe off a web page.
///
/// Nearly every recipe site publishes schema.org Recipe data as JSON-LD for
/// search engines, and that is the clean path: exact ingredients, exact
/// steps, times, yield, a photo. When a page lacks it there is a microdata
/// pass, then the plain-text parser over the page's visible words.
enum WebRecipeImporter {
    static func importRecipe(from rawURL: URL) async throws -> RecipeDraft {
        guard var url = normalize(rawURL) else { throw WebImportError.badURL }
        if url.scheme == "http", var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.scheme = "https"
            url = comps.url ?? url
        }
        let html = try await fetchHTML(url)
        guard var draft = draft(fromHTML: html, url: url) else { throw WebImportError.noRecipe }
        if let imageURL = imageURL(in: html, url: url) ?? draftImageURL(draft) {
            draft.photo = await fetchImage(imageURL)
        }
        return draft
    }

    static func normalize(_ url: URL) -> URL? {
        var text = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let fixed = URL(string: text), let host = fixed.host(), host.contains(".") else { return nil }
        return fixed
    }

    static func url(fromText text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else {
            // Find the first link inside a longer message.
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
               let match = detector.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
               let found = match.url {
                return normalize(found)
            }
            return nil
        }
        return URL(string: trimmed).flatMap(normalize)
    }

    // MARK: - Network

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static func fetchHTML(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WebImportError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 403 || http.statusCode == 429 || http.statusCode == 401 {
                throw WebImportError.blocked(http.statusCode)
            }
            if http.statusCode >= 400 {
                throw WebImportError.network("The page answered with error \(http.statusCode).")
            }
            if let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
               !type.contains("html"), !type.contains("xml"), !type.contains("text") {
                throw WebImportError.notHTML
            }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .windowsCP1252) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw WebImportError.notHTML
    }

    static func fetchImage(_ url: URL) async -> UIImage? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request), data.count < 20_000_000 else { return nil }
        return UIImage(data: data)?.scaledDown(to: 1600)
    }

    // MARK: - Page → draft

    static func draft(fromHTML html: String, url: URL) -> RecipeDraft? {
        let siteName = HTML.meta("og:site_name", in: html)
        if let object = jsonLDRecipes(in: html).first, var draft = draft(fromJSONLD: object, url: url) {
            if draft.recipe.source.name == nil { draft.recipe.source.name = siteName }
            return draft
        }
        if var draft = draft(fromMicrodata: html, url: url) {
            if draft.recipe.source.name == nil { draft.recipe.source.name = siteName }
            return draft
        }
        // Plain text: the page's visible lines through the text parser.
        let lines = HTML.textLines(from: html)
        guard lines.count > 5 else { return nil }
        var draft = TextRecipeParser.parse(lines: lines.map { TextRecipeParser.Line(text: $0) }, kind: .web)
        guard draft.recipe.realIngredients.count >= 2, !draft.recipe.realSteps.isEmpty else { return nil }
        if draft.recipe.title.isEmpty || draft.recipe.title.count < 3 {
            draft.recipe.title = pageTitle(in: html) ?? draft.recipe.title
        } else if let page = pageTitle(in: html), page.lowercased().contains(draft.recipe.title.lowercased()) == false, draft.recipe.title.count > 60 {
            draft.recipe.title = page
        }
        draft.recipe.source = RecipeSource(kind: .web, name: siteName, url: url)
        draft.warnings.insert("This page had no recipe data, so the words were read the way a scan is. Check it over.", at: 0)
        draft.recipe.needsReview = true
        return draft
    }

    private static func pageTitle(in html: String) -> String? {
        let raw = HTML.meta("og:title", in: html) ?? HTML.title(in: html)
        guard var title = raw else { return nil }
        for separator in [" | ", " - ", " – ", " — ", " • "] {
            if let range = title.range(of: separator) {
                title = String(title[..<range.lowerBound])
            }
        }
        return TextRecipeParser.tidyTitle(title).nilIfBlank
    }

    // MARK: JSON-LD

    private static let ldRegex = try! NSRegularExpression(pattern: #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script\s*>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])

    static func jsonLDRecipes(in html: String) -> [[String: Any]] {
        let ns = html as NSString
        var found: [[String: Any]] = []
        for match in ldRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            var body = ns.substring(with: match.range(at: 1))
            body = body.replacingOccurrences(of: "<!--", with: "").replacingOccurrences(of: "-->", with: "")
            body = body.replacingOccurrences(of: "//<![CDATA[", with: "").replacingOccurrences(of: "//]]>", with: "")
            body = body.replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            var object = parseJSON(body)
            if object == nil {
                // Raw newlines inside strings are the usual breakage.
                let flattened = body.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\t", with: " ")
                object = parseJSON(flattened)
            }
            guard let object else { continue }
            collectRecipes(in: object, depth: 0, into: &found)
        }
        return found
    }

    private static func parseJSON(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func collectRecipes(in any: Any, depth: Int, into found: inout [[String: Any]]) {
        guard depth < 8 else { return }
        if let dict = any as? [String: Any] {
            if isRecipeType(dict["@type"]) {
                found.append(dict)
                return
            }
            for value in dict.values {
                collectRecipes(in: value, depth: depth + 1, into: &found)
            }
        } else if let array = any as? [Any] {
            for value in array {
                collectRecipes(in: value, depth: depth + 1, into: &found)
            }
        }
    }

    private static func isRecipeType(_ any: Any?) -> Bool {
        if let s = any as? String { return s.lowercased().hasSuffix("recipe") }
        if let array = any as? [Any] { return array.contains { isRecipeType($0) } }
        return false
    }

    static func draft(fromJSONLD object: [String: Any], url: URL) -> RecipeDraft? {
        var recipe = Recipe()
        recipe.title = clean(string(object["name"]) ?? string(object["headline"]) ?? "")
        recipe.headnote = clean(string(object["description"]) ?? "")
        if recipe.headnote.count > 600 { recipe.headnote = String(recipe.headnote.prefix(600)) }

        let ingredientLines = strings(object["recipeIngredient"] ?? object["ingredients"])
        recipe.ingredients = ingredientLines.compactMap { line -> Ingredient? in
            let cleaned = clean(line)
            guard !cleaned.isEmpty else { return nil }
            return IngredientParser.parse(cleaned)
        }
        recipe.steps = steps(from: object["recipeInstructions"])

        guard !recipe.title.isEmpty || !recipe.ingredients.isEmpty else { return nil }
        guard !recipe.ingredients.isEmpty || !recipe.steps.isEmpty else { return nil }

        let yield = strings(object["recipeYield"]).first.map(clean)
        if let yield, let info = TextRecipeParser.servingsInfo(in: yield) {
            recipe.servings = info.0
            recipe.yieldText = info.1
        } else if let yield {
            let digits = yield.filter(\.isNumber)
            if let n = Int(digits), n > 0, n < 500 {
                recipe.servings = n
                let words = yield.lowercased()
                if !(words.contains("serving") || words == digits) { recipe.yieldText = yield }
            } else if !yield.isEmpty {
                recipe.yieldText = yield
            }
        }
        if recipe.servings == nil, let count = strings(object["recipeYield"]).compactMap({ Int($0.filter(\.isNumber)) }).first, count > 0 {
            recipe.servings = count
        }

        recipe.prepMinutes = duration(object["prepTime"])
        recipe.cookMinutes = duration(object["cookTime"])
        if let total = duration(object["totalTime"]) {
            let sum = (recipe.prepMinutes ?? 0) + (recipe.cookMinutes ?? 0)
            if sum == 0 { recipe.cookMinutes = total }
            else if total > sum { recipe.totalMinutesOverride = total }
        }

        var tags: [String] = []
        for key in ["recipeCategory", "recipeCuisine", "keywords"] {
            for value in strings(object[key]) {
                for piece in value.split(separator: ",") {
                    let tag = clean(String(piece)).lowercased()
                    if !tag.isEmpty, tag.count <= 24, !tags.contains(tag) { tags.append(tag) }
                }
            }
        }
        recipe.tags = Array(tags.prefix(8))

        var source = RecipeSource(kind: .web, url: url)
        source.author = authorName(object["author"])
        if let publisher = object["publisher"] as? [String: Any], let name = string(publisher["name"]) {
            source.name = clean(name)
        }
        recipe.source = source

        if let nutrition = object["nutrition"] as? [String: Any] {
            var n = Nutrition()
            n.calories = string(nutrition["calories"]).map(clean)
            n.fat = string(nutrition["fatContent"]).map(clean)
            n.carbohydrates = string(nutrition["carbohydrateContent"]).map(clean)
            n.protein = string(nutrition["proteinContent"]).map(clean)
            n.fiber = string(nutrition["fiberContent"]).map(clean)
            n.sugar = string(nutrition["sugarContent"]).map(clean)
            n.sodium = string(nutrition["sodiumContent"]).map(clean)
            if !n.isEmpty { recipe.nutrition = n }
        }

        var draft = RecipeDraft(recipe: recipe)
        draft.rawText = ingredientLines.joined(separator: "\n")
        if let image = imageURL(fromJSONLD: object["image"], base: url) {
            draft.recipe.notes = ""
            pendingImage[draft.recipe.id] = image
        }
        if recipe.title.isEmpty { draft.warnings.append("The page did not name the recipe.") }
        if recipe.ingredients.isEmpty { draft.warnings.append("No ingredients were listed on the page.") }
        if recipe.steps.isEmpty { draft.warnings.append("No steps were listed on the page.") }
        return draft
    }

    /// Image URLs found in the structured data, keyed by the draft's recipe id
    /// until the caller fetches them.
    private static var pendingImage: [UUID: URL] = [:]

    private static func draftImageURL(_ draft: RecipeDraft) -> URL? {
        let url = pendingImage[draft.recipe.id]
        pendingImage[draft.recipe.id] = nil
        return url
    }

    private static func imageURL(in html: String, url: URL) -> URL? {
        guard let og = HTML.meta("og:image", in: html) ?? HTML.meta("twitter:image", in: html) else { return nil }
        return URL(string: og, relativeTo: url)?.absoluteURL
    }

    private static func imageURL(fromJSONLD any: Any?, base: URL) -> URL? {
        guard let any else { return nil }
        if let s = any as? String { return URL(string: s, relativeTo: base)?.absoluteURL }
        if let dict = any as? [String: Any] {
            return imageURL(fromJSONLD: dict["url"] ?? dict["contentUrl"], base: base)
        }
        if let array = any as? [Any] {
            for item in array {
                if let found = imageURL(fromJSONLD: item, base: base) { return found }
            }
        }
        return nil
    }

    // MARK: JSON helpers

    private static func string(_ any: Any?) -> String? {
        guard let any else { return nil }
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        if let dict = any as? [String: Any] {
            return string(dict["@value"]) ?? string(dict["text"]) ?? string(dict["name"])
        }
        if let array = any as? [Any] { return array.compactMap(string).first }
        return nil
    }

    private static func strings(_ any: Any?) -> [String] {
        guard let any else { return [] }
        if let s = any as? String {
            // Some sites give one string with line breaks or list markup.
            if s.contains("<li") || s.contains("<br") || s.contains("\n") {
                return HTML.textLines(from: s)
            }
            return [s]
        }
        if let n = any as? NSNumber { return [n.stringValue] }
        if let array = any as? [Any] { return array.flatMap(strings) }
        if let dict = any as? [String: Any] {
            if let value = dict["@value"] ?? dict["text"] ?? dict["name"] { return strings(value) }
            return []
        }
        return []
    }

    private static func clean(_ text: String) -> String {
        HTML.stripTags(text)
    }

    private static func authorName(_ any: Any?) -> String? {
        guard let any else { return nil }
        if let s = any as? String { return clean(s).nilIfBlank }
        if let dict = any as? [String: Any] { return string(dict["name"]).map(clean)?.nilIfBlank }
        if let array = any as? [Any] { return array.compactMap(authorName).first }
        return nil
    }

    private static func steps(from any: Any?) -> [Step] {
        guard let any else { return [] }
        var out: [Step] = []
        append(any, into: &out, depth: 0)
        // A single blob step is a paragraph that wants splitting.
        if out.count == 1, out[0].text.count > 220, !out[0].isHeading {
            let text = out[0].text
            let pieces = TextRecipeParser.splitIntoSteps(text)
            if pieces.count > 1 { out = pieces.map { Step(text: $0) } }
        }
        return out.filter { !$0.text.isBlank }
    }

    private static func append(_ any: Any, into out: inout [Step], depth: Int) {
        guard depth < 6 else { return }
        if let s = any as? String {
            for line in HTML.textLines(from: s) {
                let text = TextRecipeParser.stripStepNumber(line)
                if !text.isEmpty { out.append(Step(text: text)) }
            }
            return
        }
        if let array = any as? [Any] {
            for item in array { append(item, into: &out, depth: depth + 1) }
            return
        }
        if let dict = any as? [String: Any] {
            let type = (string(dict["@type"]) ?? "").lowercased()
            if type.contains("section") {
                if let name = string(dict["name"]).map(clean), !name.isEmpty {
                    out.append(Step(text: name, isHeading: true))
                }
                if let items = dict["itemListElement"] { append(items, into: &out, depth: depth + 1) }
                return
            }
            if let text = string(dict["text"]).map(clean), !text.isEmpty {
                out.append(Step(text: TextRecipeParser.stripStepNumber(text)))
                return
            }
            if let items = dict["itemListElement"] {
                append(items, into: &out, depth: depth + 1)
                return
            }
            if let item = dict["item"] {
                append(item, into: &out, depth: depth + 1)
                return
            }
            if let name = string(dict["name"]).map(clean), !name.isEmpty {
                out.append(Step(text: TextRecipeParser.stripStepNumber(name)))
            }
        }
    }

    private static let durationRegex = try! NSRegularExpression(pattern: #"^P(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#, options: [.caseInsensitive])

    /// ISO 8601 "PT1H30M" or a human "1 hour 30 minutes" into minutes.
    static func duration(_ any: Any?) -> Int? {
        guard let text = string(any)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let ns = text as NSString
        if let match = durationRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            func part(_ i: Int) -> Double {
                match.range(at: i).location == NSNotFound ? 0 : (Double(ns.substring(with: match.range(at: i))) ?? 0)
            }
            let minutes = part(1) * 1440 + part(2) * 60 + part(3) + part(4) / 60
            return minutes > 0 ? Int(minutes.rounded()) : nil
        }
        return TextRecipeParser.minutes(from: text)
    }

    // MARK: Microdata

    static func draft(fromMicrodata html: String, url: URL) -> RecipeDraft? {
        var ingredients = HTML.itemprops("recipeIngredient", in: html)
        if ingredients.isEmpty { ingredients = HTML.itemprops("ingredients", in: html) }
        if ingredients.isEmpty { ingredients = HTML.listItems(inElementWithClassContaining: "ingredient", in: html) }
        var instructions = HTML.itemprops("recipeInstructions", in: html)
        if instructions.isEmpty { instructions = HTML.listItems(inElementWithClassContaining: "instruction", in: html) }
        if instructions.isEmpty { instructions = HTML.listItems(inElementWithClassContaining: "direction", in: html) }
        if instructions.isEmpty { instructions = HTML.listItems(inElementWithClassContaining: "method", in: html) }
        guard ingredients.count >= 2, !instructions.isEmpty else { return nil }

        var recipe = Recipe()
        recipe.title = HTML.itemprops("name", in: html).first.map(TextRecipeParser.tidyTitle) ?? pageTitle(in: html) ?? ""
        recipe.headnote = HTML.itemprops("description", in: html).first ?? HTML.meta("og:description", in: html) ?? ""
        recipe.ingredients = ingredients.map(IngredientParser.parse)
        var steps: [Step] = []
        for block in instructions {
            let pieces = block.count > 300 ? TextRecipeParser.splitIntoSteps(block) : [block]
            for piece in pieces {
                let text = TextRecipeParser.stripStepNumber(piece)
                if !text.isEmpty { steps.append(Step(text: text)) }
            }
        }
        recipe.steps = steps
        if let yield = HTML.itemprops("recipeYield", in: html).first, let info = TextRecipeParser.servingsInfo(in: yield) {
            recipe.servings = info.0
            recipe.yieldText = info.1
        }
        recipe.prepMinutes = HTML.itemprops("prepTime", in: html).first.flatMap { duration($0) }
        recipe.cookMinutes = HTML.itemprops("cookTime", in: html).first.flatMap { duration($0) }
        recipe.source = RecipeSource(kind: .web, url: url)
        var draft = RecipeDraft(recipe: recipe)
        draft.rawText = ingredients.joined(separator: "\n")
        return draft
    }
}
