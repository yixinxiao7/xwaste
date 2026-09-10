import Testing
import CoreData
@testable import xwaste

/// Store-invariant tests over an in-memory Core Data stack — no CloudKit, no
/// devices, no flakiness. One `GroceryStore` now serves iOS, macOS, and
/// watchOS, so these are the permanent regression guard for the app's
/// non-negotiables: an undo path that verifies before reversing, no
/// zero-quantity rows, and warn-never-block.
@MainActor
struct GroceryStoreTests {

    let context: NSManagedObjectContext
    let household: Household

    /// A fresh in-memory stack per test — Swift Testing builds a new instance
    /// for every `@Test`, so no test can see another's rows.
    init() {
        let controller = PersistenceController(inMemory: true)
        context = controller.container.viewContext
        household = controller.activeHousehold
    }

    // MARK: - Helpers

    @discardableResult
    private func add(_ name: String, _ quantity: Int64, _ location: ItemLocation) -> GroceryItem {
        GroceryStore.addItem(name: name, quantity: quantity, location: location,
                             household: household, context: context)
    }

    private func items(in location: ItemLocation) -> [GroceryItem] {
        let request = GroceryItem.fetchRequest()
        request.predicate = NSPredicate(format: "locationRawValue == %@ AND household == %@",
                                        location.rawValue, household)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    private func find(_ name: String, _ location: ItemLocation) -> GroceryItem? {
        GroceryStore.findItem(normalizedName: GroceryItem.normalize(name), location: location,
                              household: household, in: context)
    }

    /// The model-wide invariant: a stored row always has a positive quantity.
    private func assertNoZeroQuantityRows(_ comment: Comment) {
        let all = (try? context.fetch(GroceryItem.fetchRequest())) ?? []
        #expect(all.allSatisfy { $0.quantity >= 1 }, comment)
    }

    // MARK: - 4.1 checkOff

    @Test("Check-off with no home row flips the row's location and records the branch")
    func checkOffCreatesHomeRow() throws {
        let onion = add("Onion", 2, .shoppingList)

        let undo = try #require(GroceryStore.checkOff(onion, context: context))

        #expect(items(in: .shoppingList).isEmpty)
        let home = try #require(find("Onion", .atHome))
        #expect(home.quantity == 2)
        #expect(undo.branch == .movedToHome)
        #expect(undo.name == "Onion")
        #expect(undo.quantity == 2)
        #expect(undo.expectedHomeQuantity == 2)
    }

    @Test("Check-off merges into an existing home row and deletes the list row")
    func checkOffMergesIntoExistingHomeRow() throws {
        add("Onion", 3, .atHome)
        let listRow = add("Onion", 2, .shoppingList)
        GroceryStore.setCategory(listRow, to: .snacks, context: context)

        let undo = try #require(GroceryStore.checkOff(listRow, context: context))

        #expect(items(in: .shoppingList).isEmpty)
        #expect(items(in: .atHome).count == 1)
        #expect(try #require(find("Onion", .atHome)).quantity == 5)
        // The undo value carries the prior state the list row is rebuilt from.
        #expect(undo.branch == .mergedIntoExisting)
        #expect(undo.quantity == 2)
        #expect(undo.expectedHomeQuantity == 5)
        #expect(undo.category == .snacks)
        #expect(undo.categoryIsManual)
    }

    // MARK: - 4.2 undoCheckOff, happy path

    @Test("Undo of a moved row restores the list exactly and leaves nothing at home")
    func undoReversesMovedRow() throws {
        let onion = add("Onion", 2, .shoppingList)
        let undo = try #require(GroceryStore.checkOff(onion, context: context))

        #expect(GroceryStore.undoCheckOff(undo, context: context) == .reversed)

        // The home row the check-off produced is gone — it was the same row.
        #expect(items(in: .atHome).isEmpty)
        let restored = try #require(find("Onion", .shoppingList))
        #expect(restored.quantity == 2)
        #expect(items(in: .shoppingList).count == 1)
    }

    @Test("Undo of a merge subtracts exactly its own delta and rebuilds the list row")
    func undoReversesMerge() throws {
        add("Onion", 3, .atHome)
        let listRow = add("Onion", 2, .shoppingList)
        let undo = try #require(GroceryStore.checkOff(listRow, context: context))

        #expect(GroceryStore.undoCheckOff(undo, context: context) == .reversed)

        #expect(try #require(find("Onion", .atHome)).quantity == 3)
        let restored = try #require(find("Onion", .shoppingList))
        #expect(restored.quantity == 2)
        #expect(restored.category == undo.category)
        #expect(restored.categoryIsManual == undo.categoryIsManual)
    }

    // MARK: - 4.3 undoCheckOff, changed-elsewhere race

    @Test("A home quantity changed between check-off and undo is left as the other writer set it")
    func undoDetectsChangedHomeQuantity() throws {
        add("Onion", 3, .atHome)
        let listRow = add("Onion", 2, .shoppingList)
        let undo = try #require(GroceryStore.checkOff(listRow, context: context))

        // Another household member uses one up before Undo is tapped.
        GroceryStore.adjustQuantity(try #require(find("Onion", .atHome)), by: -1, context: context)

        #expect(GroceryStore.undoCheckOff(undo, context: context) == .changedElsewhere)

        // List row restored; the home quantity is not second-guessed.
        #expect(try #require(find("Onion", .shoppingList)).quantity == 2)
        #expect(try #require(find("Onion", .atHome)).quantity == 4)
    }

    @Test("A home row used up entirely before Undo is not resurrected")
    func undoDetectsDeletedHomeRow() throws {
        let onion = add("Onion", 2, .shoppingList)
        let undo = try #require(GroceryStore.checkOff(onion, context: context))

        // Decrement-to-zero deletes the row — the likelier race, and a nil
        // re-fetch must never be read as quantity 0.
        GroceryStore.adjustQuantity(try #require(find("Onion", .atHome)), by: -2, context: context)

        #expect(GroceryStore.undoCheckOff(undo, context: context) == .changedElsewhere)

        #expect(try #require(find("Onion", .shoppingList)).quantity == 2)
        #expect(find("Onion", .atHome) == nil)
    }

    // MARK: - 4.4 Undo expiry / abandonment

    @Test("An undo value that is never used changes nothing")
    func abandonedUndoChangesNothing() throws {
        add("Onion", 3, .atHome)
        let listRow = add("Onion", 2, .shoppingList)
        _ = GroceryStore.checkOff(listRow, context: context)

        // The banner's window lapsing simply discards the CheckOffUndo; no
        // store call happens, so the check-off result stands.
        #expect(items(in: .shoppingList).isEmpty)
        #expect(try #require(find("Onion", .atHome)).quantity == 5)
    }

    @Test("Undoing after the item has moved on does not compound the change")
    func expiredUndoIsStillSafeToRun() throws {
        let onion = add("Onion", 2, .shoppingList)
        let undo = try #require(GroceryStore.checkOff(onion, context: context))
        // Long after the window: someone bought more.
        GroceryStore.adjustQuantity(try #require(find("Onion", .atHome)), by: 5, context: context)

        #expect(GroceryStore.undoCheckOff(undo, context: context) == .changedElsewhere)
        #expect(try #require(find("Onion", .atHome)).quantity == 7)
    }

    // MARK: - 4.5 adjustQuantity

    @Test("Quantity adjusts up and down in both locations")
    func adjustQuantityBothLocations() throws {
        let listRow = add("Milk", 1, .shoppingList)
        let homeRow = add("Bread", 4, .atHome)

        GroceryStore.adjustQuantity(listRow, by: 2, context: context)
        GroceryStore.adjustQuantity(homeRow, by: -1, context: context)

        #expect(try #require(find("Milk", .shoppingList)).quantity == 3)
        #expect(try #require(find("Bread", .atHome)).quantity == 3)
        assertNoZeroQuantityRows("adjusting never leaves a zero row")
    }

    @Test("Decrementing to zero deletes the row rather than storing a zero")
    func decrementToZeroDeletesRow() throws {
        let milk = add("Milk", 1, .atHome)

        GroceryStore.adjustQuantity(milk, by: -1, context: context)

        #expect(find("Milk", .atHome) == nil)
        #expect(items(in: .atHome).isEmpty)
        assertNoZeroQuantityRows("decrement-to-zero must delete, not store 0")
    }

    @Test("Overshooting the decrement also deletes and never stores a negative")
    func decrementBelowZeroDeletesRow() throws {
        let milk = add("Milk", 2, .shoppingList)

        GroceryStore.adjustQuantity(milk, by: -5, context: context)

        #expect(find("Milk", .shoppingList) == nil)
        assertNoZeroQuantityRows("an overshooting decrement must not store a negative")
    }

    // MARK: - 4.6 Move to Shopping List

    @Test("Moving back with no matching list row returns the same row to the list")
    func moveBackWithoutMatch() throws {
        let onion = add("Onion", 3, .atHome)

        GroceryStore.moveBackToShoppingList(onion, context: context)

        #expect(items(in: .atHome).isEmpty)
        #expect(try #require(find("Onion", .shoppingList)).quantity == 3)
    }

    @Test("Moving back merges into a matching list row by normalized name")
    func moveBackMergesIntoExistingListRow() throws {
        add("Onions", 1, .shoppingList)
        let homeRow = add("onion", 3, .atHome)

        GroceryStore.moveBackToShoppingList(homeRow, context: context)

        #expect(items(in: .atHome).isEmpty)
        #expect(items(in: .shoppingList).count == 1)
        #expect(try #require(find("Onion", .shoppingList)).quantity == 4)
    }

    // MARK: - 4.7 Duplicate detection

    @Test("Normalized-name matching reports the at-home row that feeds the warning")
    func duplicateDetectionMatchesOnNormalizedName() throws {
        add("Onions", 2, .atHome)

        // The warning's input: differing case, punctuation, and plural still match.
        #expect(find("onion", .atHome)?.quantity == 2)
        #expect(find("  ONION  ", .atHome)?.quantity == 2)
        // Exact normalized equality only — no fuzzy matching.
        #expect(find("green onion", .atHome) == nil)
    }

    @Test("A duplicate warning never blocks the add")
    func duplicateNeverBlocksTheAdd() throws {
        add("Onion", 2, .atHome)

        // "Add Anyway" is just the ordinary add path; the at-home row is untouched.
        let added = add("Onion", 1, .shoppingList)

        #expect(added.quantity == 1)
        #expect(try #require(find("Onion", .atHome)).quantity == 2)
        #expect(items(in: .shoppingList).count == 1)
    }

    @Test("Adding a name already on the list merges rather than duplicating")
    func addMergesWithinTheSameLocation() throws {
        add("Onion", 2, .shoppingList)
        add("onions", 3, .shoppingList)

        #expect(items(in: .shoppingList).count == 1)
        #expect(try #require(find("Onion", .shoppingList)).quantity == 5)
    }
}

/// A second device installing fresh finds an empty local store, invents a
/// household, and only *then* receives the real one from CloudKit. Until
/// 2026-09-09 the invented household stayed active forever, so the device
/// showed an empty list while the synced items sat unreachable in the same
/// store — the failure that deferred task 10.1 existed to catch.
@MainActor
struct ActiveHouseholdAdoptionTests {

    /// Stands in for a household arriving by CloudKit import: same store, an
    /// earlier creation date, and items attached.
    private func insertSyncedHousehold(into controller: PersistenceController,
                                       named item: String) -> Household {
        let context = controller.container.viewContext
        let household = Household(context: context)
        household.id = UUID()
        household.createdAt = Date(timeIntervalSince1970: 0)
        GroceryItem.create(name: item, quantity: 1, location: .shoppingList,
                           household: household, in: context)
        try? context.save()
        return household
    }

    @Test("A fresh install marks its invented household provisional")
    func freshInstallFlagsItsOwnHousehold() {
        let controller = PersistenceController(inMemory: true)
        #expect(controller.activeHouseholdWasAutoCreated)
    }

    @Test("The synced household is adopted once it arrives")
    func adoptsSyncedHousehold() throws {
        let controller = PersistenceController(inMemory: true)
        let invented = try #require(controller.activeHousehold)

        let synced = insertSyncedHousehold(into: controller, named: "Broccoli")
        #expect(controller.adoptSyncedHouseholdIfPresent())

        #expect(controller.activeHousehold == synced)
        #expect(!controller.activeHouseholdWasAutoCreated)
        #expect(invented.isDeleted || invented.managedObjectContext == nil,
                "the empty invented household is cleaned up, not left to sync")
    }

    @Test("Adoption never strands items added before the first import")
    func keepsHouseholdThatAlreadyHasItems() throws {
        let controller = PersistenceController(inMemory: true)
        let invented = try #require(controller.activeHousehold)
        // The user added something on this device before the import landed.
        GroceryStore.addItem(name: "Onion", quantity: 1, location: .shoppingList,
                             household: invented, context: controller.container.viewContext)

        _ = insertSyncedHousehold(into: controller, named: "Broccoli")

        #expect(!controller.adoptSyncedHouseholdIfPresent())
        #expect(controller.activeHousehold == invented)
    }

    @Test("A household the user actively chose is never swapped out")
    func doesNotAdoptOverAnExplicitChoice() throws {
        let controller = PersistenceController(inMemory: true)
        let chosen = try #require(controller.activeHousehold)
        controller.activate(chosen)          // an explicit choice clears the flag
        _ = insertSyncedHousehold(into: controller, named: "Broccoli")

        #expect(!controller.adoptSyncedHouseholdIfPresent())
        #expect(controller.activeHousehold == chosen)
    }
}
