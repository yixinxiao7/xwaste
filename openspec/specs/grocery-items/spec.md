# grocery-items Specification

## Purpose

Define the grocery item record and the rules every other capability builds on: name normalization, whole-number quantities, create/edit/delete, one item per normalized name per location, and offline-first persistence.

## Requirements

### Requirement: Grocery item record

The system SHALL persist every grocery item as a single record containing a display name, a normalized name derived from the display name, a whole-number quantity, a category, a location of either `shoppingList` or `atHome`, a flag recording whether the category was set manually, a creation timestamp, and the household the item belongs to. Every item SHALL belong to exactly one household.

#### Scenario: Item created with complete record

- **WHEN** a user adds an item named "Broccoli" with quantity 1
- **THEN** the system stores one record with display name "Broccoli", normalized name "broccoli", quantity 1, an assigned category, location `shoppingList`, the manual-category flag set to false, the current timestamp, and a reference to the user's household

#### Scenario: Household exists before any item

- **WHEN** a user launches the app for the first time
- **THEN** a household is created automatically, with no prompt and no setup step, so that the first item added has an owner

#### Scenario: Items survive app restart

- **WHEN** a user adds items, force-quits the app, and relaunches it
- **THEN** every item reappears with its name, quantity, category, and location unchanged

### Requirement: Name normalization

The system SHALL derive a normalized name by trimming leading and trailing whitespace, collapsing internal whitespace runs to a single space, lowercasing, removing punctuation, and folding a trailing plural suffix. The identical normalization SHALL be applied both when storing a name and when looking one up. Two items refer to the same grocery if and only if their normalized names are exactly equal; the system SHALL NOT treat partial or fuzzy name overlap as a match.

#### Scenario: Case and whitespace differences resolve to the same item

- **WHEN** the inventory contains "Broccoli" and the user types "  broccoli  "
- **THEN** the system treats the typed name as referring to the existing "Broccoli" item

#### Scenario: Plural and singular resolve to the same item

- **WHEN** the inventory contains "Onions" and the user types "onion"
- **THEN** the system treats the typed name as referring to the existing "Onions" item

#### Scenario: Distinct names remain distinct items

- **WHEN** the inventory contains "Onion" and the user adds "Green Onion"
- **THEN** the system creates a separate item and does not merge it into "Onion"

#### Scenario: Display name preserves what the user typed

- **WHEN** a user adds "Baby Spinach"
- **THEN** the list displays "Baby Spinach" with the user's original capitalization, and the normalized form is used only for matching

### Requirement: Whole-number quantities

Item quantities SHALL be whole numbers of one or greater. The system SHALL NOT store a quantity of zero or below; any operation that would reduce a quantity to zero or below SHALL remove the item instead. The system SHALL NOT offer units of measure.

#### Scenario: Quantity increments by whole numbers

- **WHEN** a user taps the increment control on an item with quantity 2
- **THEN** the quantity becomes 3

#### Scenario: Decrementing past one removes the item

- **WHEN** a user decrements an item whose quantity is 1
- **THEN** the item is removed from its list and no zero-quantity record remains

#### Scenario: Default quantity on add

- **WHEN** a user adds an item without adjusting the quantity control
- **THEN** the item is created with quantity 1

### Requirement: Create, edit, and delete items

The system SHALL allow a user to create an item with a name and quantity, edit an existing item's name and quantity, and delete an item outright. Edits and deletions SHALL take effect immediately and SHALL be persisted.

#### Scenario: Editing a name recomputes the normalized name

- **WHEN** a user renames an item from "Bok Choy" to "Cabbage"
- **THEN** the display name becomes "Cabbage" and the normalized name becomes "cabbage"

#### Scenario: Deleting an item

- **WHEN** a user deletes an item
- **THEN** the item disappears from its list immediately and does not reappear after relaunch

#### Scenario: Blank names are rejected

- **WHEN** a user attempts to save an item whose name is empty or only whitespace
- **THEN** the system does not create the item and keeps the entry field active

### Requirement: One item per normalized name per location

Within a household, at most one item SHALL exist for a given normalized name in a given location. Whenever an operation would otherwise produce a second item with the same normalized name in the same location — adding, moving between locations, or renaming — the system SHALL combine the quantities into the item that already exists rather than storing two rows. The surviving item SHALL keep the display name, category, and manual-category flag it already had; only its quantity changes. The same normalized name in two different locations is not a collision, since one describes what to buy and the other what is owned.

#### Scenario: Renaming into an existing item merges them

- **WHEN** the shopping list holds "Onion" with quantity 2 and "Scallion" with quantity 1, and the user renames "Scallion" to "Onions"
- **THEN** the list shows a single "Onion" row with quantity 3 and no separate scallion row remains

#### Scenario: Renaming merges within the inventory as well

- **WHEN** the home inventory holds "Bell Pepper" with quantity 1 and "Red Pepper" with quantity 2, and the user renames "Red Pepper" to "Bell Peppers"
- **THEN** the inventory shows a single "Bell Pepper" row with quantity 3

#### Scenario: The surviving item keeps its own category

- **WHEN** a user renames an item into one that was manually categorized as Frozen
- **THEN** the merged row stays in Frozen and keeps its manual flag, rather than being reclassified from the newly typed name

#### Scenario: The same name in two locations stays separate

- **WHEN** "Onion" is on the shopping list and "Onion" is also in the home inventory
- **THEN** both rows exist independently and neither is merged into the other

### Requirement: Offline-first persistence

All item data SHALL be written to local storage first and SHALL remain fully readable and writable with no network connection. The system SHALL NOT require a network connection, an iCloud account, or a completed sync for any item operation to succeed.

#### Scenario: Full function in airplane mode

- **WHEN** the device has airplane mode enabled
- **THEN** the user can add, edit, categorize, check off, and delete items with no degradation, no blocking spinner, and no error

#### Scenario: Changes made offline are retained

- **WHEN** a user makes changes with no connection and later regains one
- **THEN** none of the offline changes are lost

#### Scenario: No iCloud account available

- **WHEN** the device has no iCloud account signed in, or iCloud Drive is disabled
- **THEN** the app remains fully usable as a local-only list and inventory, and communicates that sync is unavailable without presenting an error state or an empty screen
