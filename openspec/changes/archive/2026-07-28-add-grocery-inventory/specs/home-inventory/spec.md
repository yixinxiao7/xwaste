## ADDED Requirements

### Requirement: At Home screen lists what the user owns

The system SHALL provide an "At Home" screen, separate from the shopping list, that displays every item currently in the home inventory with its name and quantity, grouped into category sections in the fixed category order. Categories with no items at home SHALL NOT display an empty section header.

#### Scenario: Viewing the inventory

- **WHEN** the home inventory holds "Onion" with quantity 3 and "Milk" with quantity 1
- **THEN** the At Home screen shows "Onion 3" under Produce and "Milk 1" under Dairy & Eggs

#### Scenario: Shopping-list items are excluded

- **WHEN** an item is on the shopping list but has not been checked off
- **THEN** it does not appear on the At Home screen

### Requirement: Adjust inventory quantities directly

The system SHALL let a user increase or decrease an item's quantity from the At Home screen without navigating to another screen. Changes SHALL be applied and persisted immediately.

#### Scenario: Using an onion

- **WHEN** a user decrements "Onion" from 3 to 2 after cooking
- **THEN** the row shows 2 immediately and still shows 2 after relaunching the app

### Requirement: Reaching zero removes the item

When a user reduces an item's quantity to zero, the system SHALL remove it from the home inventory rather than displaying a zero-quantity row.

#### Scenario: Using the last one

- **WHEN** a user decrements "Milk" from 1
- **THEN** "Milk" is removed from the home inventory and no zero-quantity row remains

#### Scenario: Removed item no longer triggers a duplicate warning

- **WHEN** a user has removed all broccoli from the inventory and then adds "Broccoli" to the shopping list
- **THEN** no already-have warning is shown

### Requirement: Edit and delete inventory items

The system SHALL let a user rename an item, change its category, and delete an item from the home inventory.

#### Scenario: Deleting an item outright

- **WHEN** a user swipes an inventory row and confirms deletion
- **THEN** the item is removed from the home inventory regardless of its quantity

#### Scenario: Renaming an inventory item

- **WHEN** a user renames an automatically categorized inventory item
- **THEN** the name updates and the item is recategorized from the new name

### Requirement: Move an item back to the shopping list

The system SHALL let a user move an item from the home inventory onto the shopping list, preserving its name, quantity, and category. If the shopping list already holds an item with the same normalized name, the quantities SHALL be combined into that existing row.

#### Scenario: Correcting an accidental check-off

- **WHEN** a user moves "Broccoli" with quantity 1 from the At Home screen back to the shopping list
- **THEN** "Broccoli" with quantity 1 appears on the shopping list under Produce and no longer appears at home

#### Scenario: Moving back into an existing list row

- **WHEN** the shopping list already holds "Onion" with quantity 1 and the user moves "Onion" with quantity 2 back from the inventory
- **THEN** the shopping list shows a single "Onion" row with quantity 3

### Requirement: Add an item directly to the inventory

The system SHALL let a user add an item straight to the home inventory without first putting it on the shopping list, so that existing groceries can be recorded when the app is first set up.

#### Scenario: Stocking the inventory initially

- **WHEN** a user adds "Rice" with quantity 2 from the At Home screen
- **THEN** "Rice" with quantity 2 appears in the home inventory under Pantry and does not appear on the shopping list

### Requirement: Inventory changes reach household members

Changes to the home inventory SHALL propagate to every member of the household. A member's view SHALL update without requiring a manual refresh or an app restart once a change has synced.

#### Scenario: Using the last onion at home

- **WHEN** one member decrements "Onion" from 3 to 2 and the change syncs
- **THEN** other members' At Home screens show 2 without any manual refresh

#### Scenario: Removal propagates

- **WHEN** one member reduces an item to zero, removing it
- **THEN** the item disappears from every member's inventory, and adding it no longer triggers an already-have warning for anyone

### Requirement: Concurrent quantity edits may lose an increment

When two household members change the same item's quantity before those changes have synced, the system resolves the conflict by keeping the last write rather than combining both. The resulting quantity MAY therefore be lower than the true total. The system SHALL keep every inventory quantity directly editable so a user can correct such a discrepancy in place.

#### Scenario: Simultaneous check-off of the same item

- **WHEN** two members each check off "Onion" ×2 within the same sync window, starting from a home total of 1
- **THEN** the resulting quantity may be 3 rather than 5, and the user can correct it by editing the quantity directly

#### Scenario: Correction requires no special flow

- **WHEN** a user notices the inventory disagrees with their kitchen
- **THEN** they can set the correct quantity from the At Home screen without deleting the item, re-adding it, or visiting a settings or conflict-resolution screen

### Requirement: Empty inventory state

When the home inventory contains no items, the system SHALL display a message explaining that checked-off items land here and offering to add an item directly.

#### Scenario: Nothing at home yet

- **WHEN** a user opens the At Home screen before checking anything off
- **THEN** an empty-state message with that guidance is displayed
