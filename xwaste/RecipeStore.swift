import CoreData

/// One ingredient row as the editor collects it, before merging and ordering.
struct RecipeIngredientDraft {
    var name: String
    var quantity: Int64
}

/// One step row as the editor collects it, before dropping blanks and ordering.
struct RecipeStepDraft {
    var text: String
}

struct RecipeIngredientSnapshot {
    let name: String
    let quantity: Int64
}

struct RecipeStepSnapshot {
    let text: String
}

/// Snapshot of a deleted recipe, held in view state, that `undoDelete`
/// recreates the graph from. A value type rather than `UndoManager` for the
/// same reason as `CheckOffUndo`: a visible affordance, and cascade deletion
/// means the managed objects themselves are gone by the time undo runs.
struct RecipeSnapshot {
    let name: String
    let summary: String
    let imageData: Data?
    let ingredients: [RecipeIngredientSnapshot]
    let steps: [RecipeStepSnapshot]
    let householdID: NSManagedObjectID
}

enum CookOutcome: Equatable {
    /// The home row survived at this quantity; undo verifies it still does
    /// before adding the delta back.
    case reduced(expected: Int64)
    /// Consuming the ingredient took the home row to zero or below, deleting
    /// it; undo verifies the row is still absent before recreating it.
    case removed
}

/// One ingredient's contribution to a cook, recorded so undo can verify
/// before reversing — the same discipline as `CheckOffUndo`.
struct CookLine {
    let name: String
    let normalizedName: String
    let category: GroceryCategory
    let categoryIsManual: Bool
    let delta: Int64
    let outcome: CookOutcome
}

/// Snapshot of a Finish Cooking action, held in view state until the undo
/// banner expires or is used.
struct CookUndo {
    let recipeName: String
    let householdID: NSManagedObjectID
    let lines: [CookLine]
}

enum UndoConsumeResult: Equatable {
    case reversed
    /// One or more lines were left untouched because the home row had
    /// changed since the cook (edited, used up, or re-added by someone else).
    /// Names the affected ingredients so the banner can say so.
    case partiallyReversed(changedElsewhere: [String])
}

/// Every recipe mutation that touches more than one row lives here, mirroring
/// `GroceryStore`'s shape: value-snapshot undo, verify-before-reverse, no
/// zero-quantity rows anywhere it touches `GroceryItem`.
enum RecipeStore {

    // MARK: - Create / update

