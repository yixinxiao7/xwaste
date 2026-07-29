## ADDED Requirements

### Requirement: Watch app scope is check-off focused

The watchOS app SHALL display the household's shopping list and home inventory and SHALL support checking items off, undoing a check-off, and adjusting quantities. The watch app SHALL NOT provide adding, renaming, recategorization, deletion by any means other than decrement-to-zero, or household-sharing management; those flows remain on the phone. Because items cannot be added on the watch, the watch SHALL NOT present any duplicate warning.

#### Scenario: Watch shows the same list as the phone

- **WHEN** the household's shopping list contains "Broccoli" under Produce and "Milk" under Dairy & Eggs
- **THEN** the watch shopping list shows the same items under the same category sections in the same fixed category order, with empty categories hidden

#### Scenario: No add affordance exists

- **WHEN** a user looks for a way to create a new item on the watch
- **THEN** no add control exists, and adding remains a phone flow

### Requirement: Single-tap check-off with undo on the watch

Tapping a shopping-list row on the watch SHALL check the item off with the identical semantics as on the phone: the item leaves the list and its quantity merges into the home inventory, with no confirmation dialog before the action. After a check-off the watch SHALL present an undo affordance naming the item, available for at least five seconds, whose activation verifies the home item is unchanged before reversing — and when the item was changed elsewhere, restores only the list row and says so.

#### Scenario: Checking off from the wrist

- **WHEN** a user taps the "Onion" row (quantity 2) while 3 onions are at home
- **THEN** the row leaves the watch list, the home inventory shows a single onion row with quantity 5, and an undo affordance naming "Onion" appears

#### Scenario: Undo from the watch respects concurrent edits

- **WHEN** a user checks off an item on the watch, another household member changes the affected home item before the user taps Undo
- **THEN** the shopping-list row is restored, the home quantity is left as the other member set it, and the watch tells the user the item was changed elsewhere

#### Scenario: Undo expiry is safe

- **WHEN** the undo affordance expires or the user navigates away
- **THEN** nothing further changes, and the item remains recoverable from the phone's Move to Shopping List action

### Requirement: Quantity adjustment on the watch

The watch SHALL allow increasing and decreasing an item's quantity on both the shopping list and the home inventory without obstructing the row's primary tap action. A decrement that would reach zero SHALL remove the item, consistent with the whole-number quantity rules.

#### Scenario: Using up an item from the wrist

- **WHEN** a user decrements "Milk" from 1 in the watch inventory view
- **THEN** the milk row is removed and no zero-quantity row remains, on the watch and on every synced device

#### Scenario: Quantity controls do not steal the check-off tap

- **WHEN** a user taps the body of a shopping-list row
- **THEN** the item is checked off; quantity adjustment requires a deliberate interaction with a distinct control

### Requirement: Watch data is the household's live data

The watch app SHALL read and write the same household data as the user's other devices through the same sync container, including a shared household the user has joined: items, quantities, categories, and check-offs made anywhere SHALL appear on the watch once synced, and watch actions SHALL reach other members' devices without any watch-specific pairing, import, or setup step.

#### Scenario: Partner's additions reach the wrist

- **WHEN** a household member adds "Coffee" to the shared shopping list from their phone
- **THEN** the item appears in the watch shopping list once the change syncs, with no user action on the watch

#### Scenario: Watch check-off reaches the household

- **WHEN** a user checks off an item on the watch
- **THEN** the item leaves every member's shopping list and lands in the shared inventory once synced

### Requirement: Honest states when data cannot be shown

When the watch has no iCloud account available, the watch app SHALL state that it requires iCloud rather than showing an empty list, an error, or a spinner without explanation. While the first sync of an available account is still in progress, an empty list SHALL be presented as loading, not as an empty household.

#### Scenario: No iCloud on the watch

- **WHEN** the watch has no iCloud account available to it
- **THEN** the watch app explains that it needs iCloud to show the household's list, and offers no broken or empty-looking screen

#### Scenario: Cold first launch

- **WHEN** the watch app runs for the first time on a signed-in watch and the initial import has not finished
- **THEN** the empty state communicates that syncing is in progress
