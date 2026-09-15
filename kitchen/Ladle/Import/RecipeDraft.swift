import Foundation
import UIKit

/// A recipe on its way in, with everything the importer was unsure about
/// marked so the review screen can point at it.
struct RecipeDraft {
    var recipe: Recipe
    var warnings: [String] = []
    var flaggedIngredientIDs: Set<UUID> = []
    var flaggedStepIDs: Set<UUID> = []
    /// The scanned pages, kept with the recipe as the original.
    var scans: [UIImage] = []
    /// A photo found on the page, downloaded before review.
    var photo: UIImage?
    /// Where the words came from, for a "show me what you read" button.
    var rawText: String = ""

    init(recipe: Recipe) {
        self.recipe = recipe
    }

    var flagCount: Int { flaggedIngredientIDs.count + flaggedStepIDs.count }
}

extension RecipeDraft: Identifiable {
    var id: UUID { recipe.id }
}
