# shopping-list Specification

## Purpose

Provide the default Shopping List screen: category-sectioned display, quick add with quantity merging, row-level editing, single-tap check-off into the home inventory, and a safe undo path for check-offs.

## Requirements

### Requirement: Shopping list is the default screen

The app SHALL present two top-level destinations, "Shopping List" and "At Home", and SHALL open on the Shopping List. Switching between them SHALL preserve each screen's scroll position and SHALL NOT lose in-progress edits.

#### Scenario: Launching the app

- **WHEN** a user launches the app
- **THEN** the Shopping List screen is shown with a visible control for switching to the At Home screen

### Requirement: List is grouped into category sections

The shopping list SHALL display items grouped under their category, with sections in the fixed category order. Categories with no items on the list SHALL NOT display an empty section header.

#### Scenario: Item appears under its category header

- **WHEN** the list contains "Broccoli" and "Milk"
- **THEN** "Broccoli" appears under a "Produce" header and "Milk" appears under a "Dairy & Eggs" header

#### Scenario: Empty categories are hidden

- **WHEN** the list contains no frozen items
- **THEN** no "Frozen" header is displayed

#### Scenario: Item relocates when its category changes

- **WHEN** a user changes an item's category
- **THEN** the item moves to the corresponding section immediately, and its former section disappears if it is now empty

### Requirement: Add an item to the shopping list

The system SHALL let a user add an item by entering a name and optionally adjusting the quantity. Adding SHALL take no more than one control tap to begin and SHALL categorize the item automatically on save.

#### Scenario: Adding a new item

- **WHEN** a user enters "Broccoli" and saves
- **THEN** an item "Broccoli" with quantity 1 appears in the Produce section of the shopping list

#### Scenario: Adding with an explicit quantity

- **WHEN** a user enters "Onion", sets the quantity to 3, and saves
- **THEN** an item "Onion" with quantity 3 appears in the Produce section

### Requirement: Adding a name already on the list merges quantities

When a user adds an item whose normalized name matches an item already on the shopping list, the system SHALL increase the existing item's quantity by the amount added rather than creating a second row.

#### Scenario: Merging into an existing list row

- **WHEN** the list already contains "Onion" with quantity 2 and the user adds "onions" with quantity 1
- **THEN** the list shows a single "Onion" row with quantity 3

### Requirement: Edit and delete list items

The system SHALL let a user change an item's name, quantity, and category from the shopping list, and delete an item from the list. Adjusting quantity SHALL be possible directly from the row without opening a separate screen.

#### Scenario: Adjusting quantity from the row

- **WHEN** a user taps the increment control on a list row
- **THEN** the quantity updates immediately in place

#### Scenario: Deleting from the list

- **WHEN** a user swipes a row and confirms deletion
- **THEN** the item is removed from the shopping list and is not added to the home inventory

### Requirement: Checking off an item moves it to the home inventory

When a user checks off a shopping-list item, the system SHALL remove it from the shopping list and add its quantity to the home inventory. If an item with the same normalized name already exists at home, the system SHALL add the checked-off quantity to that existing item rather than creating a duplicate. Checking off SHALL require a single tap and SHALL NOT present a confirmation dialog.

#### Scenario: Checking off an item not yet at home

- **WHEN** a user checks off "Broccoli" with quantity 1 and no broccoli is at home
- **THEN** "Broccoli" leaves the shopping list and appears in the home inventory with quantity 1

#### Scenario: Checking off an item already at home

- **WHEN** the home inventory contains "Onion" with quantity 3 and the user checks off "Onion" with quantity 2
- **THEN** the shopping-list row disappears and the home inventory shows a single "Onion" with quantity 5

#### Scenario: Category is carried over

- **WHEN** a user checks off an item categorized as Produce
- **THEN** the item appears under Produce in the home inventory, including a category the user had set manually

### Requirement: Undo a check-off

After a check-off, the system SHALL display an undo control naming the item that was checked off. Activating it SHALL fully reverse the move: the item SHALL return to the shopping list with its original quantity and category, and the quantity added to the home inventory SHALL be subtracted, removing the home item entirely if the check-off created it. The undo control SHALL remain available for at least five seconds while the shopping list is on screen, and SHALL be dismissible by the user. Navigating away from the shopping list MAY dismiss it — the move-back-to-list recovery below is the permanent path, so a dismissed control never leaves a check-off uncorrectable.

#### Scenario: Undoing a check-off that created a new home item

- **WHEN** a user checks off "Broccoli" with quantity 1 and then activates undo
- **THEN** "Broccoli" returns to the shopping list with quantity 1 and no broccoli remains in the home inventory

#### Scenario: Undoing a check-off that merged into an existing home item

- **WHEN** the home inventory held "Onion" with quantity 3, the user checked off "Onion" with quantity 2, and the user then activates undo
- **THEN** the home inventory shows "Onion" with quantity 3 again and "Onion" with quantity 2 returns to the shopping list

#### Scenario: Undo targets the most recent check-off

- **WHEN** a user checks off several items in succession
- **THEN** the undo control refers to the most recently checked-off item and reverses only that one

#### Scenario: Undo expires without side effects

- **WHEN** a user checks off an item and lets the undo control disappear
- **THEN** the item remains in the home inventory and nothing further changes

#### Scenario: Leaving the shopping list may dismiss the control

- **WHEN** a user checks an item off and immediately switches to the At Home screen
- **THEN** the undo control need not follow them, the check-off stands, and the item remains correctable by moving it back to the shopping list

### Requirement: Undo does not overwrite a concurrent change

Before reversing a check-off, the system SHALL verify that the affected home inventory item still exists and still holds the quantity the check-off produced. If it does not — because another household member or another device changed it in the interim — the system SHALL restore the shopping-list row but SHALL NOT alter the home quantity, and SHALL tell the user that the item was changed elsewhere and was left as-is. The same SHALL apply when the home item no longer exists at all, whether it was deleted outright or reduced to zero: the system SHALL restore the shopping-list row, SHALL NOT recreate the home item, and SHALL report the same outcome.

#### Scenario: Partner edited the item before undo

- **WHEN** a user checks off "Onion" ×2 into a home total of 5, a household member then sets that item to 4, and the user activates undo
- **THEN** "Onion" ×2 returns to the shopping list, the home quantity remains 4 rather than being reduced to 3, and the user is told the item was changed elsewhere

#### Scenario: Home item was removed before undo

- **WHEN** a user checks off "Milk" ×1, a household member then uses it so its quantity reaches zero and the item is removed, and the user activates undo
- **THEN** "Milk" ×1 returns to the shopping list, no milk row is recreated at home, and the user is told the item was changed elsewhere

#### Scenario: Undamaged undo proceeds normally

- **WHEN** no one has changed the home item since the check-off
- **THEN** undo reverses the quantity exactly as recorded, with no additional message

### Requirement: Recovery after undo expires

The system SHALL let a user move an item from the home inventory back onto the shopping list at any time, so that an accidental check-off remains correctable after the undo control is gone.

#### Scenario: Correcting a mistake later

- **WHEN** a user realizes an hour later that an item was checked off by accident
- **THEN** the user can move that item from the home inventory back to the shopping list without deleting and retyping it

### Requirement: Empty shopping list state

When the shopping list contains no items, the system SHALL display a message explaining how to add the first item rather than a blank screen.

#### Scenario: First launch

- **WHEN** a user opens the app with no items on the list
- **THEN** an empty-state message with guidance to add an item is displayed
