import Foundation
import Observation
import SwiftUI

/// Everything the app knows, in memory, with the disk kept a beat behind.
///
/// Every mutation goes through a method here so it can be persisted. Views
/// read the arrays directly and never write to them.
@MainActor
@Observable
final class Library {
    static let shared = Library()

    private(set) var recipes: [Recipe] = []
    private(set) var pantry: [PantryItem] = []
    private(set) var shopping: [ShoppingItem] = []
    private(set) var plan: [PlanEntry] = []
    private(set) var settings = AppSettings()

    private enum Store: String, CaseIterable {
        case recipes = "recipes.json"
        case pantry = "pantry.json"
        case shopping = "shopping.json"
        case plan = "plan.json"
        case settings = "settings.json"
    }

    private var pending: Set<Store> = []
    private var saveTask: Task<Void, Never>?

    init() {
        recipes = Persistence.load([Recipe].self, from: Store.recipes.rawValue) ?? []
        pantry = Persistence.load([PantryItem].self, from: Store.pantry.rawValue) ?? []
        shopping = Persistence.load([ShoppingItem].self, from: Store.shopping.rawValue) ?? []
        plan = Persistence.load([PlanEntry].self, from: Store.plan.rawValue) ?? []
        settings = Persistence.load(AppSettings.self, from: Store.settings.rawValue) ?? AppSettings()
    }

    // MARK: - Persistence

