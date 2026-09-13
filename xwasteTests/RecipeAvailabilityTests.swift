import Testing
import CoreData
@testable import xwaste

/// `RecipeAvailability` is a pure function over an inventory dictionary — no
/// Core Data mutation, so these tests just build fetched-style rows in memory.
@MainActor
struct RecipeAvailabilityTests {

    let context: NSManagedObjectContext
    let household: Household

    init() {
        let controller = PersistenceController(inMemory: true)
        context = controller.container.viewContext
        household = controller.activeHousehold
    }

    private func homeItem(_ name: String, _ quantity: Int64) -> GroceryItem {
        GroceryItem.create(name: name, quantity: quantity, location: .atHome,
                           household: household, in: context)
    }

    private func recipe(_ ingredients: [(String, Int64)]) -> Recipe {
        RecipeStore.create(name: "Test Recipe", summary: "", imageData: nil,
                           ingredients: ingredients.map { RecipeIngredientDraft(name: $0.0, quantity: $0.1) },
                           steps: [], household: household, context: context)!
    }

    @Test("Every ingredient covered by At Home is fully cookable")
    func everyIngredientCovered() {
        homeItem("Onion", 3)
        homeItem("Butter", 1)
        let recipe = recipe([("Onion", 2), ("Butter", 1)])

        let status = RecipeAvailability.evaluate(recipe: recipe, inventory: RecipeAvailability.inventory(from: homeItemsFetch()))

        #expect(status.canMake)
        #expect(status.ingredients.allSatisfy { !$0.isShort })
    }

    @Test("An ingredient short by count is flagged with its shortfall")
    func ingredientShortByCount() {
        homeItem("Onion", 1)
        let recipe = recipe([("Onion", 3)])

        let status = RecipeAvailability.evaluate(recipe: recipe, inventory: RecipeAvailability.inventory(from: homeItemsFetch()))

        #expect(!status.canMake)
        #expect(status.ingredients.first?.shortfall == 2)
    }

    @Test("An ingredient absent from At Home is short by its full count")
    func ingredientAbsent() {
        let recipe = recipe([("Flour", 2)])

        let status = RecipeAvailability.evaluate(recipe: recipe, inventory: RecipeAvailability.inventory(from: homeItemsFetch()))

        #expect(!status.canMake)
        #expect(status.ingredients.first?.shortfall == 2)
    }

    @Test("A recipe with zero ingredients can always be made")
    func zeroIngredientsCanAlwaysBeMade() {
        let recipe = recipe([])

        let status = RecipeAvailability.evaluate(recipe: recipe, inventory: RecipeAvailability.inventory(from: homeItemsFetch()))

        #expect(status.canMake)
        #expect(status.ingredients.isEmpty)
    }

    @Test("\"onions\" in a recipe matches \"Onion\" at home via normalized name")
    func pluralMatchesSingular() {
        homeItem("Onion", 5)
        let recipe = recipe([("onions", 2)])

        let status = RecipeAvailability.evaluate(recipe: recipe, inventory: RecipeAvailability.inventory(from: homeItemsFetch()))

        #expect(status.canMake)
    }

    @Test("Shopping-list rows are ignored — only At Home stock counts")
    func shoppingListRowsIgnored() {
        GroceryItem.create(name: "Onion", quantity: 5, location: .shoppingList, household: household, in: context)
        let recipe = recipe([("Onion", 1)])

        // Inventory is built only from At Home rows, per the contract.
        let status = RecipeAvailability.evaluate(recipe: recipe, inventory: RecipeAvailability.inventory(from: homeItemsFetch()))

        #expect(!status.canMake)
        #expect(status.ingredients.first?.shortfall == 1)
    }

    private func homeItemsFetch() -> [GroceryItem] {
        let request = GroceryItem.fetchRequest()
        request.predicate = NSPredicate(format: "locationRawValue == %@ AND household == %@",
                                        ItemLocation.atHome.rawValue, household)
        return (try? context.fetch(request)) ?? []
    }
}