    /// The only way to construct a recipe. Returns nil for a blank name — the
    /// same rule the editor's disabled Save button enforces, held here too so
    /// no caller can create a nameless recipe.
    @discardableResult
    static func create(name: String,
                       summary: String,
                       imageData: Data?,
                       ingredients: [RecipeIngredientDraft],
                       steps: [RecipeStepDraft],
                       household: Household,
                       context: NSManagedObjectContext) -> Recipe? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let recipe = Recipe(context: context)
        recipe.name = trimmedName
        recipe.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.imageData = imageData
        recipe.createdAt = Date()
        recipe.household = household
        applyIngredients(ingredients, to: recipe, context: context)
        applySteps(steps, to: recipe, context: context)
        save(context)
        return recipe
    }

    /// Replaces ingredients and steps wholesale — simpler and safer than
    /// diffing rows against drafts, and the editor already displays every row
    /// so nothing is lost from the user's point of view. A blank name is a
    /// no-op, matching `create`.
    static func update(_ recipe: Recipe,
                       name: String,
                       summary: String,
                       imageData: Data?,
                       ingredients: [RecipeIngredientDraft],
                       steps: [RecipeStepDraft],
                       context: NSManagedObjectContext) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        recipe.name = trimmedName
        recipe.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.imageData = imageData
        for ingredient in recipe.orderedIngredients { context.delete(ingredient) }
        for step in recipe.orderedSteps { context.delete(step) }
        applyIngredients(ingredients, to: recipe, context: context)
        applySteps(steps, to: recipe, context: context)
        save(context)
    }

    /// Drops blank rows, then merges rows whose trimmed name normalizes alike
    /// — the same rule `GroceryStore` enforces for the inventory — summing
    /// their counts and keeping the first row's display name and position.
    private static func applyIngredients(_ drafts: [RecipeIngredientDraft],
                                         to recipe: Recipe,
                                         context: NSManagedObjectContext) {
        struct Merged { var name: String; var normalized: String; var quantity: Int64 }
        var merged: [Merged] = []
        var indexByNormalized: [String: Int] = [:]

        for draft in drafts {
            let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }
            let normalized = GroceryItem.normalize(trimmedName)
            guard !normalized.isEmpty else { continue }

            if let index = indexByNormalized[normalized] {
                merged[index].quantity += max(1, draft.quantity)
            } else {
                indexByNormalized[normalized] = merged.count
                merged.append(Merged(name: trimmedName, normalized: normalized, quantity: max(1, draft.quantity)))
            }
        }

        for (index, entry) in merged.enumerated() {
            let ingredient = RecipeIngredient(context: context)
            ingredient.name = entry.name
            ingredient.normalizedName = entry.normalized
            ingredient.quantity = entry.quantity
            ingredient.orderIndex = Int64(index)
            ingredient.recipe = recipe
        }
    }

    private static func applySteps(_ drafts: [RecipeStepDraft],
                                   to recipe: Recipe,
                                   context: NSManagedObjectContext) {
        var index: Int64 = 0
        for draft in drafts {
            let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let step = RecipeStep(context: context)
            step.text = trimmed
            step.orderIndex = index
            step.recipe = recipe
            index += 1
        }
    }

    // MARK: - Delete / undo

    /// Cascade handles the children; the snapshot is taken before the delete
    /// so `undoDelete` can rebuild the graph in order.
    @discardableResult
    static func delete(_ recipe: Recipe, context: NSManagedObjectContext) -> RecipeSnapshot? {
        guard let household = recipe.household else { return nil }
        let snapshot = RecipeSnapshot(
            name: recipe.displayName,
            summary: recipe.summary ?? "",
            imageData: recipe.imageData,
            ingredients: recipe.orderedIngredients.map {
                RecipeIngredientSnapshot(name: $0.displayName, quantity: $0.quantity)
            },
            steps: recipe.orderedSteps.map { RecipeStepSnapshot(text: $0.displayText) },
            householdID: household.objectID
        )
        context.delete(recipe)
        save(context)
        return snapshot
    }

    @discardableResult
    static func undoDelete(_ snapshot: RecipeSnapshot, context: NSManagedObjectContext) -> Recipe? {
        guard let household = (try? context.existingObject(with: snapshot.householdID)) as? Household else {
            return nil
        }
        let recipe = Recipe(context: context)
        recipe.name = snapshot.name
        recipe.summary = snapshot.summary
        recipe.imageData = snapshot.imageData
        recipe.createdAt = Date()
        recipe.household = household

        for (index, ingredient) in snapshot.ingredients.enumerated() {
            let row = RecipeIngredient(context: context)
            row.name = ingredient.name
            row.normalizedName = GroceryItem.normalize(ingredient.name)
            row.quantity = ingredient.quantity
            row.orderIndex = Int64(index)
            row.recipe = recipe
        }
        for (index, step) in snapshot.steps.enumerated() {
            let row = RecipeStep(context: context)
            row.text = step.text
            row.orderIndex = Int64(index)
            row.recipe = recipe
        }
        save(context)
        return recipe
    }

    // MARK: - Cooking

    /// `checkOff` in reverse: decrements each ingredient's matching At Home
    /// row by the recipe's count via the same delete-at-zero rule
    /// `GroceryStore.setQuantity` enforces. An ingredient with no matching
    /// home row is skipped entirely — nothing to consume, nothing to undo.
    static func consume(_ recipe: Recipe, context: NSManagedObjectContext) -> CookUndo? {
        guard let household = recipe.household else { return nil }
        var lines: [CookLine] = []

        for ingredient in recipe.orderedIngredients {
            guard let normalized = ingredient.normalizedName, !normalized.isEmpty,
                  let home = GroceryStore.findItem(normalizedName: normalized, location: .atHome,
                                                   household: household, in: context) else {
                continue
            }
            let name = home.displayName
            let category = home.category
            let categoryIsManual = home.categoryIsManual
            let delta = ingredient.quantity
            let remaining = home.quantity - delta
            let outcome: CookOutcome = remaining <= 0 ? .removed : .reduced(expected: remaining)

            GroceryStore.setQuantity(home, to: remaining, context: context)
            lines.append(CookLine(name: name, normalizedName: normalized, category: category,
                                  categoryIsManual: categoryIsManual, delta: delta, outcome: outcome))
        }

        guard !lines.isEmpty else { return nil }
        return CookUndo(recipeName: recipe.displayName, householdID: household.objectID, lines: lines)
    }

    /// Per-line verification, exactly `undoCheckOff`'s discipline: a line
    /// whose home row does not match its recorded post-cook state is left
    /// alone and reported, never blindly reversed.
    static func undoConsume(_ undo: CookUndo, context: NSManagedObjectContext) -> UndoConsumeResult {
        guard let household = (try? context.existingObject(with: undo.householdID)) as? Household else {
            return .partiallyReversed(changedElsewhere: undo.lines.map(\.name))
        }

        var changedElsewhere: [String] = []
        for line in undo.lines {
            let home = GroceryStore.findItem(normalizedName: line.normalizedName, location: .atHome,
                                             household: household, in: context)
            switch line.outcome {
            case .reduced(let expected):
                guard let home, home.quantity == expected else {
                    changedElsewhere.append(line.name)
                    continue
                }
                GroceryStore.adjustQuantity(home, by: line.delta, context: context)
            case .removed:
                guard home == nil else {
                    changedElsewhere.append(line.name)
                    continue
                }
                let recreated = GroceryItem(context: context)
                recreated.name = line.name
                recreated.normalizedName = line.normalizedName
                recreated.quantity = line.delta
                recreated.category = line.category
                recreated.categoryIsManual = line.categoryIsManual
                recreated.location = .atHome
                recreated.createdAt = Date()
                recreated.household = household
            }
        }
        save(context)
        return changedElsewhere.isEmpty ? .reversed : .partiallyReversed(changedElsewhere: changedElsewhere)
    }

    // MARK: - Add missing to shopping list

    /// Raises each short ingredient's shopping-list row to `max(current,
    /// shortfall)` rather than adding on top — idempotent, and never buys
    /// more than the recipe needs. No duplicate warning: the shortfall is
    /// already computed from at-home stock, the fact the warning exists to
    /// surface. Returns the ingredient names actually changed, for the
    /// confirmation banner.
    static func addMissingToShoppingList(_ recipe: Recipe,
                                         inventory: [String: Int64],
                                         context: NSManagedObjectContext) -> [String] {
        guard let household = recipe.household else { return [] }
        let status = RecipeAvailability.evaluate(recipe: recipe, inventory: inventory)
        var added: [String] = []

        for ingredientStatus in status.ingredients where ingredientStatus.isShort {
            let ingredient = ingredientStatus.ingredient
            guard let normalized = ingredient.normalizedName, !normalized.isEmpty else { continue }
            let shortfall = ingredientStatus.shortfall

            if let existing = GroceryStore.findItem(normalizedName: normalized, location: .shoppingList,
                                                    household: household, in: context) {
                guard existing.quantity < shortfall else { continue }
                GroceryStore.setQuantity(existing, to: shortfall, context: context)
            } else {
                GroceryStore.addItem(name: ingredient.displayName, quantity: shortfall,
                                     location: .shoppingList, household: household, context: context)
            }
            added.append(ingredient.displayName)
        }
        return added
    }

    // MARK: - Private

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
