import Foundation

/// One recipe in the book on day one, so the formatting has something to
/// show before anything is scanned. Deletable like any other.
enum SampleRecipe {
    static let id = UUID(uuidString: "2B7A0C6E-4C1F-4F5E-9E2B-6C1F4A8D9B10")!

    static func make() -> Recipe {
        var recipe = Recipe()
        recipe.id = id
        recipe.title = "Sunday Pancakes"
        recipe.headnote = "The ones that get made without a recipe eventually. Until then, this."
        recipe.ingredients = [
            "1½ cups all-purpose flour",
            "3½ teaspoons baking powder",
            "1 tablespoon sugar",
            "¼ teaspoon salt",
            "1¼ cups milk",
            "1 egg",
            "3 tablespoons butter, melted, plus more for the pan",
            "1 teaspoon vanilla extract",
        ].map(IngredientParser.parse)
        recipe.steps = [
            "Whisk the flour, baking powder, sugar and salt together in a large bowl.",
            "In a measuring jug, whisk the milk, egg, melted butter and vanilla until smooth.",
            "Pour the wet into the dry and stir just until no dry flour is left. A few lumps are fine. Let the batter rest 5 minutes.",
            "Heat a skillet or griddle over medium heat and rub it with a little butter.",
            "Pour about ¼ cup of batter per pancake. Cook until bubbles form and the edges look set, 2 to 3 minutes, then flip and cook 1 to 2 minutes more.",
            "Keep warm in a low oven while the rest cook. Serve with butter and maple syrup.",
        ].map { Step(text: $0) }
        recipe.servings = 4
        recipe.yieldText = "about 12 pancakes"
        recipe.prepMinutes = 10
        recipe.cookMinutes = 15
        recipe.tags = ["breakfast", "family"]
        recipe.source = RecipeSource(kind: .written, name: "Ladle")
        recipe.notes = "Buttermilk instead of milk, plus ½ teaspoon baking soda, makes them taller."
        return recipe
    }
}
