import CoreData

@objc(Recipe)
nonisolated final class Recipe: NSManagedObject {
    @NSManaged var name: String?
    @NSManaged var summary: String?
    @NSManaged var imageData: Data?
    @NSManaged var createdAt: Date?
    @NSManaged var household: Household?
    @NSManaged var ingredients: NSSet?
    @NSManaged var steps: NSSet?
}

extension Recipe {
    @nonobjc static func fetchRequest() -> NSFetchRequest<Recipe> {
        NSFetchRequest<Recipe>(entityName: "Recipe")
    }

    var displayName: String { name ?? "" }

    var orderedIngredients: [RecipeIngredient] {
        (ingredients as? Set<RecipeIngredient>)
            .map(Array.init)?
            .sorted { $0.orderIndex < $1.orderIndex } ?? []
    }

    var orderedSteps: [RecipeStep] {
        (steps as? Set<RecipeStep>)
            .map(Array.init)?
            .sorted { $0.orderIndex < $1.orderIndex } ?? []
    }
}
