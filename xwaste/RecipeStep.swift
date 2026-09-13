import CoreData

@objc(RecipeStep)
nonisolated final class RecipeStep: NSManagedObject {
    @NSManaged var text: String?
    @NSManaged var orderIndex: Int64
    @NSManaged var recipe: Recipe?
}

extension RecipeStep {
    @nonobjc static func fetchRequest() -> NSFetchRequest<RecipeStep> {
        NSFetchRequest<RecipeStep>(entityName: "RecipeStep")
    }

    var displayText: String { text ?? "" }
}
