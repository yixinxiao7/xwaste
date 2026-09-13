import XCTest

/// Drives the Recipes tab against the extended seed (task 4.8): "Buttered
/// Toast" (Butter ×1, cookable against the seeded Butter ×1 at home) and
/// "Onion Soup" (Onion ×3 + Butter ×1, missing — the seeded Onion ×2 is on
/// the shopping list, not at home). No agent-drivable iOS simulator exists on
/// this machine (see `XWasteRegressionUITests`), so this suite is the only
/// verification path for the recipes flows.
final class RecipesUITests: XCTestCase {

    private static let timeout: TimeInterval = 20

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["XWASTE_UITEST_SEED"] = "1"
        app.launchEnvironment["XWASTE_CONFIRMATION_SECONDS"] = "120"
        app.launch()
        return app
    }

    private func openRecipesTab(_ app: XCUIApplication) {
        app.tabBars.buttons["Recipes"].firstMatch.tap()
    }

    // MARK: - 5.1 Tab and tiles

    func testRecipesTabShowsBothSeededTilesInNameOrder() {
        let app = launch()
        openRecipesTab(app)

        let toast = app.staticTexts["Buttered Toast"]
        let soup = app.staticTexts["Onion Soup"]
        XCTAssertTrue(toast.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(soup.exists)
        // Name order: "Buttered Toast" sorts before "Onion Soup" — same row
        // in a two-column grid, so compare left-to-right position.
        if toast.frame.minY == soup.frame.minY {
            XCTAssertLessThan(toast.frame.minX, soup.frame.minX)
        } else {
            XCTAssertLessThan(toast.frame.minY, soup.frame.minY)
        }

        let placeholder = app.descendants(matching: .any).matching(identifier: "recipeTilePlaceholder").firstMatch
        XCTAssertTrue(placeholder.exists, "the placeholder shows for recipes with no photo")
    }

    // MARK: - 5.2 Filter

    func testFilterNarrowsToCanMakeOrMissing() {
        let app = launch()
        openRecipesTab(app)
        XCTAssertTrue(app.staticTexts["Buttered Toast"].waitForExistence(timeout: Self.timeout))

        app.buttons["Can Make"].tap()
        XCTAssertTrue(app.staticTexts["Buttered Toast"].waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.staticTexts["Onion Soup"].exists)

        app.buttons["Missing"].tap()
        XCTAssertTrue(app.staticTexts["Onion Soup"].waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.staticTexts["Buttered Toast"].exists)

        app.buttons["All"].tap()
        XCTAssertTrue(app.staticTexts["Buttered Toast"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["Onion Soup"].exists)
    }

    func testFilterWithNoMatchesShowsTheFilteredEmptyState() {
        let app = launch()
        openRecipesTab(app)
        XCTAssertTrue(app.staticTexts["Onion Soup"].waitForExistence(timeout: Self.timeout))

        // Delete the only cookable recipe so "Can Make" has nothing to show.
        app.staticTexts["Buttered Toast"].press(forDuration: 1.2)
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["Buttered Toast"].waitForExistence(timeout: 5))

        app.buttons["Can Make"].tap()
        XCTAssertTrue(app.staticTexts["No matching recipes"].waitForExistence(timeout: Self.timeout))
    }

    // MARK: - 5.3 Detail marks

    func testOnionSoupDetailShowsMissingMarksAndDisabledStartCooking() {
        let app = launch()
        openRecipesTab(app)
        XCTAssertTrue(app.staticTexts["Onion Soup"].waitForExistence(timeout: Self.timeout))

        app.staticTexts["Onion Soup"].tap()

        XCTAssertTrue(app.navigationBars["Onion Soup"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["Onion ×3"].exists)
        XCTAssertTrue(app.staticTexts["Butter ×1"].exists)
        XCTAssertTrue(app.images["Missing"].firstMatch.exists)

        let startCooking = app.buttons["Start Cooking"]
        XCTAssertTrue(startCooking.exists)
        XCTAssertFalse(startCooking.isEnabled)
        XCTAssertTrue(app.buttons["Add Missing to Shopping List"].exists)
    }

    // MARK: - 5.4 Add Missing (top-up)

    func testAddMissingTopsUpTheExistingListRowIdempotently() {
        let app = launch()
        openRecipesTab(app)
        XCTAssertTrue(app.staticTexts["Onion Soup"].waitForExistence(timeout: Self.timeout))
        app.staticTexts["Onion Soup"].tap()
        XCTAssertTrue(app.buttons["Add Missing to Shopping List"].waitForExistence(timeout: Self.timeout))

        app.buttons["Add Missing to Shopping List"].tap()
        XCTAssertTrue(app.staticTexts["Added Onion to the shopping list"].waitForExistence(timeout: Self.timeout))

        app.tabBars.buttons["Shopping List"].firstMatch.tap()
        let onionRow = app.cells.containing(.staticText, identifier: "Onion").firstMatch
        XCTAssertTrue(onionRow.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(onionRow.staticTexts["3"].exists, "the seeded Onion ×2 row is topped up to ×3")
        XCTAssertFalse(app.alerts.firstMatch.exists, "no duplicate-warning alert appears on this path")

        // Tapping again changes nothing (idempotent top-up). The Recipes
        // tab's NavigationStack still has "Onion Soup" pushed from above.
        openRecipesTab(app)
        XCTAssertTrue(app.buttons["Add Missing to Shopping List"].waitForExistence(timeout: Self.timeout))
        app.buttons["Add Missing to Shopping List"].tap()
        app.tabBars.buttons["Shopping List"].firstMatch.tap()
        XCTAssertTrue(app.cells.containing(.staticText, identifier: "Onion").firstMatch.staticTexts["3"].exists)
    }

    // MARK: - 5.5 Cooking session toggling and clean slate

    func testCookingSessionStartsUncheckedAndTogglesIndependently() {
        let app = launch()
        openRecipesTab(app)
        XCTAssertTrue(app.staticTexts["Buttered Toast"].waitForExistence(timeout: Self.timeout))
        app.staticTexts["Buttered Toast"].tap()
        XCTAssertTrue(app.buttons["Start Cooking"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.buttons["Start Cooking"].isEnabled)

        app.buttons["Start Cooking"].tap()
        let ingredientRow = app.buttons["Butter ×1"]
        let stepRow = app.buttons["Toast the bread."]
        XCTAssertTrue(ingredientRow.waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(ingredientRow.value as? String, "Unchecked")
        XCTAssertEqual(stepRow.value as? String, "Unchecked")

        ingredientRow.tap()
        stepRow.tap()
        XCTAssertEqual(ingredientRow.value as? String, "Checked")
        XCTAssertEqual(stepRow.value as? String, "Checked")

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Buttered Toast"].waitForExistence(timeout: Self.timeout))

        // Starting again shows a clean slate.
        app.buttons["Start Cooking"].tap()
        XCTAssertTrue(app.buttons["Butter ×1"].waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(app.buttons["Butter ×1"].value as? String, "Unchecked")
        app.buttons["Cancel"].tap()
    }

    // MARK: - 5.6 Finish Cooking and undo

    func testFinishCookingConsumesInventoryAndUndoRestoresIt() {
        let app = launch()
        openRecipesTab(app)
        XCTAssertTrue(app.staticTexts["Buttered Toast"].waitForExistence(timeout: Self.timeout))
        app.staticTexts["Buttered Toast"].tap()
        app.buttons["Start Cooking"].tap()
        XCTAssertTrue(app.buttons["Finish Cooking"].waitForExistence(timeout: Self.timeout))

        app.buttons["Finish Cooking"].tap()

        XCTAssertTrue(app.staticTexts["Cooked Buttered Toast"].waitForExistence(timeout: Self.timeout))
        app.tabBars.buttons["At Home"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["Butter"].waitForExistence(timeout: 5))

        // The Recipes tab's NavigationStack still has "Buttered Toast" pushed.
        app.tabBars.buttons["Recipes"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: Self.timeout))
        app.buttons["Undo"].tap()

        app.tabBars.buttons["At Home"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Butter"].waitForExistence(timeout: Self.timeout))
        app.tabBars.buttons["Recipes"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Start Cooking"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.buttons["Start Cooking"].isEnabled, "status returns to can-make")
    }

    // MARK: - 5.7 Create

    func testCreateFlowAddsANewTileAndCancelCreatesNothing() {
        let app = launch()
        openRecipesTab(app)
        XCTAssertTrue(app.staticTexts["Buttered Toast"].waitForExistence(timeout: Self.timeout))

        // Cancel from a fresh editor creates nothing.
        app.buttons["Add Recipe"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Add Recipe"].waitForExistence(timeout: Self.timeout))
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["Apple Pie"].exists)

        app.buttons["Add Recipe"].firstMatch.tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: Self.timeout))
        nameField.typeText("Apple Pie")

        app.buttons["Add Ingredient"].tap()
        let ingredientField = app.textFields["Ingredient"]
        XCTAssertTrue(ingredientField.waitForExistence(timeout: Self.timeout))
        ingredientField.tap()
        ingredientField.typeText("Apple")

        app.buttons["Add Step"].tap()
        let stepField = app.textFields["Step"]
        XCTAssertTrue(stepField.waitForExistence(timeout: Self.timeout))
        stepField.tap()
        stepField.typeText("Bake it")

        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Apple Pie"].waitForExistence(timeout: Self.timeout),
                      "the new tile appears")
    }

    // MARK: - 5.8 Delete with undo

    func testDeleteWithContextMenuShowsUndoAndRestoresIngredients() {
        let app = launch()
        openRecipesTab(app)
        XCTAssertTrue(app.staticTexts["Onion Soup"].waitForExistence(timeout: Self.timeout))

        app.staticTexts["Onion Soup"].press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: Self.timeout))
        app.buttons["Delete"].tap()

        XCTAssertFalse(app.staticTexts["Onion Soup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Deleted Onion Soup"].waitForExistence(timeout: Self.timeout))

        app.buttons["Undo"].tap()

        XCTAssertTrue(app.staticTexts["Onion Soup"].waitForExistence(timeout: Self.timeout))
        app.staticTexts["Onion Soup"].tap()
        XCTAssertTrue(app.staticTexts["Onion ×3"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["Butter ×1"].exists)
    }
}
