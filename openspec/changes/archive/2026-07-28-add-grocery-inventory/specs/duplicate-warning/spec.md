## ADDED Requirements

### Requirement: Warn when adding an item already at home

When a user saves a shopping-list item whose normalized name matches an item held in their household's home inventory with a quantity of one or more, the system SHALL present a warning before the item is added. This SHALL hold whether the save creates a new row or merges into an item already on the shopping list — what the household owns at home is the fact the warning exists to surface, and a list row already carrying that name does not convey it. The inventory consulted SHALL be the household's, so that every member is warned against the same stock regardless of who bought it.

#### Scenario: Adding something already owned

- **WHEN** the home inventory holds "Onion" with quantity 3 and the user saves a new shopping-list item named "onions"
- **THEN** a warning is presented before the item is added to the list

#### Scenario: Nothing at home produces no warning

- **WHEN** the home inventory holds no broccoli and the user saves "Broccoli"
- **THEN** no warning is shown and the item is added directly to the shopping list

#### Scenario: Items on the list alone do not trigger the warning

- **WHEN** the shopping list already holds "Onion" but no onions are at home
- **THEN** saving "Onion" again shows no already-have warning and the quantities are merged as usual

#### Scenario: On the list and at home still warns

- **WHEN** the shopping list holds "Onion" with quantity 2 and the home inventory holds "Onion" with quantity 3, and the user saves "onions" with quantity 1
- **THEN** the warning is presented stating that 3 are at home, and choosing to add anyway merges into the existing list row, leaving a single "Onion" row with quantity 3

### Requirement: Warning states the quantity on hand

The warning SHALL name the item and state how many the user already has at home, so the decision is made against a specific number rather than a generic alert.

#### Scenario: Warning text includes the count

- **WHEN** the home inventory holds "Onion" with quantity 3 and a warning is triggered for onions
- **THEN** the warning states that the user already has 3 at home

### Requirement: Warning does not block the add

The warning SHALL offer an action that adds the item anyway. Choosing it SHALL complete the add exactly as if no warning had appeared. The system SHALL NOT prevent, silently discard, or require justification for adding an item the user already owns.

#### Scenario: Buying more on purpose

- **WHEN** a user needs a second broccoli for a recipe, is warned that 1 is at home, and chooses to add anyway
- **THEN** "Broccoli" is added to the shopping list with the quantity the user entered, and the home inventory is unchanged

#### Scenario: Add-anyway is not penalized

- **WHEN** a user has chosen to add anyway for an item
- **THEN** no additional confirmation, delay, or repeated warning is presented for completing that same add

### Requirement: Cancelling returns to the entry in progress

The warning SHALL offer an action that abandons the add. Choosing it SHALL leave the shopping list unchanged and SHALL return the user to the entry they were editing, with the name and quantity they typed still present, so they can adjust rather than retype.

#### Scenario: Changing your mind

- **WHEN** a user is warned that 3 onions are at home and cancels
- **THEN** no onion item is added to the shopping list and the entry field still contains "onions"

### Requirement: Warning applies to renames that create a duplicate

When a user renames an existing shopping-list item so that its normalized name matches an item held at home, the system SHALL present the same warning with the same add-anyway and cancel choices before saving the rename.

#### Scenario: Renaming into something already owned

- **WHEN** the home inventory holds "Onion" with quantity 3 and the user renames a list item to "Onion"
- **THEN** the warning is presented, and the rename is saved only if the user chooses to proceed

### Requirement: On-hand count is visible while entering an item

While a user is typing an item name, the system SHALL display an inline, non-modal indication of how many of that item are already at home as soon as the typed name matches an inventory item. This indication SHALL NOT interrupt typing, take focus, or block saving.

#### Scenario: Live feedback while typing

- **WHEN** the home inventory holds "Onion" with quantity 3 and the user types "onion" into the name field
- **THEN** an inline note stating that 3 are already at home appears beneath the field while the user continues typing

#### Scenario: Indication clears when the name stops matching

- **WHEN** the user continues typing so the name becomes "onion powder", which matches nothing at home
- **THEN** the inline note disappears

### Requirement: Warning reflects what a household member stocked

An item added to the inventory by any household member SHALL trigger the warning for every other member. The warning SHALL be based on the most recently synced inventory state and SHALL NOT wait for a network round-trip before appearing.

#### Scenario: Partner already bought it

- **WHEN** one household member checks off "Onion" ×3 and, after that change syncs, another member adds "onions" to the shopping list
- **THEN** the second member is warned that 3 are already at home

#### Scenario: Warning does not block on the network

- **WHEN** a user adds an item while offline
- **THEN** the warning is evaluated against the locally stored inventory and appears without delay, rather than waiting for or requiring a sync
