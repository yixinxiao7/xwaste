import CoreData

/// Per-ingredient status for one recipe: how many the household has on hand
/// versus how many the recipe needs.
nonisolated struct IngredientAvailability {
    let ingredient: RecipeIngredient
    /// > 0 when At Home does not cover this ingredient's count.
    let shortfall: Int64
    var isShort: Bool { shortfall > 0 }
}

nonisolated struct RecipeStatus {
    let ingredients: [IngredientAvailability]
    let canMake: Bool
}

/// Pure status logic: never touches Core Data beyond reading the model types
/// handed to it, never persists a result. Computed fresh from one in-memory
/// pass over the household's At Home inventory every time a view needs it.
nonisolated enum RecipeAvailability {

    /// Builds a `[normalizedName: quantity]` map from At Home items. Rows with
    /// the same normalized name are summed, matching the invariant that
    /// `GroceryStore` already enforces (there should only ever be one).
    static func inventory(from items: some Sequence<GroceryItem>) -> [String: Int64] {
        var result: [String: Int64] = [:]
        for item in items {
            guard let normalized = item.normalizedName else { continue }
            result[normalized, default: 0] += item.quantity
        }
        return result
    }

    /// A recipe with zero ingredients can always be made.
    static func evaluate(recipe: Recipe, inventory: [String: Int64]) -> RecipeStatus {
        let ingredients = recipe.orderedIngredients
        let statuses = ingredients.map { ingredient -> IngredientAvailability in
            let onHand = ingredient.normalizedName.flatMap { inventory[$0] } ?? 0
            let shortfall = max(0, ingredient.quantity - onHand)
            return IngredientAvailability(ingredient: ingredient, shortfall: shortfall)
        }
        return RecipeStatus(ingredients: statuses, canMake: statuses.allSatisfy { !$0.isShort })
    }
}
