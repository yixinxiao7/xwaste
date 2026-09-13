## MODIFIED Requirements

### Requirement: Feature parity of core flows on macOS

The macOS app SHALL provide the same capabilities as the iOS app — category-sectioned list and inventory, check-off with undo, duplicate warning with its inline note and confirmation alert, manual category override, household sharing (inviting, member list, leaving, stopping), recipes with their availability status and filter, and cooking sessions with Finish Cooking and its undo — backed by the same data and sync behavior. Platform-appropriate presentation MAY differ; behavior SHALL NOT.

#### Scenario: Duplicate warning on the Mac

- **WHEN** a Mac user adds an item that is at home with quantity 2
- **THEN** the inline on-hand note and the save-time confirmation alert behave exactly as they do on iOS, including Cancel preserving the typed values

#### Scenario: Sharing from the Mac

- **WHEN** a Mac user opens the Household view and invites someone
- **THEN** the system share sheet is presented and the resulting invitation is the same household share an iOS invite would produce

#### Scenario: Cooking on the Mac

- **WHEN** a Mac user opens a recipe that can be made, starts cooking, checks entries with the mouse, and finishes
- **THEN** the session appears in a window-appropriate presentation, Escape or Cancel discards it with no inventory change, and Finish Cooking reduces At Home with the same undo control as on iOS

#### Scenario: Recipe actions reachable with Mac input

- **WHEN** a Mac user right-clicks a recipe tile
- **THEN** Edit and Delete are offered, and ⌘N on the Recipes screen opens the recipe editor
