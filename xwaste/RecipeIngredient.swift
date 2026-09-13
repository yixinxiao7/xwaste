import CoreData

@objc(RecipeIngredient)
nonisolated final class RecipeIngredient: NSManagedObject {
    @NSManaged var name: String?
    @NSManaged var normalizedName: String?
    @NSManaged var quantity: Int64
    @NSManaged var orderIndex: Int64
    @NSManaged var recipe: Recipe?
}

extension RecipeIngredient {
    @nonobjc static func fetchRequest() -> NSFetchRequest<RecipeIngredient> {
        NSFetchRequest<RecipeIngredient>(entityName: "RecipeIngredient")
    }

    var displayName: String { name ?? "" }
}
