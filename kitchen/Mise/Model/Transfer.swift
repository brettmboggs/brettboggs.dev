import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// One recipe, with its photo inside. Opens in Mise on another phone.
    static let miseRecipe = UTType(exportedAs: "dev.brettboggs.mise.recipe", conformingTo: .json)
    /// The whole book: recipes, pantry, list, plan, settings.
    static let miseLibrary = UTType(exportedAs: "dev.brettboggs.mise.library", conformingTo: .json)
}

// MARK: - Plain text

enum RecipeText {
    /// The recipe as a message: what gets pasted into a text to a friend.
    static func render(_ recipe: Recipe, scale: Double = 1, system: UnitSystem = .us) -> String {
        var lines: [String] = []
        lines.append(recipe.title.uppercased())
        if !recipe.headnote.isBlank { lines.append(recipe.headnote) }
        var meta: [String] = []
        if let yield = Format.yield(servings: recipe.servings.map { Int((Double($0) * scale).rounded()) }, text: scale == 1 ? recipe.yieldText : nil) {
            meta.append(yield)
        }
        if let prep = recipe.prepMinutes, prep > 0 { meta.append("Prep " + Format.minutes(prep)) }
        if let cook = recipe.cookMinutes, cook > 0 { meta.append("Cook " + Format.minutes(cook)) }
        if !meta.isEmpty { lines.append(meta.joined(separator: " · ")) }
        lines.append("")
        lines.append("INGREDIENTS")
        for ingredient in recipe.ingredients {
            if ingredient.isHeading {
                lines.append("")
                lines.append(ingredient.name + ":")
            } else {
                lines.append("• " + IngredientLine.text(ingredient, scale: scale, system: system))
            }
        }
        lines.append("")
        lines.append("METHOD")
        var n = 0
        for step in recipe.steps where !step.text.isBlank {
            if step.isHeading {
                lines.append("")
                lines.append(step.text + ":")
            } else {
                n += 1
                lines.append("\(n). " + step.text)
            }
        }
        if !recipe.notes.isBlank {
            lines.append("")
            lines.append("NOTES")
            lines.append(recipe.notes)
        }
        if let label = recipe.source.label {
            lines.append("")
            if let url = recipe.source.url {
                lines.append("From \(label): \(url.absoluteString)")
            } else {
                lines.append("From \(label)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum IngredientLine {
    /// "1½ cups all-purpose flour, sifted" at the given scale.
    static func text(_ ingredient: Ingredient, scale: Double, system: UnitSystem) -> String {
        if ingredient.quantity == nil && ingredient.unit == nil {
            return ingredient.text.isBlank ? ingredient.name : ingredient.text
        }
        let amount = QuantityText.string(quantity: ingredient.quantity, quantityMax: ingredient.quantityMax, unit: ingredient.unit, scale: scale, system: system)
        var line = amount.isEmpty ? ingredient.name : amount + " " + ingredient.name
        if let prep = ingredient.prep, !prep.isEmpty { line += ", " + prep }
        if ingredient.isOptional { line += " (optional)" }
        return line
    }
}

// MARK: - Files

/// One recipe on disk or in a message. Photo and scans travel inside.
struct RecipeFile: Codable {
    var format: String = "mise-recipe"
    var version: Int = 1
    var recipe: Recipe
    var photo: Data?
    var scans: [Data] = []

    init(recipe: Recipe) {
        self.recipe = recipe
        self.photo = recipe.photoID.flatMap(PhotoStore.data(for:))
        self.scans = recipe.scanIDs.compactMap(PhotoStore.data(for:))
    }

    enum CodingKeys: String, CodingKey {
        case format, version, recipe, photo, scans
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? "mise-recipe"
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        recipe = try c.decode(Recipe.self, forKey: .recipe)
        photo = try c.decodeIfPresent(Data.self, forKey: .photo)
        scans = try c.decodeIfPresent([Data].self, forKey: .scans) ?? []
    }
}

struct LibraryFile: Codable {
    var format: String = "mise-library"
    var version: Int = 1
    var exportedAt: Date = Date()
    var recipes: [RecipeFile]
    var pantry: [PantryItem]
    var shopping: [ShoppingItem]
    var plan: [PlanEntry]
    var settings: AppSettings

    init(recipes: [RecipeFile], pantry: [PantryItem], shopping: [ShoppingItem], plan: [PlanEntry], settings: AppSettings) {
        self.recipes = recipes
        self.pantry = pantry
        self.shopping = shopping
        self.plan = plan
        self.settings = settings
    }

    enum CodingKeys: String, CodingKey {
        case format, version, exportedAt, recipes, pantry, shopping, plan, settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? "mise-library"
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        recipes = try c.decodeIfPresent([RecipeFile].self, forKey: .recipes) ?? []
        pantry = try c.decodeIfPresent([PantryItem].self, forKey: .pantry) ?? []
        shopping = try c.decodeIfPresent([ShoppingItem].self, forKey: .shopping) ?? []
        plan = try c.decodeIfPresent([PlanEntry].self, forKey: .plan) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
    }
}

/// A recipe as something the share sheet can hand over as a `.mise` file.
struct RecipeDocument: Transferable {
    let data: Data
    let fileName: String

    init(recipe: Recipe) {
        data = (try? Persistence.encoder.encode(RecipeFile(recipe: recipe))) ?? Data()
        fileName = Transfer.fileName(recipe.title, ext: "mise")
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .miseRecipe) { document in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(document.fileName)
            try document.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
        .suggestedFileName { $0.fileName }
    }
}

struct LibraryDocument: Transferable {
    let data: Data
    let fileName: String

    @MainActor
    init(library: Library) {
        let file = LibraryFile(
            recipes: library.recipes.map(RecipeFile.init(recipe:)),
            pantry: library.pantry,
            shopping: library.shopping,
            plan: library.plan,
            settings: library.settings
        )
        data = (try? Persistence.encoder.encode(file)) ?? Data()
        let stamp = Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        fileName = Transfer.fileName("Mise cookbook \(stamp)", ext: "misebook")
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .miseLibrary) { document in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(document.fileName)
            try document.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
        .suggestedFileName { $0.fileName }
    }
}

enum Transfer {
    static func fileName(_ title: String, ext: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        var cleaned = title.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
        cleaned = cleaned.collapsed
        if cleaned.isEmpty { cleaned = "Recipe" }
        return String(cleaned.prefix(60)) + "." + ext
    }

    /// A temporary file URL holding a plain-text copy, for printing or
    /// AirDrop to a computer.
    static func textFile(for recipe: Recipe, system: UnitSystem) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(recipe.title, ext: "txt"))
        do {
            try RecipeText.render(recipe, system: system).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Import

enum ImportOutcome {
    case recipes([Recipe])
    case library(recipes: Int, pantry: Int)
}

enum ImportError: LocalizedError {
    case unreadable
    case unknownFormat

    var errorDescription: String? {
        switch self {
        case .unreadable: return "That file could not be read."
        case .unknownFormat: return "That is not a Mise recipe file."
        }
    }
}

enum FileImporter {
    /// Reads a `.mise` or `.misebook` file into the library.
    @MainActor
    static func importFile(at url: URL, into library: Library) throws -> ImportOutcome {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        return try importData(data, into: library)
    }

    @MainActor
    static func importData(_ data: Data, into library: Library) throws -> ImportOutcome {
        if let file = try? Persistence.decoder.decode(LibraryFile.self, from: data), file.format == "mise-library" {
            var count = 0
            for entry in file.recipes {
                if let recipe = restore(entry, into: library) {
                    count += 1
                    _ = recipe
                }
            }
            var pantryAdded = 0
            for item in file.pantry where !library.hasInPantry(item.key) {
                library.addToPantry(item.name, aisle: item.aisle)
                pantryAdded += 1
            }
            for item in file.shopping where !item.isChecked {
                library.addToShopping(item.name)
            }
            for entry in file.plan where entry.dayKey >= DayKey.today {
                library.addPlan(dayKey: entry.dayKey, meal: entry.meal, recipeID: entry.recipeID, note: entry.note)
            }
            return .library(recipes: count, pantry: pantryAdded)
        }
        if let file = try? Persistence.decoder.decode(RecipeFile.self, from: data), file.format == "mise-recipe" {
            guard let recipe = restore(file, into: library) else { throw ImportError.unreadable }
            return .recipes([recipe])
        }
        if let recipes = try? Persistence.decoder.decode([RecipeFile].self, from: data), !recipes.isEmpty {
            return .recipes(recipes.compactMap { restore($0, into: library) })
        }
        throw ImportError.unknownFormat
    }

    /// Puts the photos on disk under fresh ids and saves the recipe. A recipe
    /// already in the book with the same id is only replaced by a newer copy.
    @MainActor
    private static func restore(_ file: RecipeFile, into library: Library) -> Recipe? {
        var recipe = file.recipe
        guard !recipe.title.isBlank else { return nil }
        if let existing = library.recipe(recipe.id), existing.updatedAt >= recipe.updatedAt {
            return existing
        }
        if let photo = file.photo {
            let id = UUID().uuidString
            recipe.photoID = PhotoStore.save(data: photo, id: id) ? id : nil
        } else {
            recipe.photoID = nil
        }
        recipe.scanIDs = file.scans.compactMap { data in
            let id = UUID().uuidString
            return PhotoStore.save(data: data, id: id) ? id : nil
        }
        recipe.source.kind = recipe.source.kind == .written ? .file : recipe.source.kind
        library.insertVerbatim(recipe)
        return recipe
    }
}
