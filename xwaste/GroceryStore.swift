import CoreData

/// Snapshot of a check-off, held in view state, that undo verifies against
/// before reversing. An explicit delta record rather than `UndoManager`:
/// reversing the merge branch correctly requires knowing that this specific
/// check-off contributed the quantity, not resetting to a remembered absolute.
struct CheckOffUndo {
    enum Branch {
        /// The list row itself flipped location to `.atHome`.
        case movedToHome
        /// The quantity was folded into an existing home row; the list row was deleted.
        case mergedIntoExisting
    }

    let name: String
    let normalizedName: String
    let quantity: Int64
    let category: GroceryCategory
    let categoryIsManual: Bool
    let branch: Branch
    /// The home item's quantity immediately after the check-off. If it differs
    /// at undo time, someone else edited it in between.
    let expectedHomeQuantity: Int64
    let householdID: NSManagedObjectID
}

enum UndoCheckOffResult {
    case reversed
    /// The home item was edited, deleted, or used up elsewhere: the list row
    /// was restored, the home inventory was deliberately left untouched.
    case changedElsewhere
}

/// Every mutation that can touch more than one row — merge-on-add, check-off,
/// move-back, undo, rename — lives here, over an `NSManagedObjectContext`, so
/// the invariant "no two rows share a normalized name in the same location
/// within a household" is enforced in one place.
enum GroceryStore {