    private func schedule(_ store: Store) {
        pending.insert(store)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes everything that is waiting. Called when the app leaves the
    /// foreground, so nothing is lost to a swipe-up.
    func flush() {
        for store in pending {
            switch store {
            case .recipes: Persistence.save(recipes, to: store.rawValue)
            case .pantry: Persistence.save(pantry, to: store.rawValue)
            case .shopping: Persistence.save(shopping, to: store.rawValue)
            case .plan: Persistence.save(plan, to: store.rawValue)
            case .settings: Persistence.save(settings, to: store.rawValue)
            }
        }
        pending.removeAll()
    }

    // MARK: - AppSettings

    func update(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        settings = copy
        schedule(.settings)
    }

    /// A binding straight into one setting, for toggles and pickers.
    func setting<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in self.update { $0[keyPath: keyPath] = value } }
        )
    }

    var stapleKeys: Set<String> {
        settings.assumeStaples ? Set(settings.staples) : []
    }

    func toggleStaple(_ key: String) {
        update { settings in
            if let index = settings.staples.firstIndex(of: key) {
                settings.staples.remove(at: index)
            } else {
                settings.staples.append(key)
            }
        }
    }

    // MARK: - Recipes

    func recipe(_ id: UUID) -> Recipe? {
        recipes.first { $0.id == id }
    }

    /// Inserts or replaces, and stamps the update time.
    func save(_ recipe: Recipe) {
        var copy = recipe
        copy.updatedAt = Date()
        copy.title = copy.title.collapsed
        copy.ingredients.removeAll { $0.text.isBlank && !$0.isHeading }
        copy.steps.removeAll { $0.text.isBlank }
        if let index = recipes.firstIndex(where: { $0.id == copy.id }) {
            recipes[index] = copy
        } else {
            recipes.append(copy)
        }
        schedule(.recipes)
    }

    /// Saves a recipe exactly as given, keeping its own dates. For imports.
    func insertVerbatim(_ recipe: Recipe) {
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.append(recipe)
        }
        schedule(.recipes)
    }

    func delete(_ recipe: Recipe) {
        recipes.removeAll { $0.id == recipe.id }
        if let photoID = recipe.photoID { PhotoStore.delete(photoID) }
        for id in recipe.scanIDs { PhotoStore.delete(id) }
        plan.removeAll { $0.recipeID == recipe.id }
        schedule(.recipes)
        schedule(.plan)
    }

    func duplicate(_ recipe: Recipe) -> Recipe {
        var copy = recipe
        copy.id = UUID()
        copy.title = uniqueTitle(basedOn: recipe.title)
        copy.cookLog = []
        copy.isFavorite = false
        copy.needsReview = false
        copy.createdAt = Date()
        if let photoID = recipe.photoID, let data = PhotoStore.data(for: photoID) {
            let newID = UUID().uuidString
            copy.photoID = PhotoStore.save(data: data, id: newID) ? newID : nil
        }
        copy.scanIDs = recipe.scanIDs.compactMap { id in
            guard let data = PhotoStore.data(for: id) else { return nil }
            let newID = UUID().uuidString
            return PhotoStore.save(data: data, id: newID) ? newID : nil
        }
        save(copy)
        return copy
    }

    func uniqueTitle(basedOn candidate: String) -> String {
        let base = candidate.collapsed.isEmpty ? "Untitled" : candidate.collapsed
        let taken = Set(recipes.map { $0.title.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = recipes.firstIndex(where: { $0.id == id }) else { return }
        recipes[index].isFavorite.toggle()
        schedule(.recipes)
    }

    func markReviewed(_ id: UUID) {
        guard let index = recipes.firstIndex(where: { $0.id == id }), recipes[index].needsReview else { return }
        recipes[index].needsReview = false
        schedule(.recipes)
    }

    func logCook(_ id: UUID, rating: Int, note: String) {
        guard let index = recipes.firstIndex(where: { $0.id == id }) else { return }
        recipes[index].cookLog.append(CookEntry(date: Date(), rating: rating, note: note.collapsed))
        schedule(.recipes)
    }

    func deleteCookEntry(_ entryID: UUID, from recipeID: UUID) {
        guard let index = recipes.firstIndex(where: { $0.id == recipeID }) else { return }
        recipes[index].cookLog.removeAll { $0.id == entryID }
        schedule(.recipes)
    }

    func setNotes(_ notes: String, for id: UUID) {
        guard let index = recipes.firstIndex(where: { $0.id == id }) else { return }
        recipes[index].notes = notes
        recipes[index].updatedAt = Date()
        schedule(.recipes)
    }

    /// Every tag in use, most common first.
    var allTags: [String] {
        var counts: [String: Int] = [:]
        for recipe in recipes {
            for tag in recipe.tags { counts[tag.lowercased(), default: 0] += 1 }
        }
        return counts.sorted { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }.map(\.key)
    }

    var needsReviewCount: Int {
        recipes.filter(\.needsReview).count
    }

    // MARK: - Pantry

    var pantryIndex: PantryIndex {
        PantryIndex(pantry: pantry, staples: stapleKeys)
    }

    func hasInPantry(_ key: String) -> Bool {
        pantry.contains { $0.key == key }
    }

    @discardableResult
    func addToPantry(_ name: String, aisle: Aisle? = nil) -> PantryItem? {
        let candidate = PantryItem(name: name, aisle: aisle)
        guard !candidate.name.isEmpty else { return nil }
        if let existing = pantry.first(where: { $0.key == candidate.key }) { return existing }
        pantry.append(candidate)
        schedule(.pantry)
        return candidate
    }

    func addToPantry(_ names: [String]) {
        for name in names { addToPantry(name) }
    }

    func removeFromPantry(_ item: PantryItem) {
        pantry.removeAll { $0.id == item.id }
        schedule(.pantry)
    }

    func removeFromPantry(key: String) {
        pantry.removeAll { $0.key == key }
        schedule(.pantry)
    }

    func setUseSoon(_ item: PantryItem, _ value: Bool) {
        guard let index = pantry.firstIndex(where: { $0.id == item.id }) else { return }
        pantry[index].useSoon = value
        schedule(.pantry)
    }

    func updatePantry(_ item: PantryItem) {
        guard let index = pantry.firstIndex(where: { $0.id == item.id }) else { return }
        pantry[index] = item
        schedule(.pantry)
    }

    func clearPantry() {
        pantry.removeAll()
        schedule(.pantry)
    }

    // MARK: - Availability

    func availability(for recipe: Recipe) -> Availability {
        Availability.compute(recipe, index: pantryIndex)
    }

    /// Every recipe scored against the kitchen, best first.
    var availabilities: [Availability] {
        let index = pantryIndex
        return recipes
            .map { Availability.compute($0, index: index) }
            .sorted { a, b in
                if a.canMake != b.canMake { return a.canMake }
                if a.score != b.score { return a.score > b.score }
                return a.recipe.title.localizedCaseInsensitiveCompare(b.recipe.title) == .orderedAscending
            }
    }

    var readyToCook: [Availability] {
        availabilities.filter(\.canMake)
    }

    var almostReady: [Availability] {
        availabilities.filter(\.isClose)
    }

    /// Recipes that use something flagged "use soon", most matches first.
    var useSoonSuggestions: [(recipe: Recipe, uses: [PantryItem])] {
        let flagged = pantry.filter(\.useSoon)
        guard !flagged.isEmpty else { return [] }
        let index = pantryIndex
        return recipes.compactMap { recipe -> (Recipe, [PantryItem])? in
            let keys = Set(recipe.realIngredients.map(\.key))
            let uses = flagged.filter { item in
                keys.contains(item.key) || IngredientCatalog.entry(for: item.key)?.parent.map { keys.contains($0) } == true
            }
            guard !uses.isEmpty else { return nil }
            return (recipe, uses)
        }
        .sorted { a, b in
            if a.1.count != b.1.count { return a.1.count > b.1.count }
            return Availability.compute(a.0, index: index).score > Availability.compute(b.0, index: index).score
        }
        .map { (recipe: $0.0, uses: $0.1) }
    }

    // MARK: - Shopping

    func addToShopping(_ name: String) {
        let item = ShoppingItem(name: name)
        guard !item.name.isEmpty else { return }
        if let index = shopping.firstIndex(where: { $0.key == item.key }) {
            if shopping[index].isChecked {
                shopping[index].isChecked = false
                shopping[index].addedAt = Date()
            }
        } else {
            shopping.append(item)
        }
        schedule(.shopping)
    }

    func addToShopping(_ ingredient: Ingredient, scale: Double = 1, from recipe: Recipe? = nil) {
        ShoppingMerge.add(ingredient, scale: scale, recipeID: recipe?.id, into: &shopping)
        schedule(.shopping)
    }

    /// Adds what the kitchen lacks for a recipe. Returns how many were added.
    @discardableResult
    func addMissing(for recipe: Recipe, scale: Double = 1) -> Int {
        let availability = availability(for: recipe)
        let missing = availability.missing
        for ingredient in missing {
            ShoppingMerge.add(ingredient, scale: scale, recipeID: recipe.id, into: &shopping)
        }
        if !missing.isEmpty { schedule(.shopping) }
        return missing.count
    }

    /// Adds every ingredient of a recipe, for cooking it from an empty kitchen.
    func addAll(for recipe: Recipe, scale: Double = 1) {
        for ingredient in recipe.realIngredients {
            ShoppingMerge.add(ingredient, scale: scale, recipeID: recipe.id, into: &shopping)
        }
        schedule(.shopping)
    }

    func toggleChecked(_ item: ShoppingItem) {
        guard let index = shopping.firstIndex(where: { $0.id == item.id }) else { return }
        shopping[index].isChecked.toggle()
        schedule(.shopping)
    }

    func removeFromShopping(_ item: ShoppingItem) {
        shopping.removeAll { $0.id == item.id }
        schedule(.shopping)
    }

    func updateShopping(_ item: ShoppingItem) {
        guard let index = shopping.firstIndex(where: { $0.id == item.id }) else { return }
        shopping[index] = item
        schedule(.shopping)
    }

    func clearChecked() {
        shopping.removeAll(where: \.isChecked)
        schedule(.shopping)
    }

    func clearShopping() {
        shopping.removeAll()
        schedule(.shopping)
    }

    /// Checked items go into the pantry and off the list: the trip home.
    @discardableResult
    func moveCheckedToPantry() -> Int {
        let bought = shopping.filter(\.isChecked)
        for item in bought { addToPantry(item.name, aisle: item.aisle) }
        shopping.removeAll(where: \.isChecked)
        schedule(.shopping)
        return bought.count
    }

    var uncheckedShopping: [ShoppingItem] { shopping.filter { !$0.isChecked } }

    // MARK: - Plan

    func entries(for dayKey: String) -> [PlanEntry] {
        plan.filter { $0.dayKey == dayKey }.sorted { $0.meal.order < $1.meal.order }
    }

    func addPlan(dayKey: String, meal: Meal, recipeID: UUID?, note: String = "") {
        plan.append(PlanEntry(dayKey: dayKey, meal: meal, recipeID: recipeID, note: note.collapsed))
        schedule(.plan)
    }

    func removePlan(_ entry: PlanEntry) {
        plan.removeAll { $0.id == entry.id }
        schedule(.plan)
    }

    func movePlan(_ entry: PlanEntry, to dayKey: String, meal: Meal) {
        guard let index = plan.firstIndex(where: { $0.id == entry.id }) else { return }
        plan[index].dayKey = dayKey
        plan[index].meal = meal
        schedule(.plan)
    }

    /// Drops entries older than yesterday.
    func clearPastPlan() {
        let cutoff = DayKey.key(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        plan.removeAll { $0.dayKey < cutoff }
        schedule(.plan)
    }

    var upcomingPlan: [PlanEntry] {
        let today = DayKey.today
        return plan.filter { $0.dayKey >= today }.sorted { a, b in
            a.dayKey != b.dayKey ? a.dayKey < b.dayKey : a.meal.order < b.meal.order
        }
    }

    /// Recipes planned in the next `days` days.
    func plannedRecipes(days: Int) -> [Recipe] {
        let keys = Set(DayKey.upcoming(days))
        var seen = Set<UUID>()
        return plan
            .filter { keys.contains($0.dayKey) }
            .sorted { $0.dayKey < $1.dayKey }
            .compactMap { entry in
                guard let id = entry.recipeID, seen.insert(id).inserted else { return nil }
                return recipe(id)
            }
    }

    /// Puts everything missing for the coming week on the list.
    @discardableResult
    func shopForPlan(days: Int = 7) -> Int {
        var added = 0
        for recipe in plannedRecipes(days: days) {
            added += addMissing(for: recipe)
        }
        return added
    }

    // MARK: - Photos

    /// Saves a photo and returns its id, or nil if it could not be written.
    func storePhoto(_ image: UIImage) -> String? {
        PhotoStore.save(image)
    }

    // MARK: - First run

    func completeOnboarding(addStaples: Bool, addSample: Bool) {
        if addStaples {
            addToPantry(IngredientCatalog.commonKitchen)
        }
        if addSample && !recipes.contains(where: { $0.id == SampleRecipe.id }) {
            insertVerbatim(SampleRecipe.make())
        }
        update { $0.hasOnboarded = true }
    }

    func restoreSample() {
        insertVerbatim(SampleRecipe.make())
    }
}
