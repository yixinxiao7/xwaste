import CoreData

/// The sharing root: one record owning every `GroceryItem`, so a `CKShare` of it
/// carries the list and the inventory together. It has no name — the member list
/// comes from the `CKShare` participants, not from stored fields.
@objc(Household)
nonisolated final class Household: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var createdAt: Date?
    @NSManaged var items: NSSet?
}

extension Household {
    @nonobjc static func fetchRequest() -> NSFetchRequest<Household> {
        NSFetchRequest<Household>(entityName: "Household")
    }

    var itemsArray: [GroceryItem] {
        (items as? Set<GroceryItem>).map(Array.init) ?? []
    }
}
