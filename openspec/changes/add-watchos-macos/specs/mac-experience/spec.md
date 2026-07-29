## ADDED Requirements

### Requirement: Every action is reachable with Mac input methods

On macOS, every user action available in the app SHALL be performable with pointer and keyboard alone. No action may exist only behind a touch gesture: row actions that are swipe-based on iOS (delete, move to shopping list) SHALL be available from a context menu on the row, and the delete key SHALL delete the selected row. Creating an item SHALL be available via a keyboard shortcut as well as the toolbar control.

#### Scenario: Deleting a row without a touchscreen

- **WHEN** a Mac user right-clicks a shopping-list row and chooses Delete, or selects the row and presses the delete key
- **THEN** the item is removed exactly as an iOS swipe-to-delete would remove it

#### Scenario: Moving an item back on the Mac

- **WHEN** a Mac user right-clicks an inventory row
- **THEN** a "Move to Shopping List" action is offered with identical semantics to the iOS swipe action, including merging into an existing list row

#### Scenario: Keyboard-first add

- **WHEN** a Mac user presses ⌘N
- **THEN** the add-item sheet opens with the name field focused

### Requirement: Feature parity of core flows on macOS

The macOS app SHALL provide the same capabilities as the iOS app — category-sectioned list and inventory, check-off with undo, duplicate warning with its inline note and confirmation alert, manual category override, and household sharing (inviting, member list, leaving, stopping) — backed by the same data and sync behavior. Platform-appropriate presentation MAY differ; behavior SHALL NOT.

#### Scenario: Duplicate warning on the Mac

- **WHEN** a Mac user adds an item that is at home with quantity 2
- **THEN** the inline on-hand note and the save-time confirmation alert behave exactly as they do on iOS, including Cancel preserving the typed values

#### Scenario: Sharing from the Mac

- **WHEN** a Mac user opens the Household view and invites someone
- **THEN** the system share sheet is presented and the resulting invitation is the same household share an iOS invite would produce

### Requirement: The window respects the layout

The macOS app SHALL open at a sensible default window size and SHALL enforce a minimum window size at which both tabs remain fully usable — no clipped toolbars, unreachable controls, or collapsed lists.

#### Scenario: Shrinking the window

- **WHEN** a Mac user drags the window to its minimum size
- **THEN** the tab bar, toolbar buttons, list rows, and steppers all remain visible and operable

### Requirement: macOS is a peer device for the household

A Mac signed into the user's iCloud account SHALL sync the same private and shared data as the user's iPhone, and changes made on either SHALL converge on the other without manual refresh. The Mac SHALL degrade to fully-functional local-only use when no iCloud account is signed in, with the same honest messaging as iOS.

#### Scenario: Same-account convergence between Mac and iPhone

- **WHEN** a user adds an item on the Mac and opens the app on their iPhone signed into the same iCloud account
- **THEN** the item appears on the iPhone without manual action, and edits made on the iPhone likewise appear on the Mac

#### Scenario: Mac without iCloud

- **WHEN** the Mac has no iCloud account signed in
- **THEN** every list, inventory, categorization, and warning feature works locally and the sharing entry point explains that sharing requires iCloud
