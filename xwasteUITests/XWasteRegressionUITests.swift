import XCTest

/// The iOS half of task 7.5: a one-time regression check that group 6's
/// cross-platform edits — context menus, list selection, ⌘N — did not disturb
/// the iPhone flows that already shipped. The same view bodies now serve iOS
/// and macOS, so this guards the platform that was working first.
///
/// This suite exists because the desktop simulator panel cannot attach to an
/// Xcode 27 beta (it looks for `SimulatorKit.framework` at a path Xcode 27 no
/// longer uses) and that Xcode ships no `Simulator.app` to drive by hand, so
/// there is no way to drive the iOS simulator directly on this machine.
final class XWasteRegressionUITests: XCTestCase {

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

    private func row(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.cells.containing(.staticText, identifier: name).firstMatch
    }

    private func openAtHomeTab(_ app: XCUIApplication) {
        app.tabBars.buttons["At Home"].firstMatch.tap()
    }

    // MARK: - Swipe actions still work

    func testSwipeToDeleteStillRemovesTheRow() {
        let app = launch()
        let onion = row("Onion", in: app)
        XCTAssertTrue(onion.waitForExistence(timeout: Self.timeout))

        onion.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: Self.timeout), "the trailing swipe action survives")
        delete.tap()

        XCTAssertFalse(app.staticTexts["Onion"].waitForExistence(timeout: 5))
        // Deleting from the list never touches the inventory.
        openAtHomeTab(app)
        XCTAssertTrue(app.staticTexts["Butter"].waitForExistence(timeout: Self.timeout))
    }

    func testLeadingSwipeStillMovesAnItemBackToTheList() {
        let app = launch()
        openAtHomeTab(app)
        let butter = row("Butter", in: app)
        XCTAssertTrue(butter.waitForExistence(timeout: Self.timeout))

        butter.swipeRight()
        let moveBack = app.buttons["Move to Shopping List"].firstMatch
        XCTAssertTrue(moveBack.waitForExistence(timeout: Self.timeout))
        moveBack.tap()

        XCTAssertFalse(app.staticTexts["Butter"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Shopping List"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Butter"].waitForExistence(timeout: Self.timeout))
    }

    // MARK: - Context menus are present but not disruptive

    func testContextMenuOffersTheRowActions() {
        let app = launch()
        let onion = row("Onion", in: app)
        XCTAssertTrue(onion.waitForExistence(timeout: Self.timeout))

        onion.press(forDuration: 1.2)

        for action in ["Check Off", "Edit", "Delete"] {
            XCTAssertTrue(app.buttons[action].waitForExistence(timeout: Self.timeout),
                          "the shopping-list context menu offers \(action)")
        }
        // Dismiss without choosing anything; nothing should have changed.
        app.tap()
        XCTAssertTrue(app.staticTexts["Onion"].waitForExistence(timeout: Self.timeout))
    }

    func testInventoryContextMenuOffersMoveToShoppingList() {
        let app = launch()
        openAtHomeTab(app)
        let butter = row("Butter", in: app)
        XCTAssertTrue(butter.waitForExistence(timeout: Self.timeout))

        butter.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Move to Shopping List"].waitForExistence(timeout: Self.timeout))
        app.buttons["Move to Shopping List"].tap()

        XCTAssertFalse(app.staticTexts["Butter"].waitForExistence(timeout: 5))
    }

    func testTappingARowStillOpensTheEditorRatherThanSelectingIt() {
        // `List(selection:)` was added for the Mac's delete key; on iOS the
        // row's tap must still open the editor as it always did.
        let app = launch()
        let onion = row("Onion", in: app)
        XCTAssertTrue(onion.waitForExistence(timeout: Self.timeout))

        onion.tap()

        XCTAssertTrue(app.navigationBars["Edit Item"].waitForExistence(timeout: Self.timeout))
        app.buttons["Cancel"].tap()
    }

    // MARK: - Add and duplicate-warning flow unchanged

    func testAddFlowAndDuplicateWarningAreUnchanged() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Onion"].waitForExistence(timeout: Self.timeout))

        app.buttons["Add Item"].firstMatch.tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: Self.timeout))
        nameField.typeText("Butter")

        // The live inline note, while typing.
        XCTAssertTrue(app.staticTexts["You have 1 at home"].waitForExistence(timeout: Self.timeout),
                      "the inline on-hand note still fires")

        app.buttons["Save"].tap()

        // The confirmation alert, on save.
        let alert = app.alerts["Already at home"]
        XCTAssertTrue(alert.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(alert.staticTexts.element(boundBy: 1).label.contains("Butter"))

        // Cancel returns to a still-populated sheet — it must not discard input.
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(app.textFields["Name"].value as? String, "Butter",
                       "Cancel preserves the typed values")

        // Warn, never block: Add Anyway completes the add.
        app.buttons["Save"].tap()
        XCTAssertTrue(app.alerts["Already at home"].waitForExistence(timeout: Self.timeout))
        app.alerts["Already at home"].buttons["Add Anyway"].tap()

        XCTAssertTrue(row("Butter", in: app).waitForExistence(timeout: Self.timeout),
                      "the item lands on the shopping list")
        openAtHomeTab(app)
        XCTAssertTrue(app.staticTexts["Butter"].waitForExistence(timeout: Self.timeout),
                      "and the at-home row is untouched")
    }

    // MARK: - Check-off and undo still behave

    func testCheckOffShowsTheUndoBannerAndUndoRestoresTheRow() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Onion"].waitForExistence(timeout: Self.timeout))

        app.buttons["Check off Onion"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Checked off Onion"].waitForExistence(timeout: Self.timeout))
        app.buttons["Undo"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Onion"].waitForExistence(timeout: Self.timeout))
    }
}
