import XCTest

/// Smoke-level XCUITest over the watch app. It exists because nothing else can
/// drive a watch simulator headlessly — the desktop simulator panel is iOS-only
/// — so iOS and macOS get agent-driven verification instead of a suite each.
///
/// Every case runs against a seeded in-memory stack with a pinned CloudKit
/// account status, so nothing here depends on the simulator's iCloud state.
final class XWasteWatchUITests: XCTestCase {

    /// Matches the seed in `WatchLaunch`.
    private enum Seed {
        static let produceItems = ["Broccoli", "Onion"]
        static let dairyItem = "Milk"
        static let homeItem = "Butter"
    }

    private enum AccountStatus {
        static let available = "1"
        static let noAccount = "3"
        static let temporarilyUnavailable = "4"
    }

    private static let timeout: TimeInterval = 20

    override func setUp() {
        continueAfterFailure = false
    }

    @discardableResult
    private func launch(seeded: Bool = true,
                        accountStatus: String = AccountStatus.available) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["XWASTE_UITEST_SEED"] = seeded ? "1" : "0"
        app.launchEnvironment["XWASTE_ACCOUNT_STATUS"] = accountStatus
        // Long enough that a slow simulator cannot lose the race to the
        // confirmation's auto-dismiss.
        app.launchEnvironment["XWASTE_CONFIRMATION_SECONDS"] = "120"
        app.launch()
        return app
    }

    /// The two pages are a vertical `TabView`; paging is a swipe, and the list
    /// on each page absorbs some of them, so swipe until the target appears.
    private func swipeUntil(_ element: XCUIElement, in app: XCUIApplication,
                            attempts: Int = 6, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<attempts {
            if element.exists { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: Self.timeout),
                      "never reached \(element)", file: file, line: line)
    }

    // MARK: - 7.1 Smoke

    func testBothPagesAreReachable() {
        let app = launch()

        XCTAssertTrue(app.buttons["checkoff-Broccoli"].waitForExistence(timeout: Self.timeout),
                      "the shopping list is the first page")
        swipeUntil(app.buttons["quantity-\(Seed.homeItem)"], in: app)
    }

    func testCategorySectionsAppearInFixedOrderWithEmptyOnesHidden() {
        let app = launch()
        XCTAssertTrue(app.buttons["checkoff-Broccoli"].waitForExistence(timeout: Self.timeout))

        let produce = app.staticTexts["Produce"]
        let dairy = app.staticTexts["Dairy & Eggs"]
        XCTAssertTrue(produce.exists)
        XCTAssertTrue(dairy.exists)
        XCTAssertLessThan(produce.frame.minY, dairy.frame.minY,
                          "Produce precedes Dairy & Eggs in the fixed category order")

        for empty in ["Meat & Seafood", "Bakery", "Frozen", "Pantry", "Beverages", "Snacks", "Household", "Other"] {
            XCTAssertFalse(app.staticTexts[empty].exists, "\(empty) has no items and must be hidden")
        }
    }

    func testRowTapChecksOffAndOffersUndoThatRestoresTheRow() {
        let app = launch()
        let onion = app.buttons["checkoff-Onion"]
        XCTAssertTrue(onion.waitForExistence(timeout: Self.timeout))

        onion.tap()

        let message = app.staticTexts["confirmation-message"]
        XCTAssertTrue(message.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(message.label.contains("Onion"), "the confirmation names the item")

        let undo = app.buttons["undo-button"]
        XCTAssertTrue(undo.exists)
        undo.tap()

        XCTAssertTrue(app.buttons["checkoff-Onion"].waitForExistence(timeout: Self.timeout),
                      "undo puts the row back on the list")
    }

    func testQuantityScreenAdjustsTheItem() {
        let app = launch()
        let quantityControl = app.buttons["quantity-Onion"]
        XCTAssertTrue(quantityControl.waitForExistence(timeout: Self.timeout))

        quantityControl.tap()

        let value = app.staticTexts["quantity-value"]
        XCTAssertTrue(value.waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(value.label, "2", "Onion is seeded at 2")

        app.buttons["quantity-increment"].tap()
        XCTAssertTrue(app.staticTexts["quantity-value"].label == "3"
                      || value.waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["quantity-value"].label, "3")

        app.buttons["quantity-decrement"].tap()
        XCTAssertEqual(app.staticTexts["quantity-value"].label, "2")
    }

    func testDecrementingToZeroRemovesTheRow() {
        let app = launch()
        // Broccoli is seeded at 1, so one decrement reaches zero.
        let quantityControl = app.buttons["quantity-Broccoli"]
        XCTAssertTrue(quantityControl.waitForExistence(timeout: Self.timeout))
        quantityControl.tap()

        XCTAssertTrue(app.staticTexts["quantity-value"].waitForExistence(timeout: Self.timeout))
        app.buttons["quantity-decrement"].tap()

        let message = app.staticTexts["confirmation-message"]
        XCTAssertTrue(message.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(message.label.contains("Broccoli"))

        app.buttons["confirmation-done"].tap()
        XCTAssertFalse(app.buttons["checkoff-Broccoli"].waitForExistence(timeout: 5),
                       "a row decremented to zero is gone, not stored as zero")
    }

    // MARK: - 7.2 Honest states

    func testNoAccountShowsTheRequiresICloudScreen() {
        let app = launch(seeded: false, accountStatus: AccountStatus.noAccount)

        XCTAssertTrue(app.otherElements["requires-icloud"].waitForExistence(timeout: Self.timeout)
                      || app.staticTexts["iCloud Required"].waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.staticTexts["Nothing to buy"].exists)
    }

    func testTemporarilyUnavailableShowsTheSameRequiresICloudScreen() {
        // What an Advanced-Data-Protection account yields on a simulator; from
        // the watch's side it is indistinguishable from having no account.
        let app = launch(seeded: false, accountStatus: AccountStatus.temporarilyUnavailable)

        XCTAssertTrue(app.otherElements["requires-icloud"].waitForExistence(timeout: Self.timeout)
                      || app.staticTexts["iCloud Required"].waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.staticTexts["Nothing to buy"].exists)
    }

    func testColdLaunchShowsSyncingRatherThanAnEmptyHousehold() {
        let app = launch(seeded: false, accountStatus: AccountStatus.available)

        XCTAssertTrue(app.staticTexts["Syncing"].waitForExistence(timeout: Self.timeout),
                      "an empty store with a reachable account is still loading")
        XCTAssertFalse(app.staticTexts["Nothing to buy"].exists,
                       "an unfinished first import must never read as an empty household")
    }

    // MARK: - 7.3 Absence assertions

    func testNoEditingOrSharingAffordanceExistsAnywhere() {
        let app = launch()
        XCTAssertTrue(app.buttons["checkoff-Broccoli"].waitForExistence(timeout: Self.timeout))

        assertNoEditingAffordances(in: app, screen: "shopping list")

        // The quantity screen: +/− and nothing else.
        app.buttons["quantity-Onion"].tap()
        XCTAssertTrue(app.staticTexts["quantity-value"].waitForExistence(timeout: Self.timeout))
        assertNoEditingAffordances(in: app, screen: "quantity screen")

        // And the At Home page.
        app.swipeRight()
        swipeUntil(app.buttons["quantity-\(Seed.homeItem)"], in: app)
        assertNoEditingAffordances(in: app, screen: "at home")
    }

    // MARK: - 7.4 Visual QC

    /// The desktop simulator panel is iOS-only and cannot attach to a watch
    /// simulator, so screenshots taken from inside the suite are the visual
    /// review path. Pure capture — the assertions live in the cases above.
    func testCaptureScreenshotsForVisualReview() {
        let app = launch()
        XCTAssertTrue(app.buttons["checkoff-Onion"].waitForExistence(timeout: Self.timeout))
        attach(app, named: "01-shopping-list")

        app.buttons["checkoff-Onion"].tap()
        XCTAssertTrue(app.staticTexts["confirmation-message"].waitForExistence(timeout: Self.timeout))
        attach(app, named: "02-checkoff-confirmation")
        app.buttons["undo-button"].tap()
        XCTAssertTrue(app.buttons["checkoff-Onion"].waitForExistence(timeout: Self.timeout))

        app.buttons["quantity-Onion"].tap()
        XCTAssertTrue(app.staticTexts["quantity-value"].waitForExistence(timeout: Self.timeout))
        attach(app, named: "03-quantity-screen")
        app.swipeRight()

        swipeUntil(app.buttons["quantity-\(Seed.homeItem)"], in: app)
        attach(app, named: "04-at-home")

        let signedOut = launch(seeded: false, accountStatus: AccountStatus.noAccount)
        XCTAssertTrue(signedOut.staticTexts["iCloud Required"].waitForExistence(timeout: Self.timeout))
        attach(signedOut, named: "05-requires-icloud")

        let cold = launch(seeded: false, accountStatus: AccountStatus.available)
        XCTAssertTrue(cold.staticTexts["Syncing"].waitForExistence(timeout: Self.timeout))
        attach(cold, named: "06-syncing")
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertNoEditingAffordances(in app: XCUIApplication, screen: String,
                                            file: StaticString = #filePath, line: UInt = #line) {
        let forbidden = ["Add", "Add Item", "New", "New Item", "Rename", "Edit",
                         "Category", "Share", "Invite", "Household", "Delete", "Remove"]
        for label in forbidden {
            XCTAssertFalse(app.buttons[label].exists,
                           "\(screen) must not offer a \(label) control", file: file, line: line)
        }
        for identifier in ["add-item", "edit-item", "share-household"] {
            XCTAssertFalse(app.buttons[identifier].exists,
                           "\(screen) must not offer \(identifier)", file: file, line: line)
        }
    }
}
