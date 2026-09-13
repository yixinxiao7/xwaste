import CoreData
import Foundation

/// Launch-time seams the UI-test suites drive, shared by the iOS and watch
/// apps. Both suites need the same thing: a store whose contents they chose,
/// rather than whatever CloudKit happens to have delivered to that simulator.
/// All of it is `#if DEBUG`, so none of it exists in a shipping build.
enum LaunchSupport {
    static let seedEnvironmentKey = "XWASTE_UITEST_SEED"
    static let accountStatusEnvironmentKey = "XWASTE_ACCOUNT_STATUS"
    static let confirmationSecondsEnvironmentKey = "XWASTE_CONFIRMATION_SECONDS"

    /// The real, CloudKit-backed stack — unless a suite asked for a seeded one.
    static func makePersistenceController() -> PersistenceController {
        #if DEBUG
        if let seed = ProcessInfo.processInfo.environment[seedEnvironmentKey] {
            return seededController(seed: seed)
        }
        #endif
        return PersistenceController.shared
    }

    /// The spec floor is "at least five seconds", which is also the shipping
    /// value. A suite may widen it so a slow simulator cannot lose the race to
    /// the auto-dismiss and report a flake as a regression.
    static var confirmationDuration: Duration {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment[confirmationSecondsEnvironmentKey],
           let seconds = Double(raw) {
            return .seconds(seconds)
        }
        #endif
        return .seconds(5)
    }

    #if DEBUG
    /// Fixed rows spanning two categories, so a suite can assert section order,
    /// check-off, undo, decrement-to-zero, and the duplicate warning against
    /// known values. Seed "0" yields an empty store — the cold-launch case.
    private static func seededController(seed: String) -> PersistenceController {
        let controller = PersistenceController(inMemory: true)
        guard seed == "1" else { return controller }
        let context = controller.container.viewContext
        let household: Household = controller.activeHousehold
        GroceryItem.create(name: "Broccoli", quantity: 1, location: .shoppingList, household: household, in: context)
        GroceryItem.create(name: "Onion", quantity: 2, location: .shoppingList, household: household, in: context)
        GroceryItem.create(name: "Milk", quantity: 1, location: .shoppingList, household: household, in: context)
        GroceryItem.create(name: "Butter", quantity: 1, location: .atHome, household: household, in: context)
        // Recipes: one cookable with the seeded Butter, one short on the
        // seeded Onion (which is on the list, not at home) — no new items.
        RecipeStore.create(name: "Buttered Toast", summary: "A quick, warm snack.", imageData: nil,
                           ingredients: [RecipeIngredientDraft(name: "Butter", quantity: 1)],
                           steps: [RecipeStepDraft(text: "Toast the bread."),
                                   RecipeStepDraft(text: "Spread the butter.")],
                           household: household, context: context)
        RecipeStore.create(name: "Onion Soup", summary: "Simple and savory.", imageData: nil,
                           ingredients: [RecipeIngredientDraft(name: "Onion", quantity: 3),
                                        RecipeIngredientDraft(name: "Butter", quantity: 1)],
                           steps: [RecipeStepDraft(text: "Slice the onions."),
                                   RecipeStepDraft(text: "Cook in butter until soft."),
                                   RecipeStepDraft(text: "Simmer and serve.")],
                           household: household, context: context)
        try? context.save()
        return controller
    }
    #endif
}
