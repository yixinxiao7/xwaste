## Purpose

Guide the user through cooking a recipe with a fresh two-part checklist — ingredients to prepare, then steps to follow — and draw the used ingredients down from At Home when they finish, with an undo that verifies before reversing.

## ADDED Requirements

### Requirement: Start Cooking is available when the recipe can be made

The recipe page SHALL show a "Start Cooking" control. It SHALL be enabled when the recipe's availability status is a check mark and disabled — visible but not activatable — when the status is an x, so the marked ingredients explain why. Activating it SHALL open a new cooking session for that recipe.

#### Scenario: Starting a cookable recipe

- **WHEN** a recipe shows a check mark and the user activates Start Cooking
- **THEN** a cooking session for that recipe opens

#### Scenario: Recipe with a shortfall

- **WHEN** a recipe shows an x
- **THEN** Start Cooking is shown disabled and cannot be activated

#### Scenario: Status changes while viewing

- **WHEN** a recipe page shows a disabled Start Cooking and the missing ingredient is added At Home in the meantime
- **THEN** the control becomes enabled without leaving the page

### Requirement: Session page with two checklists

A cooking session SHALL present the recipe's ingredients, each with its count, as a checklist for preparation, and the recipe's steps, in order, as a checklist for cooking. Every entry SHALL be toggleable on and off individually. The session SHALL NOT change any stored data while it is open.

#### Scenario: Ticking off preparation

- **WHEN** the user toggles "Onion" ×3 in the ingredient checklist
- **THEN** it shows as checked, the other entries are unchanged, and toggling it again clears it

#### Scenario: Following the steps

- **WHEN** the user toggles the second step
- **THEN** the second step shows as checked and the steps remain in recipe order

### Requirement: Every session starts clean

Each cooking session SHALL begin with every ingredient and step unchecked, regardless of what was checked in any previous session for the same recipe. No checklist progress SHALL persist beyond the session that produced it.

#### Scenario: Cooking the same recipe again

- **WHEN** a user checked every entry in a previous session for "Buttered Toast" and starts a new session for it
- **THEN** every ingredient and step is unchecked

#### Scenario: Relaunch mid-session

- **WHEN** the app is quit while a session is open and relaunched
- **THEN** no session is open, and starting one again shows every entry unchecked

### Requirement: Cancelling a session

The session SHALL offer an explicit cancel control that closes it and returns to the recipe page with no change to any stored data. Once any entry has been checked, the session SHALL close only through its explicit controls, so an incidental gesture cannot end a session in progress.

#### Scenario: Backing out

- **WHEN** a user cancels a session after checking two ingredients
- **THEN** the recipe page is shown, the inventory is unchanged, and the next session starts unchecked

#### Scenario: Accidental gesture mid-cook

- **WHEN** a user has checked an entry and performs the platform's dismiss gesture on the session
- **THEN** the session remains open

### Requirement: Finishing consumes the ingredients

The session SHALL offer a "Finish Cooking" control regardless of how many entries are checked. Activating it SHALL close the session and, for each ingredient, reduce the At Home item with the same normalized name by the ingredient's count; an item whose quantity would reach zero or below SHALL be removed, per the whole-number quantity rule. The change SHALL be persisted immediately and SHALL propagate to household members like any inventory change.

#### Scenario: Finishing draws down the inventory

- **WHEN** a session for a recipe needing "Onion" ×3 and "Butter" ×1 is finished while At Home holds "Onion" ×5 and "Butter" ×1
- **THEN** At Home shows "Onion" ×2 and no butter row

#### Scenario: Unchecked entries do not block finishing

- **WHEN** a user finishes a session with several steps unchecked
- **THEN** the session closes and the inventory is reduced exactly as if every entry had been checked

#### Scenario: Recipe status reflects the cook

- **WHEN** finishing leaves fewer onions at home than the recipe needs
- **THEN** the recipe page now shows an x and Start Cooking is disabled

#### Scenario: An ingredient was used up elsewhere first

- **WHEN** At Home no longer holds one of the ingredients at the moment a session is finished
- **THEN** the other ingredients are reduced as usual, nothing is created for the absent one, and the session still closes

### Requirement: Undo a finished session

After finishing, the system SHALL display an undo control naming the recipe, available for at least five seconds while the recipe page is on screen and dismissible by the user. Activating it SHALL verify, for each ingredient, that the At Home item is still as the finish left it — holding the reduced quantity, or absent if the finish removed it — and SHALL restore only the ingredients that pass: adding the count back, or recreating a removed item with its former name, category, and manual-category flag. Ingredients changed elsewhere in the interim SHALL be left as-is and the user SHALL be told so. Letting the control expire SHALL change nothing further; At Home quantities remain directly editable as the permanent correction path.

#### Scenario: Full reversal

- **WHEN** a finish reduced "Onion" from 5 to 2 and removed "Butter" ×1, and the user activates undo
- **THEN** At Home shows "Onion" ×5 and "Butter" ×1 again, with butter's category and manual flag as before

#### Scenario: Partial reversal after a concurrent edit

- **WHEN** a finish reduced "Onion" to 2, a household member then set it to 4, and the user activates undo
- **THEN** "Onion" stays at 4, every other ingredient is restored, and the user is told that "Onion" was changed elsewhere and left as-is

#### Scenario: A removed item was re-added before undo

- **WHEN** a finish removed "Butter", someone then added "Butter" ×2 at home, and the user activates undo
- **THEN** "Butter" stays at 2, the other ingredients are restored, and the user is told that "Butter" was changed elsewhere

#### Scenario: Undo expires

- **WHEN** the user lets the undo control disappear
- **THEN** the reduced quantities stand and nothing further changes
