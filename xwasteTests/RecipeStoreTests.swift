import Testing
import CoreData
@testable import xwaste

@MainActor
struct RecipeStoreTests {

    let context: NSManagedObjectContext
    let household: Household

    init() {
        let controller = PersistenceController(inMemory: true)
        context = controller.container.viewContext
        household = controller.activeHousehold
    }

    private func homeItem(_ name: String, _ quantity: Int64) -> GroceryItem {
        GroceryItem.create(name: name, quantity: quantity, location: .atHome, household: household, in: context)
    }

    private func listItem(_ name: String, _ quantity: Int64) -> GroceryItem {
        GroceryItem.create(name: name, quantity: quantity, location: .shoppingList, household: household, in: context)
    }

    private func find(_ name: String, _ location: ItemLocation) -> GroceryItem? {
        GroceryStore.findItem(normalizedName: GroceryItem.normalize(name), location: location,
                              household: household, in: context)
    }

    // MARK: - 3.2 Create

    @Test("Create merges duplicate ingredient rows, keeping the first name and position")
    func createMergesDuplicateIngredients() throws {
        let recipe = try #require(RecipeStore.create(
            name: "Soup", summary: "", imageData: nil,
            ingredients: [
                RecipeIngredientDraft(name: "Onion", quantity: 1),
                RecipeIngredientDraft(name: "Carrot", quantity: 1),
                RecipeIngredientDraft(name: "onions", quantity: 2),
            ],
            steps: [], household: household, context: context))

        let ingredients = recipe.orderedIngredients
        #expect(ingredients.count == 2)
        #expect(ingredients[0].displayName == "Onion")
        #expect(ingredients[0].quantity == 3)
        #expect(ingredients[1].displayName == "Carrot")
    }

    @Test("Create drops blank ingredient and step rows and preserves order")
    func createDropsBlankRows() throws {
        let recipe = try #require(RecipeStore.create(
            name: "Toast", summary: "", imageData: nil,
            ingredients: [
                RecipeIngredientDraft(name: "Bread", quantity: 1),
                RecipeIngredientDraft(name: "   ", quantity: 1),
                RecipeIngredientDraft(name: "Butter", quantity: 1),
            ],
            steps: [
                RecipeStepDraft(text: "Toast the bread"),
                RecipeStepDraft(text: ""),
                RecipeStepDraft(text: "Spread butter"),
            ],
            household: household, context: context))

        #expect(recipe.orderedIngredients.map(\.displayName) == ["Bread", "Butter"])
        #expect(recipe.orderedSteps.map(\.displayText) == ["Toast the bread", "Spread butter"])
    }

    @Test("Create rejects a blank name")
    func createRejectsBlankName() {
        let recipe = RecipeStore.create(name: "   ", summary: "", imageData: nil,
                                        ingredients: [], steps: [], household: household, context: context)
        #expect(recipe == nil)
    }

    // MARK: - 3.3 Update

    @Test("Update replaces ingredients and steps wholesale, keeping identity and image")
    func updateReplacesChildrenWholesale() throws {
        let imageBytes = Data([0x01, 0x02])
        let recipe = try #require(RecipeStore.create(
            name: "Soup", summary: "Original", imageData: imageBytes,
            ingredients: [RecipeIngredientDraft(name: "Onion", quantity: 1)],
            steps: [RecipeStepDraft(text: "Chop")],
            household: household, context: context))
        let objectID = recipe.objectID

        RecipeStore.update(recipe, name: "Soup", summary: "Updated", imageData: imageBytes,
                           ingredients: [RecipeIngredientDraft(name: "Carrot", quantity: 2)],
                           steps: [RecipeStepDraft(text: "Simmer")],
                           context: context)

        #expect(recipe.objectID == objectID)
        #expect(recipe.summary == "Updated")
        #expect(recipe.imageData == imageBytes)
        #expect(recipe.orderedIngredients.map(\.displayName) == ["Carrot"])
        #expect(recipe.orderedSteps.map(\.displayText) == ["Simmer"])
    }

    @Test("Removing the image on update clears imageData")
    func updateClearsImage() throws {
        let recipe = try #require(RecipeStore.create(
            name: "Soup", summary: "", imageData: Data([0x01]),
            ingredients: [], steps: [], household: household, context: context))

        RecipeStore.update(recipe, name: "Soup", summary: "", imageData: nil,
                           ingredients: [], steps: [], context: context)

        #expect(recipe.imageData == nil)
    }

    // MARK: - 3.4 Delete / undoDelete

    @Test("Delete returns a complete snapshot and undoDelete restores it in order")
    func deleteAndUndoDeleteRoundTrip() throws {
        let recipe = try #require(RecipeStore.create(
            name: "Soup", summary: "Warming", imageData: Data([0xAB]),
            ingredients: [
                RecipeIngredientDraft(name: "Onion", quantity: 2),
                RecipeIngredientDraft(name: "Carrot", quantity: 1),
            ],
            steps: [RecipeStepDraft(text: "Chop"), RecipeStepDraft(text: "Simmer")],
            household: household, context: context))

        let snapshot = try #require(RecipeStore.delete(recipe, context: context))
        #expect(snapshot.name == "Soup")
        #expect(snapshot.summary == "Warming")
        #expect(snapshot.imageData == Data([0xAB]))
        #expect(snapshot.ingredients.map(\.name) == ["Onion", "Carrot"])
        #expect(snapshot.steps.map(\.text) == ["Chop", "Simmer"])

        let allRecipes = (try? context.fetch(Recipe.fetchRequest())) ?? []
        #expect(allRecipes.isEmpty)

        let restored = try #require(RecipeStore.undoDelete(snapshot, context: context))
        #expect(restored.displayName == "Soup")
        #expect(restored.household == household)
        #expect(restored.orderedIngredients.map(\.displayName) == ["Onion", "Carrot"])
        #expect(restored.orderedSteps.map(\.displayText) == ["Chop", "Simmer"])
    }

    // MARK: - 3.5 Consume

    @Test("Consume reduces matching rows, deletes at zero, and skips absent rows")
    func consumeReducesAndSkips() throws {
        homeItem("Onion", 5)
        homeItem("Butter", 1)
        let recipe = try #require(RecipeStore.create(
            name: "Soup", summary: "", imageData: nil,
            ingredients: [
                RecipeIngredientDraft(name: "Onion", quantity: 2),
                RecipeIngredientDraft(name: "Butter", quantity: 1),
                RecipeIngredientDraft(name: "Flour", quantity: 1),
            ],
            steps: [], household: household, context: context))

        let undo = try #require(RecipeStore.consume(recipe, context: context))

        #expect(try #require(find("Onion", .atHome)).quantity == 3)
        #expect(find("Butter", .atHome) == nil)
        #expect(undo.lines.count == 2, "the absent ingredient (Flour) produces no line")
        #expect(undo.recipeName == "Soup")
    }

    @Test("Consume leaves shopping-list rows untouched")
    func consumeLeavesShoppingListAlone() throws {
        homeItem("Onion", 3)
        listItem("Onion", 2)
        let recipe = try #require(RecipeStore.create(
            name: "Soup", summary: "", imageData: nil,
            ingredients: [RecipeIngredientDraft(name: "Onion", quantity: 1)],
            steps: [], household: household, context: context))

        _ = RecipeStore.consume(recipe, context: context)

        #expect(try #require(find("Onion", .shoppingList)).quantity == 2)
    }

    // MARK: - 3.6 Undo consume

    @Test("Undo consume fully reverses, recreating a removed row with its category and manual flag")
    func undoConsumeFullyReverses() throws {
        let butter = homeItem("Butter", 1)
        GroceryStore.setCategory(butter, to: .dairyAndEggs, context: context)
        let recipe = try #require(RecipeStore.create(
            name: "Toast", summary: "", imageData: nil,
            ingredients: [RecipeIngredientDraft(name: "Butter", quantity: 1)],
            steps: [], household: household, context: context))
        let undo = try #require(RecipeStore.consume(recipe, context: context))
        #expect(find("Butter", .atHome) == nil)

        #expect(RecipeStore.undoConsume(undo, context: context) == .reversed)

        let restored = try #require(find("Butter", .atHome))
        #expect(restored.quantity == 1)
        #expect(restored.category == .dairyAndEggs)
        #expect(restored.categoryIsManual)
    }

    @Test("A row changed elsewhere since the cook is left as-is and reported")
    func undoConsumeReportsChangedElsewhere() throws {
        homeItem("Onion", 5)
        let recipe = try #require(RecipeStore.create(
            name: "Soup", summary: "", imageData: nil,
            ingredients: [RecipeIngredientDraft(name: "Onion", quantity: 2)],
            steps: [], household: household, context: context))
        let undo = try #require(RecipeStore.consume(recipe, context: context))
        // Someone else uses one up before Undo is tapped.
        GroceryStore.adjustQuantity(try #require(find("Onion", .atHome)), by: -1, context: context)

        #expect(RecipeStore.undoConsume(undo, context: context) == .partiallyReversed(changedElsewhere: ["Onion"]))
        #expect(try #require(find("Onion", .atHome)).quantity == 2)
    }

    @Test("A removed row re-added by someone else is left at its new quantity and reported")
    func undoConsumeReportsRowReaddedElsewhere() throws {
        homeItem("Butter", 1)
        let recipe = try #require(RecipeStore.create(
            name: "Toast", summary: "", imageData: nil,
            ingredients: [RecipeIngredientDraft(name: "Butter", quantity: 1)],
            steps: [], household: household, context: context))
        let undo = try #require(RecipeStore.consume(recipe, context: context))
        // Someone re-adds Butter before Undo is tapped.
        GroceryStore.addItem(name: "Butter", quantity: 4, location: .atHome, household: household, context: context)

        #expect(RecipeStore.undoConsume(undo, context: context) == .partiallyReversed(changedElsewhere: ["Butter"]))
        #expect(try #require(find("Butter", .atHome)).quantity == 4)
    }

    @Test("An unused undo changes nothing")
    func unusedUndoChangesNothing() throws {
        homeItem("Onion", 3)
        let recipe = try #require(RecipeStore.create(
            name: "Soup", summary: "", imageData: nil,
            ingredients: [RecipeIngredientDraft(name: "Onion", quantity: 1)],
            steps: [], household: household, context: context))
        _ = try #require(RecipeStore.consume(recipe, context: context))

        // The banner's window lapsing simply discards the CookUndo.
        #expect(try #require(find("Onion", .atHome)).quantity == 2)
    }

    // MARK: - 3.7 Add missing to shopping list

    private func inventory() -> [String: Int64] {
        let request = GroceryItem.fetchRequest()
        request.predicate = NSPredicate(format: "locationRawValue == %@ AND household == %@",
                                        ItemLocation.atHome.rawValue, household)
        let items = (try? context.fetch(request)) ?? []
        return RecipeAvailability.inventory(from: items)
    }

    @Test("Add missing creates rows with the shortfall and automatic category")
    func addMissingCreatesRows() throws {
        let recipe = try #require(RecipeStore.create(
            name: "Soup", summary: "", imageData: nil,
            ingredients: [RecipeIngredientDraft(name: "Onion", quantity: 3)],
            steps: [], household: household, context: context))

        let added = RecipeStore.addMissingToShoppingList(recipe, inventory: inventory(), context: context)

        #expect(added == ["Onion"])
        let row = try #require(find("Onion", .shoppingList))
        #expect(row.quantity == 3)
        #expect(!row.categoryIsManual)
    }

    @Test("A second call changes nothing")
    func addMissingSecondCallIsNoOp() throws {
        let recipe = try #require(RecipeStore.create(
            name: "Soup", summary: "", imageData: nil,
            ingredients: [RecipeIngredientDraft(name: "Onion", quantity: 3)],
            steps: [], household: household, context: context))
        _ = RecipeStore.addMissingToShoppingList(recipe, inventory: inventory(), context: context)

        let added = RecipeStore.addMissingToShoppingList(recipe, inventory: inventory(), context: context)

        #expect(added.isEmpty)
        #expect(try #require(find("Onion", .shoppingList)).quantity == 3)
    }

    @Test("Partial list coverage is topped up, not added on top")
    func addMissingTopsUpPartialCoverage() throws {
        listItem("Onion", 1)
        let recipe = try #require(RecipeStore.create(
            name: "Soup", summary: "", imageData: nil,
            ingredients: [RecipeIngredientDraft(name: "Onion", quantity: 3)],
            steps: [], household: household, context: context))

        let added = RecipeStore.addMissingToShoppingList(recipe, inventory: inventory(), context: context)

        #expect(added == ["Onion"])
        #expect(try #require(find("Onion", .shoppingList)).quantity == 3)
    }

    @Test("A list row already covering the shortfall is untouched")
    func addMissingLeavesCoveringRowAlone() throws {
        listItem("Onion", 5)
        let recipe = try #require(RecipeStore.create(
            name: "Soup", summary: "", imageData: nil,
            ingredients: [RecipeIngredientDraft(name: "Onion", quantity: 3)],
            steps: [], household: household, context: context))

        let added = RecipeStore.addMissingToShoppingList(recipe, inventory: inventory(), context: context)

        #expect(added.isEmpty)
        #expect(try #require(find("Onion", .shoppingList)).quantity == 5)
    }

    @Test("A cookable recipe adds nothing")
    func addMissingOnCookableRecipeAddsNothing() throws {
        homeItem("Onion", 3)
        let recipe = try #require(RecipeStore.create(
            name: "Soup", summary: "", imageData: nil,
            ingredients: [RecipeIngredientDraft(name: "Onion", quantity: 3)],
            steps: [], household: household, context: context))

        let added = RecipeStore.addMissingToShoppingList(recipe, inventory: inventory(), context: context)

        #expect(added.isEmpty)
        #expect(find("Onion", .shoppingList) == nil)
    }
}