    static func findItem(normalizedName: String,
                         location: ItemLocation,
                         household: Household,
                         in context: NSManagedObjectContext) -> GroceryItem? {
        let request = GroceryItem.fetchRequest()
        request.predicate = NSPredicate(
            format: "normalizedName == %@ AND locationRawValue == %@ AND household == %@",
            normalizedName, location.rawValue, household
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Adds an item, merging into an existing row with the same normalized name
    /// in the same location instead of ever creating a duplicate.
    @discardableResult
    static func addItem(name: String,
                        quantity: Int64,
                        location: ItemLocation,
                        household: Household,
                        context: NSManagedObjectContext) -> GroceryItem {
        let normalized = GroceryItem.normalize(name)
        if let existing = findItem(normalizedName: normalized, location: location,
                                   household: household, in: context) {
            existing.quantity += max(1, quantity)
            save(context)
            return existing
        }
        let item = GroceryItem.create(name: name, quantity: quantity, location: location,
                                      household: household, in: context)
        save(context)
        return item
    }

    /// Quantities at or below zero delete the row — no zero-quantity record can
    /// ever be stored.
    static func setQuantity(_ item: GroceryItem, to quantity: Int64, context: NSManagedObjectContext) {
        if quantity <= 0 {
            context.delete(item)
        } else {
            item.quantity = quantity
        }
        save(context)
    }

    static func adjustQuantity(_ item: GroceryItem, by delta: Int64, context: NSManagedObjectContext) {
        setQuantity(item, to: item.quantity + delta, context: context)
    }

    /// Marks a shopping-list item purchased: flips it to `.atHome`, or folds its
    /// quantity into an existing home row and deletes the list row.
    static func checkOff(_ item: GroceryItem, context: NSManagedObjectContext) -> CheckOffUndo? {
        guard let household = item.household, let normalized = item.normalizedName else { return nil }

        let undo: CheckOffUndo
        if let home = findItem(normalizedName: normalized, location: .atHome,
                               household: household, in: context) {
            home.quantity += item.quantity
            undo = CheckOffUndo(name: item.displayName, normalizedName: normalized,
                                quantity: item.quantity, category: item.category,
                                categoryIsManual: item.categoryIsManual,
                                branch: .mergedIntoExisting,
                                expectedHomeQuantity: home.quantity,
                                householdID: household.objectID)
            context.delete(item)
        } else {
            undo = CheckOffUndo(name: item.displayName, normalizedName: normalized,
                                quantity: item.quantity, category: item.category,
                                categoryIsManual: item.categoryIsManual,
                                branch: .movedToHome,
                                expectedHomeQuantity: item.quantity,
                                householdID: household.objectID)
            item.location = .atHome
        }
        save(context)
        return undo
    }

    /// Reverses exactly the recorded branch — after re-fetching the home item
    /// and verifying its quantity still matches. Three outcomes on the
    /// re-fetch: match (reverse normally), mismatch, or gone. Gone is the
    /// likelier failure — decrement-to-zero deletes the row — and it must NOT
    /// be treated as quantity 0, which would resurrect a row someone
    /// deliberately used up. Mismatch and gone both restore the list row,
    /// leave the home inventory alone, and report it.
    static func undoCheckOff(_ undo: CheckOffUndo, context: NSManagedObjectContext) -> UndoCheckOffResult {
        guard let household = (try? context.existingObject(with: undo.householdID)) as? Household else {
            return .changedElsewhere
        }
        let home = findItem(normalizedName: undo.normalizedName, location: .atHome,
                            household: household, in: context)

        guard let home, home.quantity == undo.expectedHomeQuantity else {
            restoreListRow(from: undo, household: household, context: context)
            save(context)
            return .changedElsewhere
        }

        switch undo.branch {
        case .movedToHome:
            // Same row, unchanged since: flipping back restores the list exactly.
            home.location = .shoppingList
        case .mergedIntoExisting:
            home.quantity -= undo.quantity  // back to its pre-check-off value, ≥ 1
            restoreListRow(from: undo, household: household, context: context)
        }
        save(context)
        return .reversed
    }

    /// The permanent recovery path after the undo banner is gone. Preserves
    /// name, quantity, category, and manual flag; merges into an existing
    /// shopping-list row when one matches.
    static func moveBackToShoppingList(_ item: GroceryItem, context: NSManagedObjectContext) {
        guard let household = item.household, let normalized = item.normalizedName else { return }
        if let listRow = findItem(normalizedName: normalized, location: .shoppingList,
                                  household: household, in: context) {
            listRow.quantity += item.quantity
            context.delete(item)
        } else {
            item.location = .shoppingList
        }
        save(context)
    }

    /// Renames an item, recomputing `normalizedName` and reclassifying only
    /// when the category is not manual. Renaming into a name already used in
    /// the same location merges instead — two rows with one normalized name is
    /// the state every duplicate and merge path downstream assumes cannot
    /// exist. The pre-existing row survives with its own display name,
    /// category, and manual flag; only its quantity changes.
    @discardableResult
    static func rename(_ item: GroceryItem, to newName: String, context: NSManagedObjectContext) -> GroceryItem {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = GroceryItem.normalize(trimmed)
        guard !normalized.isEmpty else { return item }

        if let household = item.household,
           let existing = findItem(normalizedName: normalized, location: item.location,
                                   household: household, in: context),
           existing != item {
            existing.quantity += item.quantity
            context.delete(item)
            save(context)
            return existing
        }

        item.name = trimmed
        item.normalizedName = normalized
        if !item.categoryIsManual {
            item.category = CategoryClassifier.classify(trimmed)
        }
        save(context)
        return item
    }

    /// A manually set category is sticky: renames no longer reclassify.
    static func setCategory(_ item: GroceryItem, to category: GroceryCategory, context: NSManagedObjectContext) {
        item.category = category
        item.categoryIsManual = true
        save(context)
    }

    /// Clears the manual pin and immediately reclassifies from the current name.
    static func revertToAutomaticCategory(_ item: GroceryItem, context: NSManagedObjectContext) {
        item.categoryIsManual = false
        item.category = CategoryClassifier.classify(item.displayName)
        save(context)
    }

    // MARK: - Private

    @discardableResult
    private static func restoreListRow(from undo: CheckOffUndo,
                                       household: Household,
                                       context: NSManagedObjectContext) -> GroceryItem {
        if let existing = findItem(normalizedName: undo.normalizedName, location: .shoppingList,
                                   household: household, in: context) {
            existing.quantity += undo.quantity
            return existing
        }
        let item = GroceryItem(context: context)
        item.name = undo.name
        item.normalizedName = undo.normalizedName
        item.quantity = undo.quantity
        item.category = undo.category
        item.categoryIsManual = undo.categoryIsManual
        item.location = .shoppingList
        item.createdAt = Date()
        item.household = household
        return item
    }

    private static func save(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("Core Data save failed: \(error)")
            context.rollback()
        }
    }
}
