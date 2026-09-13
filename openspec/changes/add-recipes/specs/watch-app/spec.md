## MODIFIED Requirements

### Requirement: Watch app scope is check-off focused

The watchOS app SHALL display the household's shopping list and home inventory and SHALL support checking items off, undoing a check-off, and adjusting quantities. The watch app SHALL NOT provide adding, renaming, recategorization, deletion by any means other than decrement-to-zero, household-sharing management, recipes, or cooking sessions; those flows remain on the phone. Because items cannot be added on the watch, the watch SHALL NOT present any duplicate warning.

#### Scenario: Watch shows the same list as the phone

- **WHEN** the household's shopping list contains "Broccoli" under Produce and "Milk" under Dairy & Eggs
- **THEN** the watch shopping list shows the same items under the same category sections in the same fixed category order, with empty categories hidden

#### Scenario: No add affordance exists

- **WHEN** a user looks for a way to create a new item on the watch
- **THEN** no add control exists, and adding remains a phone flow

#### Scenario: No recipes on the watch

- **WHEN** the household has recipes
- **THEN** the watch app shows no recipes page, tile, or cooking control, and its shopping list and At Home pages are unaffected
